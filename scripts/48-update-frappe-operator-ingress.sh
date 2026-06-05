#!/usr/bin/env bash
set -euo pipefail

: "${FRAPPE_OPERATOR_NAMESPACE:=frappe-operator-system}"
: "${FRAPPE_OPERATOR_CONFIGMAP:=frappe-operator-frappe-operator-config}"

kubectl -n "$FRAPPE_OPERATOR_NAMESPACE" patch configmap "$FRAPPE_OPERATOR_CONFIGMAP" \
  --type merge \
  -p '{"data":{"ingressControllerNamespace":"traefik","ingressControllerService":"traefik"}}'

deployment="$(
  kubectl -n "$FRAPPE_OPERATOR_NAMESPACE" get deployment \
    -l control-plane=controller-manager \
    -o jsonpath='{.items[0].metadata.name}'
)"

if test -z "$deployment"; then
  deployment="$(
    kubectl -n "$FRAPPE_OPERATOR_NAMESPACE" get deployment \
      -o jsonpath='{.items[0].metadata.name}'
  )"
fi

kubectl -n "$FRAPPE_OPERATOR_NAMESPACE" rollout restart "deployment/$deployment"
kubectl -n "$FRAPPE_OPERATOR_NAMESPACE" rollout status "deployment/$deployment" --timeout=240s

echo "Frappe Operator ingress discovery now points to traefik/traefik."
