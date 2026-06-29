#!/bin/bash
set -e

# ── Colours for readable output ──────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}==> $1${NC}"; }
warning() { echo -e "${YELLOW}==> $1${NC}"; }

# ── Step 1: Kind cluster ──────────────────────────────────────────────────────
info "Step 1: Kind cluster bana rahe hain..."
if kind get clusters 2>/dev/null | grep -q "^voting$"; then
  warning "Cluster 'voting' already exists, skip kar rahe hain"
else
  kind create cluster --name voting --config kind-config.yaml
  info "Cluster ready!"
fi

# ── Set kubectl context explicitly ────────────────────────────────────────────
kubectl config use-context kind-voting

# ── Step 2: Ingress NGINX ─────────────────────────────────────────────────────
info "Step 2: Ingress NGINX deploy kar rahe hain..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# ── Step 3: Wait for ingress controller ──────────────────────────────────────
info "Step 3: Ingress controller ready hone ka wait kar rahe hain..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# ── Step 4: Deploy via Helm ───────────────────────────────────────────────────
info "Step 4: Voting app deploy kar rahe hain..."
helm upgrade --install voting-app ./voting-app \
  --namespace voting \
  --create-namespace \
  --values voting-app/values.yaml \
  --wait \
  --timeout 120s

# ── Step 5: Wait for all pods ────────────────────────────────────────────────
info "Step 5: Saare pods ready hone ka wait kar rahe hain..."
for app in vote result worker db redis; do
  echo "   Waiting for: $app"
  kubectl wait --namespace voting \
    --for=condition=ready pod \
    --selector=app=$app \
    --timeout=120s
done

# ── Step 6: Hosts file ───────────────────────────────────────────────────────
info "Step 6: Hosts file check kar rahe hain..."

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
  # Windows / WSL
  HOSTS_FILE="/mnt/c/Windows/System32/drivers/etc/hosts"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  HOSTS_FILE="/etc/hosts"
else
  # Linux
  HOSTS_FILE="/etc/hosts"
fi

ENTRY="127.0.0.1 vote.local result.local"
if grep -q "vote.local" "$HOSTS_FILE" 2>/dev/null; then
  warning "Hosts entry already exists, skip kar rahe hain"
else
  echo "$ENTRY" | sudo tee -a "$HOSTS_FILE" > /dev/null
  info "Hosts file updated: $HOSTS_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " Sab kuch ready hai!"
echo " Vote App    --> http://vote.local"
echo " Result App  --> http://result.local"
echo "=========================================="