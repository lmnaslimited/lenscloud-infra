#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${PLATFORM_KUBECONFIG:=.artifacts/lenscloud-eu.kubeconfig}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUNNER_IMAGE:?Set RUNNER_IMAGE to the published, admission-pinned CUA OAuth runner image digest}"
: "${REAL_BENCH:?Set REAL_BENCH to a Platform-managed Bench name}"
: "${REAL_SITE:?Set REAL_SITE to a Platform-managed Site hostname}"
: "${REAL_SITES_PVC:?Set REAL_SITES_PVC to the target Bench sites PVC}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M)-cua-oauth}"
: "${OAUTH_PROVIDER:=lenscloud_oauth_smoke}"
: "${OAUTH_PROVIDER_NAME:=LensCloud OAuth Smoke}"
: "${OAUTH_CLIENT_ID:=lenscloud-oauth-smoke-client}"
: "${OAUTH_BASE_URL:=https://nectar.lmnas.com}"
: "${OAUTH_REDIRECT_URL:=https://${REAL_SITE}/api/method/frappe.integrations.oauth2_logins.custom/${OAUTH_PROVIDER}}"

manager=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")
platform=(kubectl --kubeconfig "$PLATFORM_KUBECONFIG")

cleanup() {
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete job \
    "${TEST_PREFIX}-status-before" \
    "${TEST_PREFIX}-configure" \
    "${TEST_PREFIX}-status-after" \
    "${TEST_PREFIX}-secret-arg-reject" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
    "${TEST_PREFIX}-status-before-request" \
    "${TEST_PREFIX}-configure-request" \
    "${TEST_PREFIX}-status-after-request" \
    "${TEST_PREFIX}-secret-arg-reject-request" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  "${manager[@]}" -n "$RUNTIME_NAMESPACE" delete secret \
    "${TEST_PREFIX}-oauth-client-secret" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

wait_for_cleanup() {
  local resource
  for resource in \
    "job/${TEST_PREFIX}-status-before" \
    "job/${TEST_PREFIX}-configure" \
    "job/${TEST_PREFIX}-status-after" \
    "job/${TEST_PREFIX}-secret-arg-reject" \
    "configmap/${TEST_PREFIX}-status-before-request" \
    "configmap/${TEST_PREFIX}-configure-request" \
    "configmap/${TEST_PREFIX}-status-after-request" \
    "configmap/${TEST_PREFIX}-secret-arg-reject-request" \
    "secret/${TEST_PREFIX}-oauth-client-secret"; do
    for _ in $(seq 1 60); do
      if ! "${manager[@]}" -n "$RUNTIME_NAMESPACE" get "$resource" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    if "${manager[@]}" -n "$RUNTIME_NAMESPACE" get "$resource" >/dev/null 2>&1; then
      echo "Timed out waiting for old ${resource} to be deleted." >&2
      exit 1
    fi
  done
}

trap cleanup EXIT
cleanup
wait_for_cleanup

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
    lenscloud.io/bench-command-family: oauth
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
      "reason": "CUA OAuth Social Login Key runner verification"
    }
EOF
}

oauth_secret() {
  cat <<EOF | "${platform[@]}" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${TEST_PREFIX}-oauth-client-secret
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
type: Opaque
stringData:
  client_secret: placeholder-verifier-secret-do-not-use
EOF
}

command_job() {
  local name="$1" request="$2" command="$3" include_secret="${4:-false}"
  local secret_volume="" secret_mount=""
  if [[ "$include_secret" == "true" ]]; then
    secret_volume="
        - name: oauth-client-secret
          secret:
            secretName: ${TEST_PREFIX}-oauth-client-secret
            items:
              - key: client_secret
                path: client_secret"
    secret_mount="
            - name: oauth-client-secret
              mountPath: /lenscloud/secrets
              readOnly: true"
  fi
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
    lenscloud.io/bench-command-family: oauth
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
            readOnly: true${secret_volume}
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
            - name: LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH
              value: /lenscloud/secrets/client_secret
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: sites
              mountPath: /lenscloud/sites
              readOnly: true${secret_mount}
EOF
}

termination_message() {
  local job="$1"
  "${platform[@]}" -n "$RUNTIME_NAMESPACE" get pods \
    -l "job-name=${job}" \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}'
}

