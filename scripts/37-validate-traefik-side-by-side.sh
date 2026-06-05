#!/usr/bin/env bash
set -euo pipefail

: "${WORKER_PRIVATE_IP:=10.20.1.2}"
: "${SMOKE_HOST:=traefik-smoke.cloud.lmnaslens.com}"

kubectl apply -f manifests/ingress/traefik-smoke.yaml
kubectl -n default rollout status deployment/traefik-smoke --timeout=180s

response="$(curl -ksS --resolve "${SMOKE_HOST}:30443:${WORKER_PRIVATE_IP}" "https://${SMOKE_HOST}:30443/")"
grep -q "traefik-side-by-side-ok" <<<"$response"

kubectl get ingress traefik-smoke -n default -o wide
echo "Traefik side-by-side validation passed."
