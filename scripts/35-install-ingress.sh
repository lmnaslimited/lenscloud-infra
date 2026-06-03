#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/ingress/ingress-nginx-helmchart.yaml

echo "Waiting for ingress-nginx controller..."
for _ in $(seq 1 90); do
  if kubectl -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; then
    kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
    kubectl -n ingress-nginx get pods,svc
    exit 0
  fi
  sleep 2
done

kubectl -n kube-system get helmchart ingress-nginx -o yaml || true
kubectl get pods -A
exit 1

