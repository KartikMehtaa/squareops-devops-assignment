# SquareOps DevOps Take-Home Assignment
> Docker Voting App — deployed on local Kubernetes using Helm + kind

---

## Architecture

```
                        ┌─────────────────────────────────┐
                        │         NGINX Ingress            │
                        │   vote.local / result.local      │
                        └────────────┬────────────┬────────┘
                                     │            │
                              ┌──────▼──┐    ┌────▼─────┐
                              │  vote   │    │  result  │
                              │ (Flask) │    │ (Node.js)│
                              └──────┬──┘    └────┬─────┘
                                     │            │
                              ┌──────▼──┐    ┌────▼─────┐
                              │  Redis  │    │ Postgres │
                              │ (queue) │    │   (db)   │
                              └─────────┘    └──────────┘
                                     │            ▲
                                ┌────▼────────────┤
                                │     worker      │
                                │    (.NET)       │
                                └─────────────────┘
```

**Flow:** User votes on `vote` app → vote goes to Redis queue → `worker` reads from Redis and writes to Postgres → `result` app reads from Postgres and shows live results.

---

## What Changed vs Original Manifests

| Original | What I Changed | Why |
|---|---|---|
| Plain Deployments for all services | Postgres converted to **StatefulSet** | Stable identity, ordered restarts, PVC per pod |
| NodePort services | **Ingress (NGINX)** for vote + result | Single entry point, no random ports |
| No resource limits | **requests + limits** on every container | Prevents one pod eating all cluster resources |
| No health checks | **liveness + readiness probes** on every pod | Kubernetes knows when pod is actually ready |
| Postgres password in plain YAML | Moved to **Kubernetes Secret** | Credentials nahi dikhne chahiye plain text mein |
| Raw YAML manifests | Rewritten as **Helm chart** | Reusable, configurable, environment-friendly |
| No persistent storage | **PersistentVolumeClaim** for Postgres | Data survives pod restarts |

---

## Prerequisites

Make sure these are installed:

```bash
kind version        # v0.23+
kubectl version     # v1.28+
helm version        # v3.0+
docker version      # 24+
jenkins --version   # 2.400+
```

