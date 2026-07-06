#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUNNER_IMAGE:=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580}"
: "${REAL_BENCH:=run-20260629-free-prod-bench}"
: "${REAL_SITE:=run-20260629-free-prod-site.cloud.lmnaslens.com}"
: "${REAL_SITES_PVC:=run-20260629-free-prod-bench-sites}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-real-bench-runner}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "$TEST_PREFIX-status" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "$TEST_PREFIX-request" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

if [[ "$REAL_SITE" == *"/"* || "$REAL_SITE" == *".."* ]]; then
  echo "REAL_SITE must be a site name, not a path." >&2
  exit 2
fi

pvc_phase="$("${manager[@]}" -n "$RUNTIME_NAMESPACE" get pvc "$REAL_SITES_PVC" -o jsonpath='{.status.phase}')"
if [[ "$pvc_phase" != "Bound" ]]; then
  echo "Sites PVC is not Bound: ${REAL_SITES_PVC}" >&2
  exit 1
fi

cat <<EOF | "${platform[@]}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${TEST_PREFIX}-request
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.status
data:
  request.json: |
    {
      "apiVersion": "lenscloud.io/v1",
      "kind": "BenchCommand",
      "commandId": "${TEST_PREFIX}",
      "command": "maintenance_mode.status",
      "target": {
        "cluster": "lenscloud-eu-dev",
        "namespace": "${RUNTIME_NAMESPACE}",
        "bench": "${REAL_BENCH}",
        "site": "${REAL_SITE}"
      },
      "args": {},
      "timeoutSeconds": 60,
      "requestedBy": "Infra verifier",
      "reason": "Real Frappe Operator sites PVC path verification"
    }
EOF

cat <<EOF | "${platform[@]}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-status
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.status
    lenscloud.io/bench-command-request: ${TEST_PREFIX}-request
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
            name: ${TEST_PREFIX}-request
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

"${platform[@]}" -n "$RUNTIME_NAMESPACE" wait \
  --for=condition=complete "job/${TEST_PREFIX}-status" --timeout=180s

termination_message="$("${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
  -l "job-name=${TEST_PREFIX}-status" \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}')"

if [[ "$termination_message" != *'"phase":"Succeeded"'* || "$termination_message" != *'"command":"maintenance_mode.status"'* ]]; then
  echo "Real Bench runner termination summary did not report maintenance_mode.status success." >&2
  exit 1
fi

if [[ "$termination_message" != *'"layout":"frappe-sites"'* ]]; then
  echo "Real Bench runner did not report the expected frappe-sites layout." >&2
  exit 1
fi

if [[ "$termination_message" != *'"display":{"kind":"boolean","label":"Maintenance mode"'* ]]; then
  echo "Real Bench runner did not report the expected Maintenance mode display block." >&2
  exit 1
fi

if [[ "$termination_message" == *"db_password"* || "$termination_message" == *"must-not-leak"* ]]; then
  echo "Real Bench runner termination summary exposed sensitive content." >&2
  exit 1
fi

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job "$TEST_PREFIX-status" --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap "$TEST_PREFIX-request" --wait=false

echo "Real Bench runner sites path verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Bench: ${REAL_BENCH}"
echo "Site: ${REAL_SITE}"
echo "Sites PVC: ${REAL_SITES_PVC}"
echo "Positive command: maintenance_mode.status"
echo "Detected layout: frappe-sites"
echo "Display block: Maintenance mode"
echo "Sanitized result summary: present"
echo "Temporary resource prefix: ${TEST_PREFIX}"
