#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/operators/mariadb-operator-helmchart.yaml
kubectl apply -f manifests/operators/frappe-operator-release-install.yaml

echo "Waiting for CRDs..."
for crd in frappebenches.vyogo.tech frappesites.vyogo.tech sitebackups.vyogo.tech siterestores.vyogo.tech mariadbs.k8s.mariadb.com; do
  for _ in $(seq 1 90); do
    if kubectl get "crd/${crd}" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null | grep -q True; then
      break
    fi
    sleep 2
  done
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=30s
done

kubectl get crd | grep -E 'frappe|mariadb|sitebackup|siterestore'
kubectl get pods -A
