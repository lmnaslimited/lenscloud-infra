#!/usr/bin/env bash
set -euo pipefail

: "${WILDCARD_TARGET:=116.203.22.81}"
: "${WILDCARD_HTTPS_PORT:=443}"
: "${ALLOW_INSECURE_TLS:=false}"
: "${WILDCARD_SMOKE_HOST:=wildcard-smoke.cloud.lmnaslens.com}"

tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
sed "s/traefik-smoke\\.cloud\\.lmnaslens\\.com/${WILDCARD_SMOKE_HOST}/g" \
  manifests/ingress/traefik-smoke.yaml >"$tmp_manifest"

kubectl apply -f "$tmp_manifest"
kubectl -n default rollout status deployment/traefik-smoke --timeout=180s

test -z "$(kubectl get certificates -A --no-headers 2>/dev/null || true)"
test -z "$(kubectl get dnsrecords -A --no-headers 2>/dev/null || true)"

curl_args=(-fsSI)
if test "$ALLOW_INSECURE_TLS" = "true"; then
  curl_args+=(-k)
fi

curl "${curl_args[@]}" \
  --resolve "${WILDCARD_SMOKE_HOST}:${WILDCARD_HTTPS_PORT}:${WILDCARD_TARGET}" \
  "https://${WILDCARD_SMOKE_HOST}:${WILDCARD_HTTPS_PORT}/" | head

kubectl get ingress traefik-smoke -n default -o yaml
echo "Wildcard route smoke passed without per-Site DNS or Certificate resources."
