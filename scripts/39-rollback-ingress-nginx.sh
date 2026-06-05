#!/usr/bin/env bash
set -euo pipefail

: "${CONFIRM_INGRESS_ROLLBACK:?Set CONFIRM_INGRESS_ROLLBACK=yes}"
test "$CONFIRM_INGRESS_ROLLBACK" = "yes"

kubectl apply -f manifests/ingress/traefik-nodeport-helmchart.yaml
kubectl -n ingress-nginx patch service ingress-nginx-controller \
  --type merge \
  -p '{"spec":{"type":"LoadBalancer"}}'
./scripts/34-allow-servicelb-on-manager.sh ingress-nginx-controller

kubectl -n frappe-operator-system patch configmap frappe-operator-frappe-operator-config \
  --type merge \
  -p '{"data":{"ingressControllerNamespace":"ingress-nginx","ingressControllerService":"ingress-nginx-controller"}}'
kubectl -n frappe-operator-system rollout restart deployment/frappe-operator-controller-manager
kubectl -n frappe-operator-system rollout status deployment/frappe-operator-controller-manager --timeout=240s

kubectl apply -f manifests/ui/headlamp-ingress-nginx.yaml
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl get service -n ingress-nginx ingress-nginx-controller
echo "Ingress-nginx restored to LoadBalancer; Traefik remains available on NodePorts."
