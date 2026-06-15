#!/usr/bin/env bash
set -euo pipefail

: "${WILDCARD_TARGET:=116.203.22.81}"
: "${WILDCARD_HTTPS_PORT:=443}"
: "${ALLOW_INSECURE_TLS:=false}"
: "${WILDCARD_SMOKE_HOST:=wildcard-smoke.cloud.lmnaslens.com}"

./scripts/41-create-smoke-secrets.sh
tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
sed "s/wildcard-smoke\\.cloud\\.lmnaslens\\.com/${WILDCARD_SMOKE_HOST}/g" \
  manifests/smoke/wildcard-site.yaml >"$tmp_manifest"
kubectl apply -f "$tmp_manifest"
kubectl wait --for=jsonpath='{.status.phase}'=Ready frappesite/wildcard-smoke --timeout=20m

test -z "$(kubectl get certificates -A --no-headers 2>/dev/null || true)"
test -z "$(kubectl get dnsrecords -A --no-headers 2>/dev/null || true)"

curl_args=(-fsSI)
if test "$ALLOW_INSECURE_TLS" = "true"; then
  curl_args+=(-k)
fi

curl "${curl_args[@]}" \
  --resolve "${WILDCARD_SMOKE_HOST}:${WILDCARD_HTTPS_PORT}:${WILDCARD_TARGET}" \
  "https://${WILDCARD_SMOKE_HOST}:${WILDCARD_HTTPS_PORT}/" | head

kubectl get ingress wildcard-smoke-ingress -n default -o yaml
echo "Wildcard route smoke passed without per-Site DNS or Certificate resources."
