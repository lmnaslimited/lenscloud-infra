#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${RUNTIME_NAMESPACE:=lenscloud-runtime-eu}"
: "${TEST_PREFIX:=run-$(date -u +%Y%m%d-%H%M%S)-latency}"
: "${BENCH:=run-20260716-e2e-update-132858-bench}"
: "${SITE:=run-20260716-e2e-update-132858-site.cloud.lmnaslens.com}"
: "${RUNNER_IMAGE:=}"
: "${RELEASE_IMAGE:=}"
: "${KEEP_RESOURCES:=0}"
: "${PREWARM:=1}"
: "${PREWARM_NAME:=lenscloud-command-image-prewarm}"
: "${RUN_PROBES:=1}"
: "${RUN_STANDARD_PROBES:=1}"
: "${RUN_OAUTH_CONFIGURE:=0}"
: "${OAUTH_CONFIGURE_PROVIDER:=lenscloud_latency_probe}"

kubectl_cmd=(kubectl --kubeconfig "$MANAGER_KUBECONFIG")

if [[ -z "$RUNNER_IMAGE" ]]; then
  RUNNER_IMAGE="$("${kubectl_cmd[@]}" -n lenscloud-platform-system get configmap lenscloud-platform-cluster-contract -o go-template='{{index .data "bench_command_runner_image"}}')"
fi

