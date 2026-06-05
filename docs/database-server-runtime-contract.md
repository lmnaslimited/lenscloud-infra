# Database Server Runtime Contract

## Purpose

This document defines the infrastructure contract consumed by LensCloud Platform for first-class Database Server management.

Infra owns:

- MariaDB Operator installation
- storage, node placement, networking, and MariaDB CR availability
- runtime verification and handoff values
- the SOP for creating or importing an operator-managed MariaDB service

LensCloud Platform owns:

- Database Server master/runtime records
- privacy and sharing policy
- Bench attachment
- manifest generation and orchestration actions
- status and audit presentation

## Current Proven Runtime

The live EU cluster already contains:

- Cluster: `lenscloud-eu-dev`
- Region: EU
- MariaDB Operator namespace: `mariadb-operator-system`
- MariaDB CR API: `k8s.mariadb.com/v1alpha1`
- MariaDB CR: `frappe-mariadb`
- MariaDB CR namespace: `default`
- image: `mariadb:10.11`
- storage: `8Gi`
- storage class: `local-path`
- replicas: `1`
- port: `3306`
- worker placement: `lenscloud.io/node-role=worker`
- root secret reference: `frappe-mariadb-root`, key `password`

The secret value is not part of the handoff and must not be committed or copied into LensCloud fields.

## Platform Handoff Values

The live smoke MariaDB can be registered in LensCloud as:

- title: `EU Shared MariaDB 01`
- engine: `MariaDB`
- provisioning type: `Operator Managed`
- Region: `EU`
- Cluster: `lenscloud-eu-dev`
- privacy: `Public`
- Kubernetes namespace: `default`
- operator resource name: `frappe-mariadb`
- image: `mariadb:10.11`
- storage class: `local-path`
- storage size: `8Gi`
- replica count: `1`
- service port: `3306`
- root credential reference: Kubernetes Secret `frappe-mariadb-root`
- status: derive from the live MariaDB CR

## Bench Attachment Contract

A Bench attached to this Database Server must generate:

```yaml
spec:
  dbConfig:
    provider: mariadb
    mode: shared
    mariadbRef:
      name: frappe-mariadb
      namespace: default
```

The Frappe Operator supports this configuration as the Bench default. Multiple Benches may reference the same MariaDB CR when LensCloud privacy/capacity policy permits it.

Operator `mode: shared` describes database topology. LensCloud `Public`, `Private Shared`, and `Private` describe commercial/privacy isolation policy. They must not be treated as the same field.

## Runtime Rules

- MariaDB data remains on block/local storage for the current POC, not NFS.
- Database workloads run on worker nodes.
- A Database Server must be in the same Region and Cluster as an attached Bench for the first operator-managed implementation.
- Cross-cluster database access is out of scope for the first implementation.
- Private network exposure, NetworkPolicy, TLS, backup, and HA are separate production-readiness workitems.
- A one-replica `local-path` MariaDB is not HA and must be labeled accordingly.

## Verification Commands

Run on the EU manager:

```bash
export KUBECONFIG=/root/.kube/config

kubectl get mariadb frappe-mariadb -n default -o yaml
kubectl get service,pod,pvc -n default -l app.kubernetes.io/instance=frappe-mariadb -o wide
kubectl get secret frappe-mariadb-root -n default
```

Do not print or export the Secret value during normal verification.

To verify Bench references:

```bash
kubectl get frappebench -A -o yaml
kubectl get frappesite -A -o yaml
```

## Next Infra Workitems

1. Preserve the existing smoke MariaDB as the first registered shared Database Server.
2. Add a reusable, non-secret MariaDB manifest template for LensCloud dry-run comparison.
3. Add a smoke scenario where two Benches reference one MariaDB CR.
4. Document NetworkPolicy and service access requirements.
5. Add backup/restore verification for MariaDB data.
6. Design production storage and HA separately; do not use NFS as the primary MariaDB data store.
