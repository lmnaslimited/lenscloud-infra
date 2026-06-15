#!/usr/bin/env bash
set -euo pipefail

: "${HEADLAMP_HOST:=headlamp.cloud.lmnaslens.com}"

kubectl apply -f manifests/ui/headlamp-helmchart.yaml
tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
sed "s/headlamp\\.cloud\\.lmnaslens\\.com/${HEADLAMP_HOST}/g" \
  manifests/ui/headlamp-ingress.yaml >"$tmp_manifest"
kubectl apply -f "$tmp_manifest"

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
