#!/usr/bin/env bash
set -euo pipefail

: "${GODADDY_API_KEY:?Set GODADDY_API_KEY}"
: "${GODADDY_API_SECRET:?Set GODADDY_API_SECRET}"
: "${GODADDY_DOMAIN:=lmnaslens.com}"
: "${GODADDY_PREFLIGHT_NAME:=_lenscloud-preflight.cloud}"

api="https://api.godaddy.com/v1/domains/${GODADDY_DOMAIN}/records/TXT/${GODADDY_PREFLIGHT_NAME}"
auth="Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}"
original="$(mktemp)"
payload="$(mktemp)"
response="$(mktemp)"
trap 'rm -f "$original" "$payload" "$response"' EXIT

api_request() {
  local method="$1"
  local output="$2"
  shift 2

  local status
  status="$(
    curl -sS \
      -o "$output" \
      -w '%{http_code}' \
      -X "$method" \
      -H "$auth" \
      "$@" \
      "$api"
  )"

  if [[ ! "$status" =~ ^2 ]]; then
    echo "GoDaddy API request failed: method=${method} status=${status}" >&2
    jq -c '{code, message, fields}' "$output" 2>/dev/null >&2 ||
      sed -n '1,10p' "$output" >&2
    return 1
  fi
}

api_request GET "$original"
printf '[{"data":"lenscloud-preflight-%s","ttl":600}]\n' "$(date +%s)" >"$payload"

restore_record() {
  if test "$(jq 'length' "$original")" -gt 0; then
    api_request PUT "$response" \
      -H "Content-Type: application/json" \
      --data-binary "@$original"
  else
    api_request DELETE "$response"
  fi
}
trap 'restore_record || true; rm -f "$original" "$payload" "$response"' EXIT

api_request PUT "$response" \
  -H "Content-Type: application/json" \
  --data-binary "@$payload"

api_request GET "$response"
test "$(jq 'length' "$response")" -eq 1
restore_record
trap 'rm -f "$original" "$payload" "$response"' EXIT

echo "GoDaddy production API TXT create/read/restore preflight passed."
