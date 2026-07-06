#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUNNER_IMAGE:?Set RUNNER_IMAGE to the published, admission-pinned CUA runner image digest}"
: "${REAL_BENCH:?Set REAL_BENCH to a Platform-managed Bench name}"
: "${REAL_SITE:?Set REAL_SITE to a Platform-managed Site hostname}"
: "${REAL_SITES_PVC:?Set REAL_SITES_PVC to the target Bench sites PVC}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-cua-site-setup}"
: "${EXPECT_PENDING_BEFORE_COMPLETE:=1}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "${TEST_PREFIX}-status-before" \
    "${TEST_PREFIX}-complete" \
    "${TEST_PREFIX}-status-after" \
    "${TEST_PREFIX}-complete-idempotent" \
    "${TEST_PREFIX}-sensitive-reject" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "${TEST_PREFIX}-status-before-request" \
    "${TEST_PREFIX}-complete-request" \
    "${TEST_PREFIX}-status-after-request" \
    "${TEST_PREFIX}-complete-idempotent-request" \
    "${TEST_PREFIX}-sensitive-reject-request" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

request_configmap() {
  local name="$1" command="$2" args="$3"
  cat <<EOF | "${platform[@]}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: site_setup
    lenscloud.io/bench-command: ${command}
data:
  request.json: |
    {
      "apiVersion": "lenscloud.io/v1",
      "kind": "BenchCommand",
      "commandId": "${name}",
      "command": "${command}",
      "target": {
        "cluster": "lenscloud-eu-dev",
        "namespace": "${RUNTIME_NAMESPACE}",
        "bench": "${REAL_BENCH}",
        "site": "${REAL_SITE}"
      },
      "args": ${args},
      "timeoutSeconds": 300,
      "requestedBy": "Infra verifier",
      "reason": "CUA site setup runner verification"
    }
EOF
}

command_job() {
  local name="$1" request="$2" command="$3" read_only="$4"
  cat <<EOF | "${platform[@]}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${name}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: site_setup
    lenscloud.io/bench-command: ${command}
    lenscloud.io/bench-command-request: ${request}
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
      volumes:
        - name: request
          configMap:
            name: ${request}
        - name: sites
          persistentVolumeClaim:
            claimName: ${REAL_SITES_PVC}
            readOnly: ${read_only}
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: BENCH_PATH
              value: /home/frappe/frappe-bench
            - name: BENCH_SITES_PATH
              value: /lenscloud/sites
            - name: BENCH_COMMAND_REQUEST
              value: /lenscloud/request/request.json
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: sites
              mountPath: /lenscloud/sites
              readOnly: ${read_only}
EOF
}

termination_message() {
  local job="$1"
  "${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
    -l "job-name=${job}" \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}'
}

run_and_wait() {
  local suffix="$1" command="$2" args="$3" read_only="$4"
  local request="${TEST_PREFIX}-${suffix}-request"
  local job="${TEST_PREFIX}-${suffix}"
  request_configmap "$request" "$command" "$args"
  command_job "$job" "$request" "$command" "$read_only"
  local terminal=""
  for _ in $(seq 1 84); do
    local succeeded failed
    succeeded="$("${platform[@]}" -n "$RUNTIME_NAMESPACE" get "job/${job}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$("${platform[@]}" -n "$RUNTIME_NAMESPACE" get "job/${job}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    if [[ "${succeeded:-0}" != "" && "${succeeded:-0}" != "0" ]]; then
      terminal="succeeded"
      break
    fi
    if [[ "${failed:-0}" != "" && "${failed:-0}" != "0" ]]; then
      terminal="failed"
      break
    fi
    sleep 5
  done
  if [[ -z "$terminal" ]]; then
    echo "Job ${job} did not reach a terminal state in time." >&2
    exit 1
  fi
  termination_message "$job"
}

setup_args='{
  "language": "English",
  "email": "first.user@example.com",
  "full_name": "First User",
  "country": "United States",
  "timezone": "America/New_York",
  "currency": "USD"
}'

status_before="$(run_and_wait status-before site_setup.status '{}' true)"
if [[ "$status_before" != *'"phase":"Succeeded"'* || "$status_before" != *'"command":"site_setup.status"'* ]]; then
  echo "site_setup.status before completion did not succeed." >&2
  exit 1
fi
if [[ "$EXPECT_PENDING_BEFORE_COMPLETE" == "1" && "$status_before" != *'"setup_complete":false'* ]]; then
  echo "Expected setup to be pending before completion; set EXPECT_PENDING_BEFORE_COMPLETE=0 for an already completed Site." >&2
  exit 1
fi

complete_message="$(run_and_wait complete site_setup.complete "$setup_args" false)"
if [[ "$complete_message" != *'"phase":"Succeeded"'* || "$complete_message" != *'"command":"site_setup.complete"'* ]]; then
  echo "site_setup.complete did not succeed." >&2
  exit 1
fi
if [[ "$complete_message" != *'"setup_complete":true'* ]]; then
  echo "site_setup.complete did not report setup_complete=true." >&2
  exit 1
fi

status_after="$(run_and_wait status-after site_setup.status '{}' true)"
if [[ "$status_after" != *'"phase":"Succeeded"'* || "$status_after" != *'"setup_complete":true'* ]]; then
  echo "site_setup.status after completion did not report setup_complete=true." >&2
  exit 1
fi

idempotent_message="$(run_and_wait complete-idempotent site_setup.complete "$setup_args" false)"
if [[ "$idempotent_message" != *'"phase":"Succeeded"'* || "$idempotent_message" != *'"idempotent":true'* ]]; then
  echo "site_setup.complete was not idempotent." >&2
  exit 1
fi

sensitive_message="$(run_and_wait sensitive-reject site_setup.complete '{"admin_password":"example-redacted-value"}' false)"
if [[ "$sensitive_message" != *'"phase":"Failed"'* || "$sensitive_message" != *'"code":"INVALID_ARGUMENTS"'* ]]; then
  echo "Sensitive setup arg rejection did not return the expected failure." >&2
  exit 1
fi
if [[ "$sensitive_message" == *"example-redacted-value"* ]]; then
  echo "Sensitive test value leaked in termination message." >&2
  exit 1
fi

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job \
  "${TEST_PREFIX}-status-before" \
  "${TEST_PREFIX}-complete" \
  "${TEST_PREFIX}-status-after" \
  "${TEST_PREFIX}-complete-idempotent" \
  "${TEST_PREFIX}-sensitive-reject" \
  --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
  "${TEST_PREFIX}-status-before-request" \
  "${TEST_PREFIX}-complete-request" \
  "${TEST_PREFIX}-status-after-request" \
  "${TEST_PREFIX}-complete-idempotent-request" \
  "${TEST_PREFIX}-sensitive-reject-request" \
  --wait=false

echo "CUA site setup runner verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Bench: ${REAL_BENCH}"
echo "Site: ${REAL_SITE}"
echo "Sites PVC: ${REAL_SITES_PVC}"
echo "Positive commands: site_setup.status, site_setup.complete"
echo "Negative command: site_setup.complete with sensitive key rejected"
echo "Temporary resource prefix: ${TEST_PREFIX}"
