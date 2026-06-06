#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"

export KUBECONFIG="$PLATFORM_KUBECONFIG"

required=(
  "get mariadbs.k8s.mariadb.com default"
  "patch mariadbs.k8s.mariadb.com default"
  "create mariadbs.k8s.mariadb.com lenscloud-runtime-eu"
  "patch frappebenches.vyogo.tech lenscloud-runtime-eu"
  "patch frappesites.vyogo.tech lenscloud-runtime-eu"
  "get secrets lenscloud-runtime-eu"
  "create secrets lenscloud-runtime-eu"
  "get ingresses.networking.k8s.io lenscloud-runtime-eu"
)

denied=(
  "get nodes _cluster"
  "get customresourcedefinitions.apiextensions.k8s.io _cluster"
  "create namespaces _cluster"
  "patch deployments.apps kube-system"
  "get secrets default"
  "get secrets traefik"
  "list secrets lenscloud-runtime-eu"
)

for check in "${required[@]}"; do
  read -r verb resource namespace <<<"$check"
  args=(auth can-i "$verb" "$resource")
  if [[ "$namespace" != "_cluster" ]]; then
    args+=(-n "$namespace")
  fi
  result="$(kubectl "${args[@]}" 2>/dev/null || true)"
  if [[ "$result" != "yes" ]]; then
    echo "Required permission failed: ${check}" >&2
    exit 1
  fi
done

for check in "${denied[@]}"; do
  read -r verb resource namespace <<<"$check"
  args=(auth can-i "$verb" "$resource")
  if [[ "$namespace" != "_cluster" ]]; then
    args+=(-n "$namespace")
  fi
  result="$(kubectl "${args[@]}" 2>/dev/null || true)"
  if [[ "$result" != "no" ]]; then
    echo "Permission should be denied: ${check}" >&2
    exit 1
  fi
done

kubectl get mariadb frappe-mariadb -n default -o name
kubectl get frappebench,frappesite -n lenscloud-runtime-eu

echo "Restricted LensCloud Platform RBAC verification passed."
