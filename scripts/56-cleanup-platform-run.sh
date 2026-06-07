#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
: "${RUN_NAMESPACE:=lenscloud-runtime-eu}"
: "${RUN_PREFIX:?Set RUN_PREFIX to the exact run-* prefix}"

case "$RUN_PREFIX" in
  run-*) ;;
  *) echo "RUN_PREFIX must begin with run-" >&2; exit 1 ;;
esac

resources=(
  frappesites.vyogo.tech
  frappebenches.vyogo.tech
  mariadbs.k8s.mariadb.com
  jobs.batch
  secrets
  persistentvolumeclaims
)

for resource in "${resources[@]}"; do
  while IFS=/ read -r kind name; do
    [[ -n "${name:-}" ]] || continue
    case "$name" in
      "$RUN_PREFIX"|"$RUN_PREFIX"-*)
        kubectl -n "$RUN_NAMESPACE" delete "$kind/$name" --ignore-not-found
        ;;
    esac
  done < <(kubectl -n "$RUN_NAMESPACE" get "$resource" -o name)
done

if kubectl -n "$RUN_NAMESPACE" get \
  mariadb,frappebench,frappesite,job,pvc,secret -o name |
  grep -E "/${RUN_PREFIX}(-|$)"
then
  echo "Exact-prefix resources remain." >&2
  exit 1
fi

kubectl -n default get mariadb frappe-mariadb
echo "Cleanup complete; protected default/frappe-mariadb remains present."
