#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/ui/headlamp-helmchart.yaml
kubectl apply -f manifests/ui/headlamp-ingress.yaml

for _ in $(seq 1 90); do
  if kubectl -n headlamp get deployment headlamp >/dev/null 2>&1; then
    kubectl -n headlamp rollout status deployment/headlamp --timeout=180s
    break
  fi
  sleep 2
done

kubectl -n headlamp get pods,svc,ingress

cat <<'EOF'
Headlamp token:
kubectl -n headlamp create token headlamp-frappe-operator
EOF
