#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"

export KUBECONFIG="$PLATFORM_KUBECONFIG"

required=(
  "get mariadbs.k8s.mariadb.com default"
  "create mariadbs.k8s.mariadb.com lenscloud-runtime-eu"
  "patch frappebenches.vyogo.tech lenscloud-runtime-eu"
  "delete frappebenches.vyogo.tech lenscloud-runtime-eu"
  "patch frappesites.vyogo.tech lenscloud-runtime-eu"
  "delete frappesites.vyogo.tech lenscloud-runtime-eu"
  "delete mariadbs.k8s.mariadb.com lenscloud-runtime-eu"
  "get secrets lenscloud-runtime-eu"
  "create secrets lenscloud-runtime-eu"
  "delete secrets lenscloud-runtime-eu"
  "delete jobs.batch lenscloud-runtime-eu"
  "delete persistentvolumeclaims lenscloud-runtime-eu"
  "list pods lenscloud-runtime-eu"
  "list services lenscloud-runtime-eu"
  "list jobs.batch lenscloud-runtime-eu"
  "list persistentvolumeclaims lenscloud-runtime-eu"
  "list events lenscloud-runtime-eu"
  "get ingresses.networking.k8s.io lenscloud-runtime-eu"
)

denied=(
  "patch mariadbs.k8s.mariadb.com default"
  "delete mariadbs.k8s.mariadb.com default"
  "get nodes _cluster"
  "get customresourcedefinitions.apiextensions.k8s.io _cluster"
  "create namespaces _cluster"
  "delete namespaces _cluster"
  "patch storageclasses.storage.k8s.io _cluster"
  "patch deployments.apps kube-system"
  "patch deployments.apps frappe-operator-system"
  "patch deployments.apps mariadb-operator-system"
  "patch deployments.apps traefik"
  "get secrets default"
  "get secrets traefik"
  "delete secrets default"
  "delete secrets traefik"
  "delete frappebenches.vyogo.tech default"
  "delete frappesites.vyogo.tech default"
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

echo "Restricted LensCloud Platform lifecycle RBAC verification passed."
