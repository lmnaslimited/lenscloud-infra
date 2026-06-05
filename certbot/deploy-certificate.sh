#!/usr/bin/env sh
set -eu

: "${RENEWED_LINEAGE:?Certbot did not provide RENEWED_LINEAGE}"
: "${TLS_SECRET_NAMESPACE:=traefik}"
: "${TLS_SECRET_NAME:=lenscloud-cloud-wildcard-tls}"

kubectl -n "$TLS_SECRET_NAMESPACE" create secret tls "$TLS_SECRET_NAME" \
  --cert="$RENEWED_LINEAGE/fullchain.pem" \
  --key="$RENEWED_LINEAGE/privkey.pem" \
  --dry-run=client -o yaml | kubectl apply -f -
