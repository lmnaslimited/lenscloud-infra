#!/usr/bin/env bash
set -euo pipefail

: "${HCLOUD_FIREWALL:=lenscloud-eu-firewall}"
: "${PLATFORM_API_WATCH_INTERVAL:=30}"

description="lenscloud-platform-api"
mode="${1:---once}"

current_public_ip() {
  if [[ -n "${PLATFORM_PUBLIC_IP:-}" ]]; then
    printf '%s\n' "${PLATFORM_PUBLIC_IP%/32}"
    return
  fi
  curl -4 -fsS https://api.ipify.org
}

authorize_current_ip() {
  local public_ip source_ip existing_sources
  public_ip="$(current_public_ip)"
  if [[ ! "$public_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Unable to determine a valid public IPv4 address." >&2
    return 1
  fi
  source_ip="${public_ip}/32"
  existing_sources="$(
    hcloud firewall describe "$HCLOUD_FIREWALL" -o json |
      jq -r --arg description "$description" '
        .rules[]
        | select(.direction == "in" and .protocol == "tcp" and .port == "6443" and .description == $description)
        | .source_ips[]
      '
  )"

  if [[ "$existing_sources" == "$source_ip" ]]; then
    echo "Kubernetes API access already authorized for ${source_ip}."
    return
  fi

  while IFS= read -r existing_source; do
    [[ -n "$existing_source" ]] || continue
    hcloud firewall delete-rule "$HCLOUD_FIREWALL" \
      --direction in \
      --protocol tcp \
      --port 6443 \
      --source-ips "$existing_source" \
      --description "$description"
  done <<<"$existing_sources"

  hcloud firewall add-rule "$HCLOUD_FIREWALL" \
    --direction in \
    --protocol tcp \
    --port 6443 \
    --source-ips "$source_ip" \
    --description "$description"

  echo "Kubernetes API access authorized for ${source_ip}."
}

case "$mode" in
  --once)
    authorize_current_ip
    ;;
  --watch)
    echo "Watching for Platform public IPv4 changes every ${PLATFORM_API_WATCH_INTERVAL}s. Press Ctrl-C to stop."
    last_ip=""
    while true; do
      detected_ip="$(current_public_ip 2>/dev/null || true)"
      if [[ -n "$detected_ip" && "$detected_ip" != "$last_ip" ]]; then
        if authorize_current_ip; then
          last_ip="$detected_ip"
        fi
      fi
      sleep "$PLATFORM_API_WATCH_INTERVAL"
    done
    ;;
  *)
    echo "Usage: $0 [--once|--watch]" >&2
    exit 2
    ;;
esac
