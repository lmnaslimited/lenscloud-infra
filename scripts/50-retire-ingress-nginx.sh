#!/usr/bin/env bash
set -euo pipefail

: "${CONFIRM_RETIRE_INGRESS_NGINX:?Set CONFIRM_RETIRE_INGRESS_NGINX=yes after final HTTPS verification}"
test "$CONFIRM_RETIRE_INGRESS_NGINX" = "yes"

kubectl -n traefik get service traefik
kubectl -n traefik get secret lenscloud-cloud-wildcard-tls
kubectl get ingress -A -o wide

kubectl -n kube-system delete helmchart ingress-nginx --ignore-not-found
kubectl delete namespace ingress-nginx --ignore-not-found

echo "ingress-nginx retired. Reapply manifests/ingress/ingress-nginx-helmchart.yaml for rollback."
