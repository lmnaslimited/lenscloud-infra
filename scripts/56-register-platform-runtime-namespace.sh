#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_SYSTEM_NAMESPACE:=lenscloud-platform-system}"
: "${PLATFORM_SERVICE_ACCOUNT:=lenscloud-platform}"
: "${ROLE_NAME:=lenscloud-platform-runtime}"
: "${DRY_RUN:=false}"

namespace="${RUNTIME_NAMESPACE:-}"
customer="${RUNTIME_CUSTOMER:-}"
purpose="${RUNTIME_PURPOSE:-}"
region="${RUNTIME_REGION:-}"
cluster="${RUNTIME_CLUSTER:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/56-register-platform-runtime-namespace.sh --namespace NAME [options]

Options:
  --namespace NAME       Runtime namespace to create or update.
  --customer VALUE      Optional customer identifier label.
  --purpose VALUE       Optional purpose/tier label: public, private-shared,
                        private, enterprise, or another platform-approved value.
  --region VALUE        Optional region label value.
  --cluster VALUE       Optional cluster label value.
  --dry-run             Render server-side dry-run output without mutating.
  -h, --help            Show this help.

Environment equivalents:
  RUNTIME_NAMESPACE, RUNTIME_CUSTOMER, RUNTIME_PURPOSE, RUNTIME_REGION,
  RUNTIME_CLUSTER, DRY_RUN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      namespace="${2:-}"
      shift 2
      ;;
    --customer)
      customer="${2:-}"
      shift 2
      ;;
    --purpose)
      purpose="${2:-}"
      shift 2
      ;;
    --region)
      region="${2:-}"
      shift 2
      ;;
    --cluster)
      cluster="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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

if [[ -z "$namespace" ]]; then
  echo "--namespace is required." >&2
  usage >&2
  exit 2
fi

if [[ ! "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "Invalid Kubernetes namespace name: $namespace" >&2
  exit 2
fi

label_lines=(
  "    lenscloud.io/runtime-namespace: \"true\""
  "    lenscloud.io/managed-by: platform"
  "    lenscloud.io/managed-runtime: \"true\""
)

if [[ -n "$customer" ]]; then
  label_lines+=("    lenscloud.io/customer: ${customer}")
fi
if [[ -n "$purpose" ]]; then
  label_lines+=("    lenscloud.io/runtime-purpose: ${purpose}")
fi
if [[ -n "$region" ]]; then
  label_lines+=("    lenscloud.io/region: ${region}")
fi
if [[ -n "$cluster" ]]; then
  label_lines+=("    lenscloud.io/cluster: ${cluster}")
fi

apply_args=(apply -f -)
if [[ "$DRY_RUN" == "true" ]]; then
  apply_args+=(--dry-run=server -o yaml)
fi

{
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
  labels:
EOF
  printf '%s\n' "${label_lines[@]}"
  cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${namespace}
rules:
  - apiGroups:
      - k8s.mariadb.com
    resources:
      - mariadbs
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - vyogo.tech
    resources:
      - frappebenches
      - frappesites
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
    resources:
      - services
      - persistentvolumeclaims
      - configmaps
      - events
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - list
      - watch
      - delete
  - apiGroups:
      - ""
    resources:
      - configmaps
    verbs:
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
    resources:
      - persistentvolumeclaims
    verbs:
      - delete
  - apiGroups:
      - batch
    resources:
      - jobs
    verbs:
      - create
      - get
      - list
      - watch
      - delete
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
      - create
      - update
      - patch
      - delete
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLE_NAME}
  namespace: ${namespace}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${ROLE_NAME}
subjects:
  - kind: ServiceAccount
    name: ${PLATFORM_SERVICE_ACCOUNT}
    namespace: ${PLATFORM_SYSTEM_NAMESPACE}
EOF
} | kubectl "${apply_args[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run completed for Platform runtime namespace ${namespace}."
else
  echo "Platform runtime namespace ${namespace} registered or updated."
  echo "Labels: lenscloud.io/runtime-namespace=true lenscloud.io/managed-by=platform"
  echo "RBAC: RoleBinding ${namespace}/${ROLE_NAME} -> ${PLATFORM_SYSTEM_NAMESPACE}/${PLATFORM_SERVICE_ACCOUNT}"
fi
