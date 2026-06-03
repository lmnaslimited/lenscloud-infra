#!/usr/bin/env bash
set -euo pipefail

: "${MANAGER_NAME:=lenscloud-eu-manager-1}"
: "${WORKER_NAME:=lenscloud-eu-worker-1}"

kubectl label node "$MANAGER_NAME" lenscloud.io/node-role=manager --overwrite
kubectl label node "$WORKER_NAME" lenscloud.io/node-role=worker --overwrite
kubectl taint node "$MANAGER_NAME" lenscloud.io/manager-only=true:NoSchedule --overwrite
kubectl get nodes --show-labels