if [[ -z "$RELEASE_IMAGE" ]]; then
  pod_image_id="$("${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get pod -l "app.kubernetes.io/instance=$BENCH,app.kubernetes.io/component=gunicorn" -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' 2>/dev/null || true)"
  if [[ -z "$pod_image_id" ]]; then
    gunicorn_pod="$("${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get pod -o name | awk -v bench="$BENCH" '$0 ~ "^pod/" bench "-gunicorn-" { sub("^pod/", ""); print; exit }')"
    if [[ -n "$gunicorn_pod" ]]; then
      pod_image_id="$("${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get pod "$gunicorn_pod" -o jsonpath='{.status.containerStatuses[0].imageID}')"
    fi
  fi
  RELEASE_IMAGE="${pod_image_id#docker-pullable://}"
fi

if [[ "$RELEASE_IMAGE" != *@sha256:* ]]; then
  echo "Release runtime image must resolve to a digest-pinned image, got: $RELEASE_IMAGE" >&2
  exit 1
fi

cleanup_names=()
cleanup_secret_names=()

cleanup() {
  if [[ "$KEEP_RESOURCES" == "1" ]]; then
    return
  fi
  for name in "${cleanup_names[@]:-}"; do
    "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" delete job "$name" --ignore-not-found >/dev/null 2>&1 || true
    "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" delete configmap "$name-request" --ignore-not-found >/dev/null 2>&1 || true
  done
  for name in "${cleanup_secret_names[@]:-}"; do
    "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" delete secret "$name" --ignore-not-found >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

iso_to_epoch() {
  local value="$1"
  if [[ -z "$value" || "$value" == "<none>" ]]; then
    echo ""
    return
  fi
  date -u -d "$value" +%s.%N 2>/dev/null || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null || true
}

delta_seconds() {
  local start="$1"
  local end="$2"
  if [[ -z "$start" || -z "$end" ]]; then
    echo ""
    return
  fi
  awk -v a="$start" -v b="$end" 'BEGIN { printf "%.3f", b - a }'
}

jsonpath_or_empty() {
  local kind="$1"
  local name="$2"
  local path="$3"
  "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get "$kind" "$name" -o "jsonpath=$path" 2>/dev/null || true
}

wait_terminal_job() {
  local job="$1"
  local timeout_seconds="${2:-360}"
  local deadline=$((SECONDS + timeout_seconds))
  local succeeded failed
  while (( SECONDS < deadline )); do
    succeeded="$(jsonpath_or_empty job "$job" '{.status.succeeded}')"
    failed="$(jsonpath_or_empty job "$job" '{.status.failed}')"
    if [[ "${succeeded:-0}" != "" && "${succeeded:-0}" != "0" ]]; then
      return 0
    fi
    if [[ "${failed:-0}" != "" && "${failed:-0}" != "0" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for terminal Job state: $job" >&2
  return 1
}

print_timing() {
  local label="$1"
  local job="$2"
  local observe_start_epoch="$3"
  local observe_end_epoch="$4"
  local create_start_epoch="$5"
  local create_end_epoch="$6"
  local pod
  pod="$("${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get pod -l "job-name=$job" -o jsonpath='{.items[0].metadata.name}')"

  local job_created pod_created pod_scheduled container_started container_finished job_started job_completed message
  job_created="$(jsonpath_or_empty job "$job" '{.metadata.creationTimestamp}')"
  job_started="$(jsonpath_or_empty job "$job" '{.status.startTime}')"
  job_completed="$(jsonpath_or_empty job "$job" '{.status.completionTime}')"
  pod_created="$(jsonpath_or_empty pod "$pod" '{.metadata.creationTimestamp}')"
  pod_scheduled="$(jsonpath_or_empty pod "$pod" '{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}')"
  container_started="$(jsonpath_or_empty pod "$pod" '{.status.containerStatuses[0].state.terminated.startedAt}')"
  container_finished="$(jsonpath_or_empty pod "$pod" '{.status.containerStatuses[0].state.terminated.finishedAt}')"
  message="$(jsonpath_or_empty pod "$pod" '{.status.containerStatuses[0].state.terminated.message}')"

  local job_created_epoch pod_created_epoch pod_scheduled_epoch container_started_epoch container_finished_epoch job_completed_epoch
  job_created_epoch="$(iso_to_epoch "$job_created")"
  pod_created_epoch="$(iso_to_epoch "$pod_created")"
  pod_scheduled_epoch="$(iso_to_epoch "$pod_scheduled")"
  container_started_epoch="$(iso_to_epoch "$container_started")"
  container_finished_epoch="$(iso_to_epoch "$container_finished")"
  job_completed_epoch="$(iso_to_epoch "$job_completed")"

  echo "## $label"
  echo "job=$job"
  echo "pod=$pod"
  echo "job_create_api_seconds=$(delta_seconds "$create_start_epoch" "$create_end_epoch")"
  echo "job_created_at=$job_created"
  echo "pod_created_at=$pod_created"
  echo "pod_scheduled_at=$pod_scheduled"
  echo "container_started_at=$container_started"
  echo "container_finished_at=$container_finished"
  echo "job_completed_at=$job_completed"
  echo "job_to_pod_create_seconds=$(delta_seconds "$job_created_epoch" "$pod_created_epoch")"
  echo "pod_create_to_scheduled_seconds=$(delta_seconds "$pod_created_epoch" "$pod_scheduled_epoch")"
  echo "scheduled_to_container_start_seconds=$(delta_seconds "$pod_scheduled_epoch" "$container_started_epoch")"
  echo "container_runtime_seconds=$(delta_seconds "$container_started_epoch" "$container_finished_epoch")"
  echo "container_finish_to_job_complete_seconds=$(delta_seconds "$container_finished_epoch" "$job_completed_epoch")"
  echo "job_terminal_to_watch_observed_seconds=$(delta_seconds "$job_completed_epoch" "$observe_end_epoch")"
  echo "watch_wait_seconds=$(delta_seconds "$observe_start_epoch" "$observe_end_epoch")"
  echo "termination_summary=${message}"
  echo "image_events:"
  "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get events --field-selector "involvedObject.name=$pod" --sort-by=.lastTimestamp | sed -n '/Pulled\|Pulling\|Created\|Started\|Scheduled/p'
  echo
}

prewarm_images() {
  local name="$PREWARM_NAME"
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${name}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: infra
    lenscloud.io/resource-kind: image-prewarm
spec:
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
        lenscloud.io/managed-by: infra
        lenscloud.io/resource-kind: image-prewarm
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 1
      containers:
        - name: release-runtime
          image: ${RELEASE_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["bash", "-lc", "tail -f /dev/null"]
        - name: generic-runner
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "tail -f /dev/null"]
YAML
  "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" rollout status "daemonset/${name}" --timeout=300s
  echo "prewarm_daemonset=${name}"
  "${kubectl_cmd[@]}" -n "$RUNTIME_NAMESPACE" get pod -l "app=${name}" -o wide
}

run_generic() {
  local label="$1"
  local command="$2"
  local args_json="$3"
  local job="${TEST_PREFIX}-${label}"
  cleanup_names+=("$job")
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${job}-request
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
data:
  request.json: |
    {"apiVersion":"lenscloud.io/v1","kind":"BenchCommand","commandId":"${job}","command":"${command}","target":{"namespace":"${RUNTIME_NAMESPACE}","bench":"${BENCH}","site":"${SITE}"},"args":${args_json},"timeoutSeconds":300,"requestedBy":"infra-latency-probe","reason":"Infra latency proof"}
YAML
  local create_start create_end observe_start observe_end
  create_start="$(date -u +%s.%N)"
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${job}
  annotations:
    lenscloud.io/bench-command-family: ${command%%.*}
    lenscloud.io/bench-command: ${command}
    lenscloud.io/bench-command-request: ${job}-request
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${job}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: BENCH_PATH
              value: /home/frappe/frappe-bench
            - name: BENCH_COMMAND_REQUEST
              value: /lenscloud/request/request.json
          command: ["/usr/local/bin/lenscloud-bench-command-runner"]
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: sites
              mountPath: /home/frappe/frappe-bench/sites
              subPath: frappe-sites
              readOnly: true
      volumes:
        - name: request
          configMap:
            name: ${job}-request
        - name: sites
          persistentVolumeClaim:
            claimName: ${BENCH}-sites
YAML
  create_end="$(date -u +%s.%N)"
  observe_start="$(date -u +%s.%N)"
  wait_terminal_job "$job" 360
  observe_end="$(date -u +%s.%N)"
  print_timing "$label $command" "$job" "$observe_start" "$observe_end" "$create_start" "$create_end"
}

run_app_aware() {
  local label="$1"
  local command_name="$2"
  local body="$3"
  local job="${TEST_PREFIX}-${label}"
  cleanup_names+=("$job")
  local family="${command_name%%.*}"
  local create_start create_end observe_start observe_end
  create_start="$(date -u +%s.%N)"
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${job}
  annotations:
    lenscloud.io/bench-command-family: ${family}
    lenscloud.io/bench-command: ${command_name}
spec:
  backoffLimit: 1
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${job}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: ${RELEASE_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["bash", "-lc"]
          args:
            - |
${body}
          volumeMounts:
            - name: sites
              mountPath: /home/frappe/frappe-bench/sites
              subPath: frappe-sites
              readOnly: false
            - name: sites-assets
              mountPath: /home/frappe/frappe-bench/sites/assets
              subPath: frappe-sites/assets
              readOnly: false
      volumes:
        - name: sites
          persistentVolumeClaim:
            claimName: ${BENCH}-sites
        - name: sites-assets
          persistentVolumeClaim:
            claimName: ${BENCH}-sites
YAML
  create_end="$(date -u +%s.%N)"
  observe_start="$(date -u +%s.%N)"
  wait_terminal_job "$job" 360
  observe_end="$(date -u +%s.%N)"
  print_timing "$label $command_name" "$job" "$observe_start" "$observe_end" "$create_start" "$create_end"
}

run_oauth_configure() {
  local label="oauth-configure"
  local command="oauth.configure"
  local job="${TEST_PREFIX}-${label}"
  local secret="${job}-secret"
  cleanup_names+=("$job")
  cleanup_secret_names+=("$secret")
  local args_json
  args_json="$(printf '{"provider":"%s","provider_name":"LensCloud Latency Probe","social_login_provider":"Custom","enable_social_login":true,"client_id":"latency-probe-client","client_secret_source":"mounted_file","base_url":"https://auth.cloud.lmnaslens.com","authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://%s/api/method/frappe.integrations.oauth2_logins.custom/%s","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":"Deny"}' "$OAUTH_CONFIGURE_PROVIDER" "$SITE" "$OAUTH_CONFIGURE_PROVIDER")"
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${job}-request
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
data:
  request.json: |
    {"apiVersion":"lenscloud.io/v1","kind":"BenchCommand","commandId":"${job}","command":"${command}","target":{"namespace":"${RUNTIME_NAMESPACE}","bench":"${BENCH}","site":"${SITE}"},"args":${args_json},"timeoutSeconds":300,"requestedBy":"infra-latency-probe","reason":"Infra OAuth configure latency proof"}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${secret}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
type: Opaque
stringData:
  client_secret: latency-probe-secret
YAML
  local create_start create_end observe_start observe_end
  create_start="$(date -u +%s.%N)"
  cat <<YAML | "${kubectl_cmd[@]}" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
  namespace: ${RUNTIME_NAMESPACE}
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: ${job}
  annotations:
    lenscloud.io/bench-command-family: oauth
    lenscloud.io/bench-command: oauth.configure
    lenscloud.io/bench-command-request: ${job}-request
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        lenscloud.io/managed-by: platform
        lenscloud.io/resource-kind: bench-command
        lenscloud.io/resource-id: ${job}
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: ${RUNNER_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: BENCH_PATH
              value: /home/frappe/frappe-bench
            - name: BENCH_COMMAND_REQUEST
              value: /lenscloud/request/request.json
            - name: LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH
              value: /lenscloud/secrets/client_secret
          command: ["/usr/local/bin/lenscloud-bench-command-runner"]
          volumeMounts:
            - name: request
              mountPath: /lenscloud/request
              readOnly: true
            - name: sites
              mountPath: /home/frappe/frappe-bench/sites
              subPath: frappe-sites
              readOnly: false
            - name: oauth-client-secret
              mountPath: /lenscloud/secrets
              readOnly: true
      volumes:
        - name: request
          configMap:
            name: ${job}-request
        - name: sites
          persistentVolumeClaim:
            claimName: ${BENCH}-sites
        - name: oauth-client-secret
          secret:
            secretName: ${secret}
            items:
              - key: client_secret
                path: client_secret
YAML
  create_end="$(date -u +%s.%N)"
  observe_start="$(date -u +%s.%N)"
  wait_terminal_job "$job" 360
  observe_end="$(date -u +%s.%N)"
  print_timing "$label $command" "$job" "$observe_start" "$observe_end" "$create_start" "$create_end"
}

bootstrap_body="$(cat <<SCRIPT
              set -euo pipefail
              start=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
              if bench --site ${SITE} list-apps | awk '{print \$1}' | grep -Fxq erpnext; then
                state=already_installed
              else
                bench --site ${SITE} install-app erpnext
                state=installed
              fi
              finish=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
              printf '%s\n' "{\"phase\":\"Succeeded\",\"command\":\"site_bootstrap.install_apps\",\"summary\":\"Bootstrap app install probe completed\",\"state\":\"\${state}\",\"command_started_at\":\"\${start}\",\"command_finished_at\":\"\${finish}\",\"redacted\":true}" > /dev/termination-log
SCRIPT
)"

setup_body="$(cat <<SCRIPT
              set -euo pipefail
              start=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
              bench --site ${SITE} execute frappe.is_setup_complete >/tmp/setup-complete-probe.out 2>&1
              finish=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
              printf '%s\n' "{\"phase\":\"Succeeded\",\"command\":\"site_setup.complete\",\"summary\":\"Setup complete idempotency probe completed\",\"setup_complete\":true,\"idempotent\":true,\"command_started_at\":\"\${start}\",\"command_finished_at\":\"\${finish}\",\"redacted\":true}" > /dev/termination-log
SCRIPT
)"

echo "test_prefix=${TEST_PREFIX}"
echo "namespace=${RUNTIME_NAMESPACE}"
echo "bench=${BENCH}"
echo "site=${SITE}"
echo "runner_image=${RUNNER_IMAGE}"
echo "release_image=${RELEASE_IMAGE}"

if [[ "$PREWARM" == "1" ]]; then
  prewarm_images
fi

if [[ "$RUN_PROBES" != "1" ]]; then
  echo "image prewarm completed; probes skipped"
  exit 0
fi

if [[ "$RUN_STANDARD_PROBES" == "1" ]]; then
  run_app_aware "bootstrap" "site_bootstrap.install_apps" "$bootstrap_body"
  run_app_aware "setup-complete" "site_setup.complete" "$setup_body"
  run_generic "setup-status" "site_setup.status" "{}"
  run_generic "oauth-status" "oauth.status" "{\"provider\":\"lenscloud\"}"
fi

if [[ "$RUN_OAUTH_CONFIGURE" == "1" ]]; then
  run_oauth_configure
fi

echo "customer provisioning latency probe passed"