Install links:
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [helm](https://helm.sh/docs/intro/install/)
- [Jenkins](https://www.jenkins.io/doc/book/installing/linux/)

---

## Quick Start (Single Command)

```bash
git clone https://github.com/KartikMehtaa/squareops-devops-assignment.git
cd squareops-devops-assignment
chmod +x bootstrap.sh
./bootstrap.sh
```

Script automatically:
1. Creates a `kind` cluster (1 control-plane + 2 workers)
2. Deploys NGINX Ingress Controller
3. Deploys the voting app via Helm
4. Updates your hosts file (auto-detects WSL / Mac / Linux)

Then open:
- **Vote app** → http://vote.local
- **Result app** → http://result.local

---

## Step-by-Step (Manual)

### 1. Create kind cluster

```bash
kind create cluster --name voting --config kind-config.yaml
kubectl config use-context kind-voting
```

### 2. Deploy NGINX Ingress

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 3. Deploy voting app

```bash
helm upgrade --install voting-app ./voting-app \
  --namespace voting \
  --create-namespace \
  --wait \
  --timeout 120s
```

### 4. Update hosts file

**WSL:**
```bash
echo "127.0.0.1 vote.local result.local" | sudo tee -a /mnt/c/Windows/System32/drivers/etc/hosts
```

**Mac / Linux:**
```bash
echo "127.0.0.1 vote.local result.local" | sudo tee -a /etc/hosts
```

### 5. Open in browser

- http://vote.local
- http://result.local

---

## Repo Structure

```
squareops-devops-assignment/
├── voting-app/               # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── db-statefulset.yaml
│       ├── db-service.yaml
│       ├── redis-deployment.yaml
│       ├── redis-service.yaml
│       ├── vote-deployment.yaml
│       ├── vote-service.yaml
│       ├── result-deployment.yaml
│       ├── result-service.yaml
│       ├── worker-deployment.yaml
│       ├── secret.yaml
│       └── ingress.yaml
├── Jenkinsfile               # CI/CD pipeline
├── kind-config.yaml
├── bootstrap.sh
└── README.md
```

---

## CI/CD Pipeline (Jenkins)

Pipeline is self-hosted on **Jenkins running inside WSL**, triggered via **GitHub webhook + ngrok tunnel**.

### How it works

```
Push to vote/** on GitHub
        │
        ▼
GitHub Webhook → ngrok tunnel → Jenkins (WSL:8080)
        │
        ▼
Checkout → Lint Python → Lint Manifests → Build Image → Push to Docker Hub → Smoke Test (kind)
```

### Stage breakdown

| Stage | Tool | What it checks |
|---|---|---|
| Checkout | git | Latest code from main branch |
| Lint Python | `flake8` | Code style, syntax errors in vote/ |
| Lint Manifests | `yamllint` | YAML syntax in Helm templates |
| Build Image | `docker build` | Image builds without errors |
| Push | Docker Hub | Image pushed to `kartikmehta/squareops-assessments` |
| Smoke Test | `kind` + `kubectl` | Vote endpoint returns HTTP 200 |

### Jenkins setup (local WSL)

**1. Start Jenkins**
```bash
sudo systemctl start jenkins
# Jenkins runs at http://localhost:8080
```

**2. Required plugins**
- Git Plugin
- Pipeline Plugin
- Docker Pipeline Plugin
- GitHub Integration Plugin
- Blue Ocean (optional, for better UI)

**3. Create pipeline job**
```
New Item → Pipeline → Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/KartikMehtaa/squareops-devops-assignment.git
Script Path: Jenkinsfile
```

**4. Add Docker Hub credentials**
```
Manage Jenkins → Credentials → Add
Kind: Username with password
ID: docker-creds
```

### Webhook setup (ngrok)

Since Jenkins runs locally on WSL, ngrok is used to expose it to GitHub:

```bash
# Terminal 1 — Jenkins start karo
sudo systemctl start jenkins

# Terminal 2 — ngrok tunnel banao
ngrok http 8080
# Copy the https URL e.g. https://abc123.ngrok.io
```

GitHub mein webhook add karo:
```
Repo → Settings → Webhooks → Add webhook
Payload URL: https://abc123.ngrok.io/github-webhook/
Content type: application/json
Trigger: Just the push event
```

> **Note:** ngrok URL har restart pe change hoti hai. Video walkthrough se pehle `ngrok http 8080` zaroor run karo.

### Trigger pipeline manually

```
Jenkins → voting-app-pipeline → Build Now
```

---

## Troubleshooting

### Pods not coming up

```bash
# Saare pods ka status dekho
kubectl get pods -n voting

# Specific pod ka detail dekho
kubectl describe pod <pod-name> -n voting

# Logs dekho
kubectl logs <pod-name> -n voting
```

Common reasons:
- `ImagePullBackOff` → image name galat hai `values.yaml` mein
- `Pending` → PVC bind nahi hua, `kubectl get pvc -n voting` check karo
- `CrashLoopBackOff` → `kubectl logs` se error dekho

---

### Vote result app mein nahi aa raha

```bash
# 1. Worker running hai?
kubectl get pods -n voting -l app=worker

# 2. Worker ke logs mein error hai?
kubectl logs -l app=worker -n voting

# 3. Postgres ready hai?
kubectl exec -it <db-pod-name> -n voting -- pg_isready -U postgres

# 4. Redis mein votes hain?
kubectl exec -it <redis-pod-name> -n voting -- redis-cli LLEN votes
```

Most common cause: `worker` pod Postgres se connect nahi kar pa raha — Secret correctly mount hua hai ya nahi check karo.

---

### Ingress kaam nahi kar raha (vote.local nahi khul raha)

```bash
# Ingress controller running hai?
kubectl get pods -n ingress-nginx

# Ingress resource check karo
kubectl get ingress -n voting
kubectl describe ingress voting-app-ingress -n voting

# Hosts file mein entry hai?
cat /etc/hosts | grep vote.local
```

Common fix — manually add karo:
```
127.0.0.1 vote.local result.local
```

---

### Jenkins pipeline trigger nahi ho rahi (webhook issue)

```bash
# 1. ngrok chalu hai?
ngrok http 8080

# 2. GitHub webhook delivery check karo
# Repo → Settings → Webhooks → Recent Deliveries
# Green tick hona chahiye, red X nahi

# 3. Jenkins mein GitHub hook trigger enabled hai?
# Job → Configure → Build Triggers
# ✅ GitHub hook trigger for GITScm polling — checked hona chahiye

# 4. ngrok URL change ho gayi?
# GitHub webhook mein naya URL update karo
```

---

## Trade-offs & What I'd Do Differently

### Trade-offs made

| Decision | Why | Trade-off |
|---|---|---|
| Self-hosted Jenkins on WSL | Full control, no cost | ngrok dependency for webhooks |
| Single Postgres replica | Simple for local dev | Not HA — production mein replica chahiye |
| `yamllint` for manifest lint | Easy to install | `kube-linter` zyada checks karta hai |
| `latest` tag for upstream images | Convenience | Not reproducible — pinned tags better hote |

### With more time I would

- Add **NetworkPolicies** — only `vote` → `redis`, only `worker` → `db`
- Add **HorizontalPodAutoscaler** on vote service (CPU metric)
- Add **ArgoCD** for GitOps
- Use **sealed-secrets** for proper secret management
- Add `values-dev.yaml` and `values-staging.yaml`
- Move to **GitHub Actions** for simpler webhook setup

---

## Video Walkthrough

[Link here — Loom/YouTube]

---

## Author

**Kartik Mehta**
GitHub: [@KartikMehtaa](https://github.com/KartikMehtaa)
