#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_API_SERVER:=https://116.203.22.81:6443}"
: "${OUTPUT_PATH:=.artifacts/lenscloud-eu.kubeconfig}"

mkdir -p "$(dirname "$OUTPUT_PATH")"
umask 077

token="$(
  kubectl -n lenscloud-platform-system \
    get secret lenscloud-platform-token \
    -o jsonpath='{.data.token}' |
    base64 -d
)"
ca_data="$(
  kubectl -n lenscloud-platform-system \
    get secret lenscloud-platform-token \
    -o jsonpath='{.data.ca\.crt}'
)"

if [[ -z "$token" || -z "$ca_data" ]]; then
  echo "Service-account token or CA data is unavailable." >&2
  exit 1
fi

cat >"$OUTPUT_PATH" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: lenscloud-eu-dev
    cluster:
      server: ${PLATFORM_API_SERVER}
      certificate-authority-data: ${ca_data}
users:
  - name: lenscloud-platform
    user:
      token: ${token}
contexts:
  - name: lenscloud-platform@lenscloud-eu-dev
    context:
      cluster: lenscloud-eu-dev
      user: lenscloud-platform
      namespace: lenscloud-runtime-eu
current-context: lenscloud-platform@lenscloud-eu-dev
EOF

chmod 600 "$OUTPUT_PATH"
echo "Restricted kubeconfig written to ${OUTPUT_PATH}."
