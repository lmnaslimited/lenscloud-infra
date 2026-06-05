#!/usr/bin/env bash
set -euo pipefail

: "${CONFIRM_TRAEFIK_CUTOVER:?Set CONFIRM_TRAEFIK_CUTOVER=yes after side-by-side and TLS validation}"
test "$CONFIRM_TRAEFIK_CUTOVER" = "yes"

kubectl -n traefik get secret lenscloud-cloud-wildcard-tls
kubectl apply -f manifests/ingress/traefik-default-tls-store.yaml

kubectl -n ingress-nginx patch service ingress-nginx-controller \
  --type merge \
  -p '{"spec":{"type":"NodePort"}}'

kubectl apply -f manifests/ingress/traefik-loadbalancer-helmchart.yaml
kubectl -n traefik rollout status deployment/traefik --timeout=240s
./scripts/34-allow-servicelb-on-manager.sh traefik

./scripts/48-update-frappe-operator-ingress.sh
kubectl apply -f manifests/ui/headlamp-ingress.yaml
kubectl -n traefik get service traefik
kubectl get ingress -A -o wide

echo "Traefik owns the public LoadBalancer ports. Keep ingress-nginx until final verification passes."
