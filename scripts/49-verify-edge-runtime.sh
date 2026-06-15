#!/usr/bin/env bash
set -euo pipefail

: "${WILDCARD_TARGET:=116.203.22.81}"
: "${WILDCARD_SMOKE_HOST:=wildcard-smoke.cloud.lmnaslens.com}"
: "${HEADLAMP_HOST:=headlamp.cloud.lmnaslens.com}"

kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl -n traefik get deployment,service,secret,tlsstore
kubectl -n lenscloud-edge get job,cronjob,pvc
kubectl get ingress -A -o wide

expiry="$(
  kubectl -n traefik get secret lenscloud-cloud-wildcard-tls \
    -o jsonpath='{.data.tls\.crt}' |
  base64 -d |
  openssl x509 -noout -enddate
)"
echo "$expiry"

curl -fsSI --resolve "${WILDCARD_SMOKE_HOST}:443:${WILDCARD_TARGET}" \
  "https://${WILDCARD_SMOKE_HOST}/" | head
curl -fsSI --resolve "${HEADLAMP_HOST}:443:${WILDCARD_TARGET}" \
  "https://${HEADLAMP_HOST}/" | head

echo "EU wildcard edge verification passed."
