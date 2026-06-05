#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/ingress/traefik-nodeport-helmchart.yaml

echo "Waiting for Traefik..."
for _ in $(seq 1 120); do
  if kubectl -n traefik get deployment traefik >/dev/null 2>&1; then
    kubectl -n traefik rollout status deployment/traefik --timeout=240s
    kubectl -n traefik get pods,svc,ingressclass
    exit 0
  fi
  sleep 2
done

kubectl -n kube-system get helmchart traefik -o yaml || true
kubectl get pods -A
exit 1
