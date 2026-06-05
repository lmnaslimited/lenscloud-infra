#!/usr/bin/env bash
set -euo pipefail

./scripts/41-create-smoke-secrets.sh
kubectl apply -f manifests/smoke/shared-database-two-benches.yaml

kubectl wait --for=jsonpath='{.status.phase}'=Ready frappebench/shared-db-bench-a --timeout=20m
kubectl wait --for=jsonpath='{.status.phase}'=Ready frappebench/shared-db-bench-b --timeout=20m
kubectl wait --for=jsonpath='{.status.phase}'=Ready frappesite/shared-db-site-a --timeout=20m
kubectl wait --for=jsonpath='{.status.phase}'=Ready frappesite/shared-db-site-b --timeout=20m

for bench in shared-db-bench-a shared-db-bench-b; do
  test "$(kubectl get frappebench "$bench" -o jsonpath='{.spec.dbConfig.mariadbRef.name}')" = "frappe-mariadb"
  test "$(kubectl get frappebench "$bench" -o jsonpath='{.spec.dbConfig.mariadbRef.namespace}')" = "default"
done

site_a_db="$(
  kubectl get secret shared-db-site-a-init-secrets \
    -o jsonpath='{.data.db_name}' | base64 -d
)"
site_b_db="$(
  kubectl get secret shared-db-site-b-init-secrets \
    -o jsonpath='{.data.db_name}' | base64 -d
)"
site_a_user="$(
  kubectl get secret shared-db-site-a-init-secrets \
    -o jsonpath='{.data.db_user}' | base64 -d
)"
site_b_user="$(
  kubectl get secret shared-db-site-b-init-secrets \
    -o jsonpath='{.data.db_user}' | base64 -d
)"

test -n "$site_a_db"
test -n "$site_b_db"
test -n "$site_a_user"
test -n "$site_b_user"
test "$site_a_db" != "$site_b_db"
test "$site_a_user" != "$site_b_user"

kubectl get frappebench,frappesite,mariadb,pods,pvc -o wide
echo "Two-Bench shared MariaDB smoke passed."
