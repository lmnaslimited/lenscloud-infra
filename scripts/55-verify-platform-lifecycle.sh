#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${TEST_PREFIX:=infra-lifecycle-check}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete \
    secret "$TEST_PREFIX-managed" "$TEST_PREFIX-unowned" \
    job "$TEST_PREFIX-managed" \
    pvc "$TEST_PREFIX-managed" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

"${platform[@]}" -n "$RUNTIME_NAMESPACE" create secret generic \
  "$TEST_PREFIX-managed" \
  --from-literal=probe=redacted \
  --dry-run=client -o yaml |
  "${platform[@]}" label --local -f - \
    lenscloud.io/managed-by=platform \
    lenscloud.io/resource-kind=acceptance \
    lenscloud.io/resource-id="$TEST_PREFIX" \
    -o yaml |
  "${platform[@]}" apply -f -

"${manager[@]}" -n "$RUNTIME_NAMESPACE" create job "$TEST_PREFIX-managed" \
  --image=busybox:1.36 -- /bin/true
"${manager[@]}" -n "$RUNTIME_NAMESPACE" label job "$TEST_PREFIX-managed" \
  lenscloud.io/managed-by=platform \
  lenscloud.io/resource-kind=acceptance \
  lenscloud.io/resource-id="$TEST_PREFIX"

cat <<EOF | "${manager[@]}" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TEST_PREFIX}-managed
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: acceptance
    lenscloud.io/resource-id: ${TEST_PREFIX}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Mi
EOF

"${manager[@]}" -n "$RUNTIME_NAMESPACE" create secret generic \
  "$TEST_PREFIX-unowned" --from-literal=probe=redacted

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete secret "$TEST_PREFIX-managed"
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job "$TEST_PREFIX-managed"
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete pvc "$TEST_PREFIX-managed"

if "${platform[@]}" -n "$RUNTIME_NAMESPACE" \
  delete secret "$TEST_PREFIX-unowned" >/dev/null 2>&1; then
  echo "Unlabelled resource deletion unexpectedly succeeded." >&2
  exit 1
fi

if "${platform[@]}" -n default \
  delete mariadb frappe-mariadb >/dev/null 2>&1; then
  echo "Protected MariaDB deletion unexpectedly succeeded." >&2
  exit 1
fi

echo "Managed dependent deletion passed."
echo "Unlabelled runtime and protected baseline deletion remained denied."
