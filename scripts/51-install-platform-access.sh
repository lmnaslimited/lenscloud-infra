#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"

kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml
kubectl wait \
  --for=jsonpath='{.type}'=kubernetes.io/service-account-token \
  secret/lenscloud-platform-token \
  -n lenscloud-platform-system \
  --timeout=60s

kubectl get serviceaccount,secret -n lenscloud-platform-system
kubectl get role,rolebinding -n default
kubectl get role,rolebinding -n lenscloud-runtime-eu

echo "Restricted LensCloud Platform service account installed."
