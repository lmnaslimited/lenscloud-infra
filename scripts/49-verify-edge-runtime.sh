#!/usr/bin/env bash
set -euo pipefail

: "${WILDCARD_TARGET:=116.203.22.81}"

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

curl -fsSI --resolve "wildcard-smoke.cloud.lmnaslens.com:443:${WILDCARD_TARGET}" \
  https://wildcard-smoke.cloud.lmnaslens.com/ | head
curl -fsSI --resolve "headlamp.cloud.lmnaslens.com:443:${WILDCARD_TARGET}" \
  https://headlamp.cloud.lmnaslens.com/ | head

echo "EU wildcard edge verification passed."
