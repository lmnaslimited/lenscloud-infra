#!/usr/bin/env bash
set -euo pipefail

: "${CLUSTER_NAME:=lenscloud-eu-dev}"
: "${LOCATION:=nbg1}"
: "${NETWORK_ZONE:=eu-central}"
: "${NETWORK_NAME:=lenscloud-eu-net}"
: "${NETWORK_CIDR:=10.20.0.0/16}"
: "${SUBNET_CIDR:=10.20.1.0/24}"
: "${FIREWALL_NAME:=lenscloud-eu-firewall}"
: "${MANAGER_NAME:=lenscloud-eu-manager-1}"
: "${WORKER_NAME:=lenscloud-eu-worker-1}"
: "${MANAGER_TYPE:=cx23}"
: "${WORKER_TYPE:=cx33}"
: "${SSH_KEY_NAME:=team-lead-key}"

ensure_network() {
  if ! hcloud network describe "$NETWORK_NAME" >/dev/null 2>&1; then
    hcloud network create --name "$NETWORK_NAME" --ip-range "$NETWORK_CIDR"
  fi

  if ! hcloud network describe "$NETWORK_NAME" -o json | jq -e --arg cidr "$SUBNET_CIDR" '.subnets[]? | select(.ip_range == $cidr)' >/dev/null; then
    hcloud network add-subnet "$NETWORK_NAME" --network-zone "$NETWORK_ZONE" --type cloud --ip-range "$SUBNET_CIDR"
  fi
}

ensure_firewall() {
  if ! hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
    hcloud firewall create --name "$FIREWALL_NAME"
  fi

  if ! hcloud firewall describe "$FIREWALL_NAME" -o json | jq -e '.rules | length > 0' >/dev/null; then
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 22 --source-ips 0.0.0.0/0 --source-ips ::/0 --description ssh-key-only
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --source-ips ::/0
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --source-ips ::/0
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port any --source-ips "$NETWORK_CIDR"
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol udp --port any --source-ips "$NETWORK_CIDR"
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol icmp --source-ips "$NETWORK_CIDR"
  fi
}

ensure_server() {
  local name="$1"
  local type="$2"

  if hcloud server describe "$name" >/dev/null 2>&1; then
    return
  fi

  hcloud server create \
    --name "$name" \
    --type "$type" \
    --image ubuntu-24.04 \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_NAME" \
    --network "$NETWORK_NAME" \
    --firewall "$FIREWALL_NAME" \
    --label "lenscloud.io/cluster=$CLUSTER_NAME" \
    --label "lenscloud.io/region=eu"
}

ensure_network
ensure_firewall
ensure_server "$MANAGER_NAME" "$MANAGER_TYPE"
ensure_server "$WORKER_NAME" "$WORKER_TYPE"

hcloud server list -o columns=name,status,ipv4,private_net,location,type | grep -E "NAME|$MANAGER_NAME|$WORKER_NAME"
