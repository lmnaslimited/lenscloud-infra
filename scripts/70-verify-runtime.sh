#!/usr/bin/env bash
set -euo pipefail

kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get crd | grep -E 'frappe|mariadb|sitebackup|siterestore'
kubectl get mariadb,frappebench,frappesite,pvc -A
kubectl get ingressclass,ingress -A
kubectl get cronjob,job -n lenscloud-edge 2>/dev/null || true
kubectl get secret lenscloud-cloud-wildcard-tls -n traefik 2>/dev/null || true
