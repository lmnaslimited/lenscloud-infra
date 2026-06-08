# Platform Runtime Lifecycle Evidence - June 8, 2026

## Scope

- Infra implementation revision applied: `5dd4178`
- cluster: `lenscloud-eu-dev`
- service account: `lenscloud-platform-system/lenscloud-platform`
- runtime namespace: `lenscloud-runtime-eu`
- protected baseline: `MariaDB/default/frappe-mariadb`
- Public cleanup prefix: `run-20260607-0623`

No kubeconfig, token, password, Secret value, or private key was recorded.

## Policy Deployment

Applied successfully:

- runtime CRUD/delete RBAC for MariaDB, FrappeBench, and FrappeSite;
- related-resource read access;
- owned Job, PVC, and Secret delete access;
- read-only MariaDB access in `default`;
- `ValidatingAdmissionPolicy/lenscloud-platform-owned-delete`;
- matching policy binding scoped to the managed runtime namespace.

The admission policy requires
`lenscloud.io/managed-by=platform` for direct deletes by the Platform service
account.

## Positive Evidence

- Host and manager restricted permission preflights passed.
- Runtime Pods, Services, Jobs, PVCs, Ingresses, and Events are inspectable.
- Labelled owned Secret, Job, and PVC deletion passed.
- Three accepted Public FrappeSites were deleted through the restricted
  Platform identity.
- All three Site finalizers completed normally.
- Both accepted Public FrappeBenches were deleted through the restricted
  Platform identity after Site removal.
- Both Bench finalizers completed normally.
- A temporary labelled MariaDB was created through the restricted identity,
  reached Ready, and was deleted through the restricted identity.
- The MariaDB finalizer completed normally.

MariaDB deletion retained its data PVC by operator/storage policy. This proves
that Platform deletion must inventory and explicitly clean an attributable,
labelled PVC when the product deletion policy requests data removal.

## Negative Evidence

The restricted identity remained unable to:

- patch or delete `MariaDB/default/frappe-mariadb`;
- delete an unlabelled runtime Secret;
- list runtime Secrets;
- access or delete Secrets in `default` or `traefik`;
- delete Frappe resources in `default`;
- mutate Nodes, namespaces, CRDs, StorageClasses, operator Deployments,
  Traefik, or cluster infrastructure.

Cross-namespace and cluster-scoped mutation checks passed as denied.

## Public Cleanup

The five legacy Public owner CRs predated ownership labels. Their documented
ownership was confirmed, then only those exact resources were labelled and
deleted in dependency order:

- Sites:
  - `run-20260607-0623-platform`
  - `run-20260607-0623-customer`
  - `run-20260607-0623-free`
- Benches:
  - `run-20260607-0623-pub-a`
  - `run-20260607-0623-pub-b`

Exact-prefix residual PVCs and Secrets were removed with the guarded cleanup
script. No `run-20260607-0623*` MariaDB, Bench, Site, Job, PVC, Secret, or
Ingress remained afterward.

## Baseline And Capacity

- manager and worker: Ready
- pressure conditions: false
- worker scheduled requests: CPU 59%, memory 47%
- MariaDB Operator: Ready
- Frappe Operator: Ready
- Traefik: Ready
- Headlamp: Ready
- wildcard TLS Secret: present
- `local-path`: default StorageClass
- `MariaDB/default/frappe-mariadb`: Ready/Running

The cluster has sufficient headroom for sequential Private Shared and Private
acceptance. The scenarios should not run concurrently.

## Final Local Cleanup

The temporary MariaDB acceptance retained:

```text
PVC/lenscloud-runtime-eu/storage-infra-lifecycle-mariadb-0
```

It is not part of the Public prefix. It must be labelled with the temporary
Database Server identity and deleted through the restricted Platform identity:

```bash
kubectl -n lenscloud-runtime-eu label pvc \
  storage-infra-lifecycle-mariadb-0 \
  lenscloud.io/managed-by=platform \
  lenscloud.io/resource-kind=database-server \
  lenscloud.io/resource-id=infra-lifecycle-mariadb \
  --overwrite

kubectl --kubeconfig .artifacts/lenscloud-eu.kubeconfig \
  -n lenscloud-runtime-eu delete pvc \
  storage-infra-lifecycle-mariadb-0
```

This final test-artifact deletion was pending when the execution approval
quota interrupted the session. It does not block Platform lifecycle authority
or sequential acceptance capacity, but must be removed before calling the
runtime namespace empty.
