#!/usr/bin/env bash
set -euo pipefail

kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get crd | grep -E 'frappe|mariadb|sitebackup|siterestore'
kubectl get mariadb,frappebench,frappesite,pvc -A

