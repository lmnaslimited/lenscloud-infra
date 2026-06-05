#!/usr/bin/env bash
set -euo pipefail

: "${CERTBOT_IMAGE_REPOSITORY:=ghcr.io/lmnaslimited/lenscloud-certbot-godaddy}"
: "${CERTBOT_IMAGE_TAG:=2.8.0}"
: "${PUSH_CERTBOT_IMAGE:=false}"

image="${CERTBOT_IMAGE_REPOSITORY}:${CERTBOT_IMAGE_TAG}"
docker build --platform linux/amd64 -t "$image" certbot
docker run --rm --platform linux/amd64 "$image" plugins

if test "$PUSH_CERTBOT_IMAGE" = "true"; then
  docker push "$image"
fi

digest="$(docker image inspect "$image" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
if test -n "$digest"; then
  printf 'export CERTBOT_IMAGE=%q\n' "$digest"
else
  echo "Image validated locally. Push it to obtain the immutable registry digest." >&2
  printf 'export CERTBOT_IMAGE=%q\n' "$image"
fi
