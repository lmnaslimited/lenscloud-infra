#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUNNER_IMAGE:=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:b209598b8252e6eb0f5d65a4783e597cb565ef575e24632374f18b34473f398a}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-bench-runner}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "$TEST_PREFIX-maintenance" \
    "$TEST_PREFIX-negative-image" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "$TEST_PREFIX-request" \
    "$TEST_PREFIX-fixture" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

runtime_labels="$("${manager[@]}" get namespace "$RUNTIME_NAMESPACE" -o jsonpath='{.metadata.labels}')"
if [[ "$runtime_labels" != *"lenscloud.io/runtime-namespace"* || "$runtime_labels" != *"lenscloud.io/managed-runtime"* ]]; then
  echo "Runtime namespace is not labelled as an approved LensCloud runtime namespace." >&2
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
    lenscloud.io/bench-command: maintenance_mode.enable
data:
  request.json: |
    {
      "apiVersion": "lenscloud.io/v1",
      "kind": "BenchCommand",
      "commandId": "${TEST_PREFIX}",
      "command": "maintenance_mode.enable",
      "target": {
        "cluster": "lenscloud-eu-dev",
        "namespace": "${RUNTIME_NAMESPACE}",
        "bench": "runner-smoke-bench",
        "site": "runner-smoke.cloud.lmnaslens.com"
      },
      "args": {},
      "timeoutSeconds": 60,
      "requestedBy": "Infra verifier",
      "reason": "Production runner digest verification"
    }
EOF

cat <<'EOF' | sed "s/__TEST_PREFIX__/${TEST_PREFIX}/g; s/__RUNTIME_NAMESPACE__/${RUNTIME_NAMESPACE}/g" | "${platform[@]}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: __TEST_PREFIX__-fixture
  namespace: __RUNTIME_NAMESPACE__
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: __TEST_PREFIX__
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.enable
data:
  site_config.json: |
    {
      "db_name": "runner_smoke",
      "db_password": "must-not-leak",
      "maintenance_mode": 0,
      "developer_mode": 0
    }
EOF

cat <<EOF | "${platform[@]}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-maintenance
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.enable
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
        - name: fixture
          configMap:
            name: ${TEST_PREFIX}-fixture
        - name: bench
          emptyDir: {}
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: BENCH_PATH
              value: /tmp/frappe-bench
            - name: BENCH_COMMAND_REQUEST
              value: /lenscloud/request/request.json
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: fixture
              mountPath: /tmp/fixture
              readOnly: true
            - name: bench
              mountPath: /tmp/frappe-bench
          command:
            - sh
            - -lc
            - |
              mkdir -p /tmp/frappe-bench/sites/runner-smoke.cloud.lmnaslens.com
              cp /tmp/fixture/site_config.json /tmp/frappe-bench/sites/runner-smoke.cloud.lmnaslens.com/site_config.json
              /usr/local/bin/lenscloud-bench-command-runner
EOF

"${platform[@]}" -n "$RUNTIME_NAMESPACE" wait \
  --for=condition=complete "job/${TEST_PREFIX}-maintenance" --timeout=180s

termination_message="$("${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
  -l "job-name=${TEST_PREFIX}-maintenance" \
  -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}')"

if [[ "$termination_message" != *'"phase":"Succeeded"'* || "$termination_message" != *'"command":"maintenance_mode.enable"'* ]]; then
  echo "Production runner termination summary did not report maintenance_mode success." >&2
  exit 1
fi

if [[ "$termination_message" == *"must-not-leak"* || "$termination_message" == *"db_password"* ]]; then
  echo "Production runner termination summary exposed sensitive fixture content." >&2
  exit 1
fi

if cat <<EOF | "${platform[@]}" apply -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-negative-image
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.enable
spec:
  backoffLimit: 0
  template:
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: busybox:1.36
          command: ["true"]
EOF
then
  echo "Non-runner maintenance_mode image was unexpectedly admitted." >&2
  exit 1
fi

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job "$TEST_PREFIX-maintenance" --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap "$TEST_PREFIX-request" "$TEST_PREFIX-fixture" --wait=false

echo "Bench Command production runner verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Runner image: ${RUNNER_IMAGE}"
echo "Positive command: maintenance_mode.enable"
echo "Sanitized result summary: present"
echo "Negative non-runner image: denied"
echo "Temporary resource prefix: ${TEST_PREFIX}"
