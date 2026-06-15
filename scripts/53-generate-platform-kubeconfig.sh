#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_API_SERVER:=https://116.203.22.81:6443}"
: "${OUTPUT_PATH:=.artifacts/lenscloud-eu.kubeconfig}"
: "${PLATFORM_CLUSTER_NAME:=lenscloud-eu-dev}"
: "${PLATFORM_RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${PLATFORM_CONTEXT_NAME:=lenscloud-platform@${PLATFORM_CLUSTER_NAME}}"

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
  - name: ${PLATFORM_CLUSTER_NAME}
    cluster:
      server: ${PLATFORM_API_SERVER}
      certificate-authority-data: ${ca_data}
users:
  - name: lenscloud-platform
    user:
      token: ${token}
contexts:
  - name: ${PLATFORM_CONTEXT_NAME}
    context:
      cluster: ${PLATFORM_CLUSTER_NAME}
      user: lenscloud-platform
      namespace: ${PLATFORM_RUNTIME_NAMESPACE}
current-context: ${PLATFORM_CONTEXT_NAME}
EOF

chmod 600 "$OUTPUT_PATH"
echo "Restricted kubeconfig written to ${OUTPUT_PATH}."
