#!/bin/bash
set -e

# agar cluster pehle se hai toh skip karo
if ! kind get clusters | grep -q "voting"; then
  kind create cluster --name voting --config kind-config.yaml
else
  echo "Cluster already running hai, skip kar rahe hain"
fi

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

helm upgrade --install voting ./helm/voting-app \
  --namespace voting \
  --create-namespace

kubectl wait --namespace voting \
  --for=condition=ready pod \
  --selector=app=vote \
  --timeout=120s

echo "127.0.0.1 vote.local result.local" | sudo tee -a /etc/hosts

echo "Done! Open http://vote.local"