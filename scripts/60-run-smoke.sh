#!/usr/bin/env bash
set -euo pipefail

./scripts/41-create-smoke-secrets.sh
kubectl apply -f manifests/smoke/frappe-smoke.yaml

kubectl get mariadb,frappebench,frappesite,pvc,pods
echo "Watch readiness with:"
echo "kubectl get mariadb,frappebench,frappesite,pods,pvc -w"
