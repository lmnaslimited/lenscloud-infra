#!/usr/bin/env bash
set -euo pipefail

ensure_secret() {
  local namespace="$1"
  local name="$2"
  local key="$3"

  if kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1; then
    return
  fi

  local value
  value="$(openssl rand -base64 32)"
  kubectl -n "$namespace" create secret generic "$name" "--from-literal=${key}=${value}"
}

ensure_secret default frappe-mariadb-root password
ensure_secret default dev-site-admin-password password
ensure_secret default onecx-admin-password password
ensure_secret default twocx-admin-password password
ensure_secret default shared-db-site-a-admin-password password
ensure_secret default shared-db-site-b-admin-password password
ensure_secret default wildcard-smoke-admin-password password
ensure_secret default handoff-site-admin-password password

echo "Smoke Secrets exist. Values were not printed."
