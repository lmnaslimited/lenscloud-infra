#!/usr/bin/env bash
set -euo pipefail

service_name="${1:?Service name required}"

for _ in $(seq 1 60); do
  daemonset="$(
    kubectl -n kube-system get daemonset \
      -l "svccontroller.k3s.cattle.io/svcname=${service_name}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
  )"
  if test -n "$daemonset"; then
    break
  fi
  sleep 2
done

test -n "${daemonset:-}"

if ! kubectl -n kube-system get daemonset "$daemonset" -o json |
  jq -e '.spec.template.spec.tolerations[]? |
    select(.key == "lenscloud.io/manager-only")' >/dev/null; then
  kubectl -n kube-system patch daemonset "$daemonset" \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"lenscloud.io/manager-only","operator":"Equal","value":"true","effect":"NoSchedule"}}]'
fi

kubectl -n kube-system rollout status "daemonset/$daemonset" --timeout=180s
kubectl -n kube-system get pods \
  -l "svccontroller.k3s.cattle.io/svcname=${service_name}" \
  -o wide
