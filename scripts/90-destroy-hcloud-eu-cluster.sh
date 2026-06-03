#!/usr/bin/env bash
set -euo pipefail

: "${NETWORK_NAME:=lenscloud-eu-net}"
: "${FIREWALL_NAME:=lenscloud-eu-firewall}"
: "${MANAGER_NAME:=lenscloud-eu-manager-1}"
: "${WORKER_NAME:=lenscloud-eu-worker-1}"
: "${CONFIRM_DESTROY:?Set CONFIRM_DESTROY=yes to destroy the EU dev cluster}"

if [[ "$CONFIRM_DESTROY" != "yes" ]]; then
  echo "Refusing to destroy. Set CONFIRM_DESTROY=yes."
  exit 1
fi

hcloud server delete "$WORKER_NAME" || true
hcloud server delete "$MANAGER_NAME" || true
hcloud firewall delete "$FIREWALL_NAME" || true
hcloud network delete "$NETWORK_NAME" || true

