#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

bench_path="$tmpdir/frappe-bench"
site="runner-test.localhost"
mkdir -p "$bench_path/sites/$site" "$tmpdir/request"
cat >"$bench_path/sites/$site/site_config.json" <<'JSON'
{
 "db_name": "runner_test",
 "db_password": "must-not-leak",
 "developer_mode": 0,
 "maintenance_mode": 0
}
JSON

run_command() {
  local name="$1"
  local request="$2"
  local status="${3:-0}"
  local request_path="$tmpdir/request/${name}.json"
  local termination_path="$tmpdir/request/${name}.termination.json"
  printf '%s\n' "$request" >"$request_path"
  set +e
  BENCH_PATH="$bench_path" \
  BENCH_COMMAND_REQUEST="$request_path" \
  BENCH_COMMAND_TERMINATION_LOG="$termination_path" \
    python3 bench-command-runner/runner.py >/dev/null
  local actual=$?
  set -e
  if [[ "$actual" != "$status" ]]; then
    echo "Unexpected exit for ${name}: expected ${status}, got ${actual}" >&2
    cat "$termination_path" >&2 || true
    exit 1
  fi
  if grep -E 'must-not-leak|password|token|private|secret' "$termination_path" >/dev/null; then
    echo "Sensitive content detected in ${name} termination summary." >&2
    cat "$termination_path" >&2
    exit 1
  fi
  cat "$termination_path"
}

base_target='"target":{"namespace":"lenscloud-runtime-eu","bench":"runner-test-bench","site":"runner-test.localhost"}'

run_command maintenance_enable \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-1\",\"command\":\"maintenance_mode.enable\",${base_target},\"args\":{},\"timeoutSeconds\":60}"

grep '"maintenance_mode": 1' "$bench_path/sites/$site/site_config.json" >/dev/null

run_command maintenance_status \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-2\",\"command\":\"maintenance_mode.status\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"display":{"kind":"boolean","label":"Maintenance mode","rawValue":1,"safe":true,"value":"On"}' >/dev/null

run_command developer_enable \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-3\",\"command\":\"developer_mode.enable\",${base_target},\"args\":{},\"timeoutSeconds\":60}"

grep '"developer_mode": 1' "$bench_path/sites/$site/site_config.json" >/dev/null

run_command developer_status \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-3b\",\"command\":\"developer_mode.status\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"display":{"kind":"boolean","label":"Developer mode","rawValue":1,"safe":true,"value":"On"}' >/dev/null

run_command site_config_set \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-4\",\"command\":\"site_config.set\",${base_target},\"args\":{\"key\":\"server_script_enabled\",\"value\":1},\"timeoutSeconds\":60}"

grep '"server_script_enabled": 1' "$bench_path/sites/$site/site_config.json" >/dev/null

run_command site_config_get \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-4b\",\"command\":\"site_config.get\",${base_target},\"args\":{\"key\":\"server_script_enabled\"},\"timeoutSeconds\":60}" |
  grep -F '"display":{"kind":"boolean","label":"Server script","rawValue":1,"safe":true,"value":"On"}' >/dev/null

run_command cors_update \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-5\",\"command\":\"cors.allowlist.update\",${base_target},\"args\":{\"origins\":[\"https://app.example.com\",\"https://admin.example.com\"]},\"timeoutSeconds\":60}"

grep 'https://admin.example.com' "$bench_path/sites/$site/site_config.json" >/dev/null

run_command cors_get \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-5b\",\"command\":\"cors.allowlist.get\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"display":{"kind":"origin-list","label":"CORS allowlist","rawValue":["https://admin.example.com","https://app.example.com"],"safe":true,"value":["https://admin.example.com","https://app.example.com"]}' >/dev/null

run_command unsupported_backup \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-6\",\"command\":\"backup.create\",${base_target},\"args\":{},\"timeoutSeconds\":60}" \
  0 | grep '"phase":"Unsupported"' >/dev/null

run_command invalid_sensitive_key \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-7\",\"command\":\"site_config.get\",${base_target},\"args\":{\"key\":\"db_password\"},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

nested_site="runner-nested.localhost"
mkdir -p "$bench_path/sites/frappe-sites/$nested_site"
cat >"$bench_path/sites/frappe-sites/$nested_site/site_config.json" <<'JSON'
{
 "db_name": "runner_nested",
 "db_password": "must-not-leak",
 "maintenance_mode": 0
}
JSON

nested_target='"target":{"namespace":"lenscloud-runtime-eu","bench":"runner-test-bench","site":"runner-nested.localhost"}'

run_command nested_maintenance_status \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-8\",\"command\":\"maintenance_mode.status\",${nested_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"layout":"frappe-sites"' >/dev/null

echo "Bench command runner local verification passed."
