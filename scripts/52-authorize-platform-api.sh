#!/usr/bin/env bash
set -euo pipefail

: "${HCLOUD_FIREWALL:=lenscloud-eu-firewall}"
: "${PLATFORM_PUBLIC_IP:=$(curl -4 -fsS https://api.ipify.org)}"

source_ip="${PLATFORM_PUBLIC_IP%/32}/32"
description="lenscloud-platform-api"

while IFS= read -r existing_source; do
  [[ -n "$existing_source" ]] || continue
  hcloud firewall delete-rule "$HCLOUD_FIREWALL" \
    --direction in \
    --protocol tcp \
    --port 6443 \
    --source-ips "$existing_source" \
    --description "$description"
done < <(
  hcloud firewall describe "$HCLOUD_FIREWALL" -o json |
    jq -r --arg description "$description" '
      .rules[]
      | select(.direction == "in" and .protocol == "tcp" and .port == "6443" and .description == $description)
      | .source_ips[]
    '
)

hcloud firewall add-rule "$HCLOUD_FIREWALL" \
  --direction in \
  --protocol tcp \
  --port 6443 \
  --source-ips "$source_ip" \
  --description "$description"

echo "Kubernetes API access authorized for ${source_ip}."
