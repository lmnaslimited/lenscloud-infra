#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-bench-command}"
: "${UNAPPROVED_NAMESPACE:=kube-system}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "$TEST_PREFIX-positive" \
    "$TEST_PREFIX-negative-unlabelled" \
    "$TEST_PREFIX-negative-secret-volume" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "$TEST_PREFIX-request" \
    "$TEST_PREFIX-unowned" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

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

expect_yes create configmaps "$RUNTIME_NAMESPACE"
expect_yes get configmaps "$RUNTIME_NAMESPACE"
expect_yes delete configmaps "$RUNTIME_NAMESPACE"
expect_yes create jobs.batch "$RUNTIME_NAMESPACE"
expect_yes get jobs.batch "$RUNTIME_NAMESPACE"
expect_yes list pods "$RUNTIME_NAMESPACE"

expect_no list secrets "$RUNTIME_NAMESPACE"
expect_no get pods "$RUNTIME_NAMESPACE"
expect_no get secrets default
expect_no create jobs.batch default
expect_no create configmaps default
expect_no create jobs.batch "$UNAPPROVED_NAMESPACE"
expect_no get pods/log "$RUNTIME_NAMESPACE"
expect_no patch namespaces _cluster

"${platform[@]}" -n "$RUNTIME_NAMESPACE" create configmap "$TEST_PREFIX-request" \
  --from-literal=request.json='{"apiVersion":"lenscloud.io/v1","kind":"BenchCommand","command":"bench_test.status","target":{"bench":"verification","site":"verification.localhost"},"args":{"mode":"status"},"timeoutSeconds":60}' \
  --dry-run=client -o yaml |
  "${platform[@]}" label --local -f - \
    lenscloud.io/managed-by=platform \
    lenscloud.io/resource-kind=bench-command \
    lenscloud.io/resource-id="$TEST_PREFIX" \
    -o yaml |
  "${platform[@]}" annotate --local -f - \
    lenscloud.io/bench-command-family=bench_test \
    lenscloud.io/bench-command=bench_test.status \
    -o yaml |
  "${platform[@]}" apply -f -

cat <<EOF | "${platform[@]}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-positive
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: bench_test
    lenscloud.io/bench-command: bench_test.status
    lenscloud.io/bench-command-request: ${TEST_PREFIX-request}
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${TEST_PREFIX}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              printf '%s\n' '{"phase":"Succeeded","command":"bench_test.status","sanitized":true,"summary":"bench command contract verification"}' > /dev/termination-log
EOF

"${platform[@]}" -n "$RUNTIME_NAMESPACE" wait \
  --for=condition=complete "job/${TEST_PREFIX}-positive" --timeout=120s

termination_message="$("${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
  -l "job-name=${TEST_PREFIX}-positive" \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}')"

if [[ "$termination_message" != *'"sanitized":true'* ]]; then
  echo "Sanitized termination summary was not found." >&2
  exit 1
fi

if ! cat <<EOF | "${platform[@]}" apply --dry-run=server -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-runtime-image-positive
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: bench
    lenscloud.io/bench-command: bench.update
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${TEST_PREFIX}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: migration
          image: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
          securityContext:
            privileged: false
          command: ["bash", "-lc"]
          args: ["true"]
EOF
then
  echo "Digest-pinned Release Group runtime image was not admitted for bench.update." >&2
  exit 1
fi

if cat <<EOF | "${platform[@]}" apply --dry-run=server -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-app-aware-runner-negative
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: bench
    lenscloud.io/bench-command: bench.update
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${TEST_PREFIX}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: old-runner
          image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
          securityContext:
            privileged: false
          command: ["true"]
EOF
then
  echo "App-aware bench command using the old runner image unexpectedly passed admission." >&2
  exit 1
fi

if cat <<EOF | "${platform[@]}" apply --dry-run=server -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-mutable-runtime-image-negative
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: bench
    lenscloud.io/bench-command: bench.update
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${TEST_PREFIX}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: mutable-runtime-image
          image: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
          securityContext:
            privileged: false
          command: ["true"]
EOF
then
  echo "Mutable Release Group runtime tag unexpectedly passed admission." >&2
  exit 1
fi

if cat <<EOF | "${platform[@]}" apply -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-negative-unlabelled
  namespace: ${RUNTIME_NAMESPACE}
spec:
  template:
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: negative
          image: busybox:1.36
          command: ["true"]
EOF
then
  echo "Unlabelled bench-command Job creation unexpectedly succeeded." >&2
  exit 1
fi

if cat <<EOF | "${platform[@]}" apply -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-negative-secret-volume
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: bench_test
spec:
  template:
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      volumes:
        - name: forbidden
          secret:
            secretName: should-not-mount
      containers:
        - name: negative
          image: busybox:1.36
          command: ["true"]
EOF
then
  echo "Secret-volume bench-command Job creation unexpectedly succeeded." >&2
  exit 1
fi

"${manager[@]}" -n "$RUNTIME_NAMESPACE" create configmap "$TEST_PREFIX-unowned" \
  --from-literal=probe=redacted >/dev/null

if "${platform[@]}" -n "$RUNTIME_NAMESPACE" \
  delete configmap "$TEST_PREFIX-unowned" >/dev/null 2>&1; then
  echo "Unlabelled ConfigMap deletion unexpectedly succeeded." >&2
  exit 1
fi

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job "$TEST_PREFIX-positive" --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap "$TEST_PREFIX-request" --wait=false

echo "Bench Command Job/API RBAC verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Positive command family: bench_test"
echo "Sanitized result summary: present"
echo "Digest-pinned Release Group runtime image for app-aware bench commands: admitted"
echo "Old runner image for app-aware bench commands: denied"
echo "Mutable Release Group runtime tag for app-aware bench commands: denied"
echo "Negative unlabelled Job: denied"
echo "Negative Secret volume Job: denied"
echo "Secret listing and pod log read: denied"
echo "Unapproved namespace and default namespace creation: denied"
