#!/usr/bin/env bash
set -euo pipefail

: "${GODADDY_API_KEY:?Set GODADDY_API_KEY}"
: "${GODADDY_API_SECRET:?Set GODADDY_API_SECRET}"

credentials="$(mktemp)"
trap 'rm -f "$credentials"' EXIT
chmod 600 "$credentials"

cat >"$credentials" <<EOF
dns_godaddy_key = ${GODADDY_API_KEY}
dns_godaddy_secret = ${GODADDY_API_SECRET}
EOF

kubectl create namespace lenscloud-edge --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lenscloud-edge create secret generic godaddy-dns-api \
  --from-file=credentials.ini="$credentials" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "GoDaddy credentials stored in Kubernetes Secret lenscloud-edge/godaddy-dns-api."
