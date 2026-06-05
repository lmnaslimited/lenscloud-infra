#!/usr/bin/env bash
set -euo pipefail

kubectl -n lenscloud-edge get secret godaddy-dns-api
test -f manifests/generated/certbot-issue-job.yaml
test -f manifests/generated/certbot-renew-cronjob.yaml

kubectl apply -f manifests/edge/certbot-rbac.yaml

if ! kubectl -n traefik get secret lenscloud-cloud-wildcard-tls >/dev/null 2>&1; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj "/CN=bootstrap.invalid" \
    -keyout "$tmp_dir/tls.key" \
    -out "$tmp_dir/tls.crt" >/dev/null 2>&1
  kubectl -n traefik create secret tls lenscloud-cloud-wildcard-tls \
    --cert="$tmp_dir/tls.crt" \
    --key="$tmp_dir/tls.key"
fi

kubectl delete job certbot-wildcard-issue -n lenscloud-edge --ignore-not-found
kubectl apply -f manifests/generated/certbot-issue-job.yaml
kubectl -n lenscloud-edge wait --for=condition=Complete job/certbot-wildcard-issue --timeout=30m
kubectl -n lenscloud-edge logs job/certbot-wildcard-issue

kubectl -n traefik get secret lenscloud-cloud-wildcard-tls
kubectl apply -f manifests/ingress/traefik-default-tls-store.yaml
kubectl apply -f manifests/generated/certbot-renew-cronjob.yaml

echo "Wildcard certificate issued and renewal CronJob installed."
