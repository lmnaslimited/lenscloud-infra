#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUNNER_IMAGE:=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741}"
: "${REAL_BENCH:=run-20260629-free-prod-bench}"
: "${REAL_SITE:=run-20260629-free-prod-site.cloud.lmnaslens.com}"
: "${REAL_SITES_PVC:=run-20260629-free-prod-bench-sites}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-remaining-runner}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "${TEST_PREFIX}-backup-status" \
    "${TEST_PREFIX}-backup-create" \
    "${TEST_PREFIX}-restore-preview" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "${TEST_PREFIX}-backup-status-request" \
    "${TEST_PREFIX}-backup-create-request" \
    "${TEST_PREFIX}-restore-preview-request" \
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
    lenscloud.io/bench-command-family: ${command%%.*}
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
      "timeoutSeconds": 180,
      "requestedBy": "Infra verifier",
      "reason": "Remaining Bench Command family verification"
    }
EOF
}

command_job() {
  local name="$1" request="$2" command="$3"
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
    lenscloud.io/bench-command-family: ${command%%.*}
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
            readOnly: true
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: BENCH_PATH
              value: /home/frappe/frappe-bench
            - name: BENCH_COMMAND_REQUEST
              value: /lenscloud/request/request.json
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: sites
              mountPath: /home/frappe/frappe-bench/sites
              readOnly: true
EOF
}

termination_message() {
  local job="$1"
  "${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
    -l "job-name=${job}" \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}'
}

run_and_wait() {
  local suffix="$1" command="$2" args="$3"
  local request="${TEST_PREFIX}-${suffix}-request"
  local job="${TEST_PREFIX}-${suffix}"
  request_configmap "$request" "$command" "$args"
  command_job "$job" "$request" "$command"
  "${platform[@]}" -n "$RUNTIME_NAMESPACE" wait --for=condition=complete "job/${job}" --timeout=180s
  termination_message "$job"
}

status_message="$(run_and_wait backup-status backup.status '{}')"
if [[ "$status_message" != *'"phase":"Succeeded"'* || "$status_message" != *'"command":"backup.status"'* ]]; then
  echo "backup.status did not succeed." >&2
  exit 1
fi
if [[ "$status_message" != *'"display":{"kind":"backup-status","label":"Backups"'* ]]; then
  echo "backup.status did not return the expected display block." >&2
  exit 1
fi

create_message="$(run_and_wait backup-create backup.create '{}')"
if [[ "$create_message" != *'"phase":"Unsupported"'* || "$create_message" != *'"code":"COMMAND_UNSUPPORTED"'* ]]; then
  echo "backup.create did not return the expected Unsupported result." >&2
  exit 1
fi

preview_message="$(run_and_wait restore-preview restore.preview '{"backupId":"metadata-only"}')"
if [[ "$preview_message" != *'"phase":"Unsupported"'* || "$preview_message" != *'"code":"COMMAND_UNSUPPORTED"'* ]]; then
  echo "restore.preview did not return the expected Unsupported result." >&2
  exit 1
fi

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job \
  "${TEST_PREFIX}-backup-status" \
  "${TEST_PREFIX}-backup-create" \
  "${TEST_PREFIX}-restore-preview" \
  --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
  "${TEST_PREFIX}-backup-status-request" \
  "${TEST_PREFIX}-backup-create-request" \
  "${TEST_PREFIX}-restore-preview-request" \
  --wait=false

echo "Bench Command remaining families verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Bench: ${REAL_BENCH}"
echo "Site: ${REAL_SITE}"
echo "Sites PVC: ${REAL_SITES_PVC}"
echo "Positive command: backup.status"
echo "Unsupported commands: backup.create, restore.preview"
echo "Sanitized result summaries: present"
echo "Temporary resource prefix: ${TEST_PREFIX}"