run_and_wait() {
  local suffix="$1" command="$2" args="$3" include_secret="${4:-false}"
  local request="${TEST_PREFIX}-${suffix}-request"
  local job="${TEST_PREFIX}-${suffix}"
  request_configmap "$request" "$command" "$args"
  command_job "$job" "$request" "$command" "$include_secret"
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

expect_apply_denied() {
  local name="$1"
  set +e
  local output
  output="$("$@" 2>&1)"
  local status=$?
  set -e
  if [[ "$status" == "0" ]]; then
    echo "Expected apply to be denied for ${name}, but it succeeded." >&2
    exit 1
  fi
  if [[ "$output" == *"placeholder-verifier-secret-do-not-use"* ]]; then
    echo "Sensitive verifier value leaked in denial output for ${name}." >&2
    exit 1
  fi
}

oauth_secret >/dev/null

status_args="{\"provider\":\"${OAUTH_PROVIDER}\"}"
status_before="$(run_and_wait status-before oauth.status "$status_args" false)"
if [[ "$status_before" != *'"phase":"Succeeded"'* || "$status_before" != *'"command":"oauth.status"'* ]]; then
  echo "oauth.status before configure did not succeed." >&2
  exit 1
fi

configure_args="{\"provider\":\"${OAUTH_PROVIDER}\",\"provider_name\":\"${OAUTH_PROVIDER_NAME}\",\"social_login_provider\":\"Custom\",\"enable_social_login\":true,\"client_id\":\"${OAUTH_CLIENT_ID}\",\"client_secret_source\":\"mounted_file\",\"base_url\":\"${OAUTH_BASE_URL}\",\"authorize_url\":\"/api/method/frappe.integrations.oauth2.authorize\",\"access_token_url\":\"/api/method/frappe.integrations.oauth2.get_token\",\"redirect_url\":\"${OAUTH_REDIRECT_URL}\",\"api_endpoint\":\"/api/method/frappe.integrations.oauth2.openid_profile\",\"custom_base_url\":true,\"auth_url_data\":{\"response_type\":\"code\",\"scope\":\"openid\"},\"sign_ups\":\"\"}"

configure_message="$(run_and_wait configure oauth.configure "$configure_args" true)"
if [[ "$configure_message" != *'"phase":"Succeeded"'* || "$configure_message" != *'"command":"oauth.configure"'* ]]; then
  echo "oauth.configure did not succeed." >&2
  exit 1
fi
if [[ "$configure_message" != *'"secret_configured":true'* ]]; then
  echo "oauth.configure did not report secret_configured=true." >&2
  exit 1
fi
if [[ "$configure_message" == *"placeholder-verifier-secret-do-not-use"* || "$configure_message" == *"client_secret"* ]]; then
  echo "OAuth secret leaked in configure termination message." >&2
  exit 1
fi

status_after="$(run_and_wait status-after oauth.status "$status_args" false)"
if [[ "$status_after" != *'"phase":"Succeeded"'* || "$status_after" != *'"summary":"Social login is enabled"'* ]]; then
  echo "oauth.status after configure did not report enabled social login." >&2
  exit 1
fi

sensitive_message="$(run_and_wait secret-arg-reject oauth.configure '{"provider":"lenscloud_oauth_smoke","provider_name":"LensCloud OAuth Smoke","client_secret":"placeholder-verifier-secret-do-not-use"}' false)"
if [[ "$sensitive_message" != *'"phase":"Failed"'* || "$sensitive_message" != *'"code":"INVALID_ARGUMENTS"'* ]]; then
  echo "oauth.configure with client_secret arg did not fail safely." >&2
  exit 1
fi
if [[ "$sensitive_message" == *"placeholder-verifier-secret-do-not-use"* ]]; then
  echo "Sensitive test value leaked in rejection message." >&2
  exit 1
fi

expect_apply_denied non_oauth_secret_volume "${platform[@]}" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${TEST_PREFIX}-unsafe-secret-volume
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${TEST_PREFIX}
  annotations:
    lenscloud.io/bench-command-family: maintenance_mode
    lenscloud.io/bench-command: maintenance_mode.status
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
        - name: oauth-client-secret
          secret:
            secretName: ${TEST_PREFIX}-oauth-client-secret
            items:
              - key: client_secret
                path: client_secret
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          volumeMounts:
            - name: oauth-client-secret
              mountPath: /lenscloud/secrets
              readOnly: true
EOF

"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete job \
  "${TEST_PREFIX}-status-before" \
  "${TEST_PREFIX}-configure" \
  "${TEST_PREFIX}-status-after" \
  "${TEST_PREFIX}-secret-arg-reject" \
  --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete configmap \
  "${TEST_PREFIX}-status-before-request" \
  "${TEST_PREFIX}-configure-request" \
  "${TEST_PREFIX}-status-after-request" \
  "${TEST_PREFIX}-secret-arg-reject-request" \
  --wait=false
"${platform[@]}" -n "$RUNTIME_NAMESPACE" delete secret \
  "${TEST_PREFIX}-oauth-client-secret" \
  --wait=false

echo "CUA OAuth runner verification passed."
echo "Runtime namespace: ${RUNTIME_NAMESPACE}"
echo "Bench: ${REAL_BENCH}"
echo "Site: ${REAL_SITE}"
echo "Sites PVC: ${REAL_SITES_PVC}"
echo "Positive commands: oauth.status, oauth.configure"
echo "Negative checks: direct client_secret arg rejected; non-oauth Secret volume denied"
echo "Temporary resource prefix: ${TEST_PREFIX}"
