#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${UNAPPROVED_NAMESPACE:=kube-system}"

export KUBECONFIG="$PLATFORM_KUBECONFIG"

required=(
  "get namespaces _cluster"
  "list namespaces _cluster"
  "get mariadbs.k8s.mariadb.com default"
  "create mariadbs.k8s.mariadb.com ${RUNTIME_NAMESPACE}"
  "patch frappebenches.vyogo.tech ${RUNTIME_NAMESPACE}"
  "delete frappebenches.vyogo.tech ${RUNTIME_NAMESPACE}"
  "patch frappesites.vyogo.tech ${RUNTIME_NAMESPACE}"
  "delete frappesites.vyogo.tech ${RUNTIME_NAMESPACE}"
  "delete mariadbs.k8s.mariadb.com ${RUNTIME_NAMESPACE}"
  "get secrets ${RUNTIME_NAMESPACE}"
  "create secrets ${RUNTIME_NAMESPACE}"
  "delete secrets ${RUNTIME_NAMESPACE}"
  "create configmaps ${RUNTIME_NAMESPACE}"
  "delete configmaps ${RUNTIME_NAMESPACE}"
  "create jobs.batch ${RUNTIME_NAMESPACE}"
  "delete jobs.batch ${RUNTIME_NAMESPACE}"
  "list configmaps ${RUNTIME_NAMESPACE}"
  "delete persistentvolumeclaims ${RUNTIME_NAMESPACE}"
  "list pods ${RUNTIME_NAMESPACE}"
  "delete pods ${RUNTIME_NAMESPACE}"
  "list services ${RUNTIME_NAMESPACE}"
  "list jobs.batch ${RUNTIME_NAMESPACE}"
  "list persistentvolumeclaims ${RUNTIME_NAMESPACE}"
  "list events ${RUNTIME_NAMESPACE}"
  "get ingresses.networking.k8s.io ${RUNTIME_NAMESPACE}"
)

denied=(
  "patch mariadbs.k8s.mariadb.com default"
  "delete mariadbs.k8s.mariadb.com default"
  "get nodes _cluster"
  "get customresourcedefinitions.apiextensions.k8s.io _cluster"
  "create namespaces _cluster"
  "delete namespaces _cluster"
  "patch namespaces _cluster"
  "patch storageclasses.storage.k8s.io _cluster"
  "patch deployments.apps kube-system"
  "patch deployments.apps frappe-operator-system"
  "patch deployments.apps mariadb-operator-system"
  "patch deployments.apps traefik"
  "get secrets default"
  "get secrets traefik"
  "delete secrets default"
  "delete secrets traefik"
  "get pods/log ${RUNTIME_NAMESPACE}"
  "delete pods default"
  "delete frappebenches.vyogo.tech default"
  "delete frappesites.vyogo.tech default"
  "list secrets ${RUNTIME_NAMESPACE}"
  "create jobs.batch default"
  "create configmaps default"
  "list pods ${UNAPPROVED_NAMESPACE}"
  "create secrets ${UNAPPROVED_NAMESPACE}"
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
kubectl get namespace "$RUNTIME_NAMESPACE" \
  -o jsonpath='{.metadata.labels.lenscloud\.io/runtime-namespace}{" "}{.metadata.labels.lenscloud\.io/managed-by}{"\n"}'
kubectl get frappebench,frappesite -n "$RUNTIME_NAMESPACE"

echo "Restricted LensCloud Platform RBAC verification passed for ${RUNTIME_NAMESPACE}."
