#!/usr/bin/env bash
set -euo pipefail

: "${CERTBOT_IMAGE:?Set CERTBOT_IMAGE to an immutable image digest}"
: "${CERTBOT_EMAIL:?Set CERTBOT_EMAIL}"
: "${CERTBOT_DOMAIN:=cloud.lmnaslens.com}"

case "$CERTBOT_IMAGE" in
  *@sha256:*) ;;
  *) echo "CERTBOT_IMAGE must be pinned by sha256 digest." >&2; exit 1 ;;
esac

mkdir -p manifests/generated
export CERTBOT_IMAGE CERTBOT_EMAIL CERTBOT_DOMAIN

envsubst < manifests/edge/certbot-issue-job.template.yaml \
  > manifests/generated/certbot-issue-job.yaml
envsubst < manifests/edge/certbot-renew-cronjob.template.yaml \
  > manifests/generated/certbot-renew-cronjob.yaml

echo "Rendered manifests/generated/certbot-*.yaml"
