#!/usr/bin/env bash
set -euo pipefail

job_name=certbot-wildcard-renew-dry-run

kubectl -n lenscloud-edge get cronjob certbot-wildcard-renew >/dev/null
kubectl -n lenscloud-edge delete job "$job_name" --ignore-not-found

kubectl -n lenscloud-edge create job \
  --from=cronjob/certbot-wildcard-renew \
  "$job_name" \
  --dry-run=client \
  -o json |
  jq '.spec.template.spec.containers[0].args = ["renew-dry-run"]' |
  kubectl apply -f -

kubectl -n lenscloud-edge wait \
  --for=condition=Complete \
  "job/$job_name" \
  --timeout=30m
kubectl -n lenscloud-edge logs "job/$job_name"

echo "Certbot renewal dry-run passed using the production CronJob configuration."
