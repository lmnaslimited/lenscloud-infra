#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=}"
: "${UNAPPROVED_NAMESPACE:=kube-system}"
: "${PUBLIC_DATABASE_NAMESPACE:=default}"
: "${PUBLIC_DATABASE_NAME:=frappe-mariadb}"

usage() {
  cat <<'EOF'
Usage:
  scripts/57-verify-platform-runtime-namespace.sh --namespace NAME [options]

Options:
  --namespace NAME              Approved Platform runtime namespace to verify.
  --platform-kubeconfig PATH    Restricted Platform kubeconfig.
  --unapproved-namespace NAME   Namespace that must remain inaccessible.
                                Default: kube-system.
  --public-db-namespace NAME    Protected shared MariaDB namespace. Default: default.
  --public-db-name NAME         Protected shared MariaDB name. Default: frappe-mariadb.
  -h, --help                    Show this help.

Environment equivalents:
  PLATFORM_KUBECONFIG, RUNTIME_NAMESPACE, UNAPPROVED_NAMESPACE,
  PUBLIC_DATABASE_NAMESPACE, PUBLIC_DATABASE_NAME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      RUNTIME_NAMESPACE="${2:-}"
      shift 2
      ;;
    --platform-kubeconfig)
      PLATFORM_KUBECONFIG="${2:-}"
      shift 2
      ;;
    --unapproved-namespace)
      UNAPPROVED_NAMESPACE="${2:-}"
      shift 2
      ;;
    --public-db-namespace)
      PUBLIC_DATABASE_NAMESPACE="${2:-}"
      shift 2
      ;;
    --public-db-name)
      PUBLIC_DATABASE_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$RUNTIME_NAMESPACE" ]]; then
  echo "--namespace is required." >&2
  usage >&2
  exit 2
fi

platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

expect_yes() {
  local verb="$1" resource="$2" namespace="${3:-}"
  local args=(auth can-i "$verb" "$resource")
  if [[ -n "$namespace" && "$namespace" != "_cluster" ]]; then
    args+=(-n "$namespace")
  fi
  local result
  result="$("${platform[@]}" "${args[@]}" 2>/dev/null || true)"
  if [[ "$result" != "yes" ]]; then
    echo "Expected allow failed: ${verb} ${resource} ${namespace:-_cluster}" >&2
    exit 1
  fi
}

expect_no() {
  local verb="$1" resource="$2" namespace="${3:-}"
  local args=(auth can-i "$verb" "$resource")
  if [[ -n "$namespace" && "$namespace" != "_cluster" ]]; then
    args+=(-n "$namespace")
  fi
  local result
  result="$("${platform[@]}" "${args[@]}" 2>/dev/null || true)"
  if [[ "$result" != "no" ]]; then
    echo "Expected denial failed: ${verb} ${resource} ${namespace:-_cluster}" >&2
    exit 1
  fi
}

label_runtime="$("${platform[@]}" get namespace "$RUNTIME_NAMESPACE" \
  -o jsonpath='{.metadata.labels.lenscloud\.io/runtime-namespace}' 2>/dev/null || true)"
label_managed="$("${platform[@]}" get namespace "$RUNTIME_NAMESPACE" \
  -o jsonpath='{.metadata.labels.lenscloud\.io/managed-by}' 2>/dev/null || true)"

if [[ "$label_runtime" != "true" || "$label_managed" != "platform" ]]; then
  echo "Namespace ${RUNTIME_NAMESPACE} is missing required Platform labels." >&2
  echo "Expected: lenscloud.io/runtime-namespace=true lenscloud.io/managed-by=platform" >&2
  exit 1
fi

expect_yes get namespaces _cluster
expect_yes list namespaces _cluster
expect_yes create mariadbs.k8s.mariadb.com "$RUNTIME_NAMESPACE"
expect_yes patch mariadbs.k8s.mariadb.com "$RUNTIME_NAMESPACE"
expect_yes delete mariadbs.k8s.mariadb.com "$RUNTIME_NAMESPACE"
expect_yes create frappebenches.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes patch frappebenches.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes delete frappebenches.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes create frappesites.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes patch frappesites.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes delete frappesites.vyogo.tech "$RUNTIME_NAMESPACE"
expect_yes list pods "$RUNTIME_NAMESPACE"
expect_yes delete pods "$RUNTIME_NAMESPACE"
expect_yes list services "$RUNTIME_NAMESPACE"
expect_yes list persistentvolumeclaims "$RUNTIME_NAMESPACE"
expect_yes delete persistentvolumeclaims "$RUNTIME_NAMESPACE"
expect_yes list jobs.batch "$RUNTIME_NAMESPACE"
expect_yes delete jobs.batch "$RUNTIME_NAMESPACE"
expect_yes list ingresses.networking.k8s.io "$RUNTIME_NAMESPACE"
expect_yes list events "$RUNTIME_NAMESPACE"
expect_yes get secrets "$RUNTIME_NAMESPACE"
expect_yes create secrets "$RUNTIME_NAMESPACE"
expect_yes patch secrets "$RUNTIME_NAMESPACE"
expect_yes delete secrets "$RUNTIME_NAMESPACE"

expect_no list secrets "$RUNTIME_NAMESPACE"
expect_no create namespaces _cluster
expect_no patch namespaces _cluster
expect_no delete namespaces _cluster
expect_no patch customresourcedefinitions.apiextensions.k8s.io _cluster
expect_no patch nodes _cluster
expect_no patch mariadbs.k8s.mariadb.com "$PUBLIC_DATABASE_NAMESPACE"
expect_no delete mariadbs.k8s.mariadb.com "$PUBLIC_DATABASE_NAMESPACE"
expect_no get secrets "$PUBLIC_DATABASE_NAMESPACE"
expect_no get pods/log "$RUNTIME_NAMESPACE"
expect_no delete pods "$PUBLIC_DATABASE_NAMESPACE"
expect_no list pods "$UNAPPROVED_NAMESPACE"
expect_no create secrets "$UNAPPROVED_NAMESPACE"
expect_no delete frappebenches.vyogo.tech "$UNAPPROVED_NAMESPACE"
expect_no delete frappesites.vyogo.tech "$UNAPPROVED_NAMESPACE"

"${platform[@]}" -n "$PUBLIC_DATABASE_NAMESPACE" \
  get mariadb "$PUBLIC_DATABASE_NAME" -o name >/dev/null

cat <<EOF
Platform runtime namespace verification passed.
Namespace: ${RUNTIME_NAMESPACE}
Required labels: present
Namespace list: allowed for label discovery
Namespace mutation: denied
Protected MariaDB mutation: denied
Unapproved namespace access checked against: ${UNAPPROVED_NAMESPACE}
EOF
