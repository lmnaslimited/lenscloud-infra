#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

bench_path="$tmpdir/frappe-bench"
site="runner-test.localhost"
mkdir -p "$bench_path/sites/$site" "$tmpdir/request" "$tmpdir/oauth-secret"
printf 'must-not-leak-oauth-secret\n' >"$tmpdir/oauth-secret/client_secret"
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
  LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH="$tmpdir/oauth-secret/client_secret" \
  LENS_COMMAND_FAKE_FRAPPE_SETUP=1 \
    python3 bench-command-runner/runner.py >/dev/null
  local actual=$?
  set -e
  if [[ "$actual" != "$status" ]]; then
    echo "Unexpected exit for ${name}: expected ${status}, got ${actual}" >&2
    cat "$termination_path" >&2 || true
    exit 1
  fi
  if grep -E 'must-not-leak|db_password|admin_password|client_secret|token=|private_key|BEGIN ' "$termination_path" >/dev/null; then
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

mkdir -p "$bench_path/sites/$site/private/backups"
printf 'fake backup metadata only\n' >"$bench_path/sites/$site/private/backups/20260630_010203-runner-test-database.sql.gz"

run_command backup_status \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-6\",\"command\":\"backup.status\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"display":{"kind":"backup-status","label":"Backups"' >/dev/null

run_command unsupported_backup_create \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-6b\",\"command\":\"backup.create\",${base_target},\"args\":{},\"timeoutSeconds\":60}" \
  0 | grep -F '"phase":"Unsupported"' >/dev/null

run_command unsupported_restore_preview \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-6c\",\"command\":\"restore.preview\",${base_target},\"args\":{\"backupId\":\"20260630_010203-runner-test-database.sql.gz\"},\"timeoutSeconds\":60}" \
  0 | grep -F '"phase":"Unsupported"' >/dev/null

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

run_command setup_status_pending \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-9\",\"command\":\"site_setup.status\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"summary":"Setup wizard is pending"' >/dev/null

run_command setup_complete \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-10\",\"command\":\"site_setup.complete\",${base_target},\"args\":{\"language\":\"English\",\"email\":\"first.user@example.com\",\"full_name\":\"First User\",\"country\":\"United States\",\"timezone\":\"America/New_York\",\"currency\":\"USD\"},\"timeoutSeconds\":60}" |
  grep -F '"summary":"Setup wizard completed"' >/dev/null

run_command setup_status_complete \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-11\",\"command\":\"site_setup.status\",${base_target},\"args\":{},\"timeoutSeconds\":60}" |
  grep -F '"summary":"Setup wizard is complete"' >/dev/null

run_command setup_complete_idempotent \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-12\",\"command\":\"site_setup.complete\",${base_target},\"args\":{\"language\":\"English\",\"email\":\"first.user@example.com\",\"full_name\":\"First User\",\"country\":\"United States\",\"timezone\":\"America/New_York\",\"currency\":\"USD\"},\"timeoutSeconds\":60}" |
  grep -F '"idempotent":true' >/dev/null

run_command setup_sensitive_reject \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-13\",\"command\":\"site_setup.complete\",${base_target},\"args\":{\"language\":\"English\",\"admin_password\":\"must-not-leak\"},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

run_command app_aware_bootstrap_unsupported \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-13a\",\"command\":\"site_bootstrap.install_apps\",${base_target},\"args\":{\"install_apps\":[{\"app\":\"erpnext\",\"install_sequence\":20}]},\"timeoutSeconds\":60}" \
  0 | grep '"code":"COMMAND_UNSUPPORTED"' >/dev/null

run_command app_aware_site_app_unsupported \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-13b\",\"command\":\"site_app.install\",${base_target},\"args\":{\"apps\":[{\"app\":\"payments\",\"install_sequence\":30}]},\"timeoutSeconds\":60}" \
  0 | grep '"code":"COMMAND_UNSUPPORTED"' >/dev/null

bench_target='"target":{"namespace":"lenscloud-runtime-eu","bench":"runner-test-bench"}'

run_command app_aware_bench_update_unsupported \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-13c\",\"command\":\"bench.update\",${bench_target},\"args\":{\"target_release\":\"v16.14.2\"},\"timeoutSeconds\":60}" \
  0 | grep '"code":"COMMAND_UNSUPPORTED"' >/dev/null

