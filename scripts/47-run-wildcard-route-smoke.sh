#!/usr/bin/env bash
set -euo pipefail

: "${WILDCARD_TARGET:=116.203.22.81}"
: "${WILDCARD_HTTPS_PORT:=443}"
: "${ALLOW_INSECURE_TLS:=false}"

./scripts/41-create-smoke-secrets.sh
kubectl apply -f manifests/smoke/wildcard-site.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Ready frappesite/wildcard-smoke --timeout=20m

test -z "$(kubectl get certificates -A --no-headers 2>/dev/null || true)"
test -z "$(kubectl get dnsrecords -A --no-headers 2>/dev/null || true)"

curl_args=(-fsSI)
if test "$ALLOW_INSECURE_TLS" = "true"; then
  curl_args+=(-k)
fi

curl "${curl_args[@]}" \
  --resolve "wildcard-smoke.cloud.lmnaslens.com:${WILDCARD_HTTPS_PORT}:${WILDCARD_TARGET}" \
  "https://wildcard-smoke.cloud.lmnaslens.com:${WILDCARD_HTTPS_PORT}/" | head

kubectl get ingress wildcard-smoke-ingress -n default -o yaml
echo "Wildcard route smoke passed without per-Site DNS or Certificate resources."
