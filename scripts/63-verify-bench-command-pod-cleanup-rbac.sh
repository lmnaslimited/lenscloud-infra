#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-pod-cleanup}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete pod \
    "$TEST_PREFIX-terminal-platform" \
    "$TEST_PREFIX-terminal-unlabelled" \
    "$TEST_PREFIX-running-platform" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

expect_can_i() {
  local expected="$1" verb="$2" resource="$3" namespace="$4"
  local result
  result="$("${platform[@]}" auth can-i "$verb" "$resource" -n "$namespace" 2>/dev/null || true)"
  if [[ "$result" != "$expected" ]]; then
    echo "Expected '${expected}' for ${verb} ${resource} in ${namespace}, got '${result}'." >&2
    exit 1
  fi
}

expect_can_i yes delete pods "$RUNTIME_NAMESPACE"
expect_can_i no get pods "$RUNTIME_NAMESPACE"
expect_can_i no get pods/log "$RUNTIME_NAMESPACE"
expect_can_i no list secrets "$RUNTIME_NAMESPACE"
expect_can_i no delete pods default

cat <<EOF | "${manager[@]}" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-terminal-platform
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: done
      image: busybox:1.36
      command: ["true"]
---
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-terminal-unlabelled
  namespace: ${RUNTIME_NAMESPACE}
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: done
      image: busybox:1.36
      command: ["true"]
---
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-running-platform
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: wait
      image: busybox:1.36
      command: ["sh", "-c", "sleep 300"]
EOF

"${manager[@]}" -n "$RUNTIME_NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${TEST_PREFIX}-terminal-platform" --timeout=120s
"${manager[@]}" -n "$RUNTIME_NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/${TEST_PREFIX}-terminal-unlabelled" --timeout=120s

for _ in $(seq 1 60); do
  phase="$("${manager[@]}" -n "$RUNTIME_NAMESPACE" get pod "$TEST_PREFIX-running-platform" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Running" ]]; then
    break
  fi
  sleep 2
done
phase="$("${manager[@]}" -n "$RUNTIME_NAMESPACE" get pod "$TEST_PREFIX-running-platform" -o jsonpath='{.status.phase}')"
if [[ "$phase" != "Running" ]]; then
  echo "Running Platform-labelled pod did not reach Running phase." >&2
  exit 1
fi

if ! "${platform[@]}" -n "$RUNTIME_NAMESPACE" delete pod "$TEST_PREFIX-terminal-platform" --wait=true --timeout=120s >/dev/null; then
  echo "Platform could not delete a terminal Platform-labelled Bench Command pod." >&2
  exit 1
fi

if "${platform[@]}" -n "$RUNTIME_NAMESPACE" delete pod "$TEST_PREFIX-terminal-unlabelled" >/dev/null 2>&1; then
  echo "Platform unexpectedly deleted an unlabelled terminal pod." >&2
  exit 1
fi

if "${platform[@]}" -n "$RUNTIME_NAMESPACE" delete pod "$TEST_PREFIX-running-platform" >/dev/null 2>&1; then
  echo "Platform unexpectedly deleted a non-terminal Platform-labelled pod." >&2
  exit 1
fi

if "${platform[@]}" -n default delete pod "$TEST_PREFIX-terminal-platform" >/dev/null 2>&1; then
  echo "Platform unexpectedly had pod delete access in default namespace." >&2
  exit 1
fi

cleanup

echo "Bench Command terminal pod cleanup RBAC/admission verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Positive delete: terminal Platform-labelled Bench Command pod"
echo "Negative delete: unlabelled terminal pod denied"
echo "Negative delete: non-terminal Platform-labelled pod denied"
echo "Negative access: pod logs, get pods, list secrets, and default pod delete denied"
echo "Temporary resource prefix: ${TEST_PREFIX}"