run_command oauth_status_missing \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-14\",\"command\":\"oauth.status\",${base_target},\"args\":{\"provider\":\"platform_oauth_https\"},\"timeoutSeconds\":60}" |
  grep -F '"summary":"Social login is not configured"' >/dev/null

oauth_args='{"provider":"platform_oauth_https","provider_name":"Platform OAuth Https","social_login_provider":"Custom","enable_social_login":true,"client_id":"local-client-id","client_secret_source":"mounted_file","base_url":"https://platform-oauth.example.com","authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://runner-test.localhost/api/method/frappe.integrations.oauth2_logins.custom/platform_oauth_https","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":""}'

run_command oauth_configure \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-15\",\"command\":\"oauth.configure\",${base_target},\"args\":${oauth_args},\"timeoutSeconds\":60}" |
  grep -F '"summary":"Social login configured"' >/dev/null

run_command oauth_status_enabled \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-16\",\"command\":\"oauth.status\",${base_target},\"args\":{\"provider_name\":\"Platform OAuth Https\"},\"timeoutSeconds\":60}" |
  grep -F '"value":"Enabled"' |
  grep -F '"secret_configured":true' >/dev/null

run_command oauth_secret_arg_reject \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-17\",\"command\":\"oauth.configure\",${base_target},\"args\":{\"provider\":\"platform_oauth_https\",\"provider_name\":\"Platform OAuth Https\",\"client_secret\":\"must-not-leak-oauth-secret\"},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

oauth_local_args='{"provider":"platform_oauth","provider_name":"Platform OAuth","social_login_provider":"Custom","enable_social_login":true,"client_id":"local-dev-client-id","client_secret_source":"mounted_file","base_url":"http://dev.localhost:8000","allow_local_oauth_http":true,"authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://runner-test.localhost/api/method/frappe.integrations.oauth2_logins.custom/platform_oauth","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":""}'

run_command oauth_local_http_configure \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-18\",\"command\":\"oauth.configure\",${base_target},\"args\":${oauth_local_args},\"timeoutSeconds\":60}" |
  grep -F '"base_url":"http://dev.localhost:8000"' |
  grep -F '"provider":"platform_oauth"' >/dev/null

oauth_local_missing_flag='{"provider":"platform_oauth","provider_name":"Platform OAuth","social_login_provider":"Custom","enable_social_login":true,"client_id":"local-dev-client-id","client_secret_source":"mounted_file","base_url":"http://dev.localhost:8000","authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://runner-test.localhost/api/method/frappe.integrations.oauth2_logins.custom/platform_oauth","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":""}'

run_command oauth_local_http_missing_flag_reject \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-19\",\"command\":\"oauth.configure\",${base_target},\"args\":${oauth_local_missing_flag},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

oauth_local_false_flag='{"provider":"platform_oauth","provider_name":"Platform OAuth","social_login_provider":"Custom","enable_social_login":true,"client_id":"local-dev-client-id","client_secret_source":"mounted_file","base_url":"http://dev.localhost:8000","allow_local_oauth_http":false,"authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://runner-test.localhost/api/method/frappe.integrations.oauth2_logins.custom/platform_oauth","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":""}'

run_command oauth_local_http_false_flag_reject \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-20\",\"command\":\"oauth.configure\",${base_target},\"args\":${oauth_local_false_flag},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

oauth_nonlocal_http='{"provider":"platform_oauth","provider_name":"Platform OAuth","social_login_provider":"Custom","enable_social_login":true,"client_id":"local-dev-client-id","client_secret_source":"mounted_file","base_url":"http://platform.example.com:8000","allow_local_oauth_http":true,"authorize_url":"/api/method/frappe.integrations.oauth2.authorize","access_token_url":"/api/method/frappe.integrations.oauth2.get_token","redirect_url":"https://runner-test.localhost/api/method/frappe.integrations.oauth2_logins.custom/platform_oauth","api_endpoint":"/api/method/frappe.integrations.oauth2.openid_profile","custom_base_url":true,"auth_url_data":{"response_type":"code","scope":"openid"},"sign_ups":""}'

run_command oauth_nonlocal_http_reject \
  "{\"apiVersion\":\"lenscloud.io/v1\",\"kind\":\"BenchCommand\",\"commandId\":\"local-21\",\"command\":\"oauth.configure\",${base_target},\"args\":${oauth_nonlocal_http},\"timeoutSeconds\":60}" \
  1 | grep '"code":"INVALID_ARGUMENTS"' >/dev/null

echo "Bench command runner local verification passed."
