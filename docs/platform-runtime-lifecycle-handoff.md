# Platform Runtime Lifecycle Handoff

Minimum Infra lifecycle implementation revision: `1f57682`.

Live EU verification was completed against revision `5dd4178` on June 8, 2026.
See `docs/platform-runtime-lifecycle-evidence-20260608.md`.

## Authority

After cluster handoff, LensCloud Platform owns routine lifecycle operations for
its resources in `lenscloud-runtime-eu`:

- `MariaDB`
- `FrappeBench`
- `FrappeSite`
- explicitly owned Jobs, PVCs, and Secrets needed for cleanup

Infra continues to own nodes, namespaces, CRDs, operators, RBAC, storage,
Traefik, wildcard TLS, Certbot, Headlamp, and the protected Public database
`MariaDB/default/frappe-mariadb`.

## Identity

- service account: `lenscloud-platform-system/lenscloud-platform`
- runtime namespace: `lenscloud-runtime-eu`
- backend credential reference:
  `file:/run/secrets/lenscloud-eu.kubeconfig`

The credential remains server-side and must never be returned to the browser,
logs, action records, or manifest previews.

## Ownership Contract

Every Platform-created runtime owner must carry:

```yaml
metadata:
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: <database-server|bench|site>
    lenscloud.io/resource-id: <platform-document-name>
    lenscloud.io/customer: <customer-id-when-applicable>
```

Infra admission denies direct deletes by the Platform service account when
`lenscloud.io/managed-by=platform` is absent. LensCloud must additionally
verify the exact Cluster, namespace, kind, resource ID, customer/privacy
boundary, dependency state, protected-resource denylist, user permission, and
destructive confirmation before deletion.

Kubernetes RBAC cannot express label-qualified permissions. The admission
guard enforces the primary ownership label, while LensCloud is the required
second policy layer for document identity and business ownership. Operator
dependents that do not inherit the ownership label should normally be removed
by owner references/finalizers. Direct Platform cleanup is unavailable until
the dependent is demonstrably owned and labelled.

## Permissions

In `lenscloud-runtime-eu`, Platform can reconcile and delete MariaDB,
FrappeBench, and FrappeSite resources; inspect Pods, Services, Jobs, PVCs,
Ingresses, and Events; and delete labelled owned Jobs, PVCs, and Secrets.
Secret listing remains denied.

In `default`, Platform has read-only MariaDB access. It cannot patch, replace,
or delete `frappe-mariadb`, and it has no Secret access there.

Cross-namespace, cluster-scoped, operator, edge, and infrastructure Secret
operations remain denied.

## Platform Next Work

At Platform revision `818c262`:

1. add the ownership labels to all generated runtime manifests;
2. add secret-safe related-resource inventory APIs;
3. add dependency-aware Site, Bench, and Database Server delete APIs;
4. use asynchronous `Deletion Requested`, `Quiescing`, `Deleting`, `Deleted`,
   and `Deletion Failed` states;
5. record reconcile, delete, retry, and status actions;
6. expose inspect/delete/progress/retry in the operator UI;
7. prove managed create/inspect/delete without manager access;
8. resume sequential Private Shared and Private acceptance.

Platform must never remove finalizers manually as a normal lifecycle action.
An operator finalizer failure becomes `Deletion Failed` with diagnostic
evidence and an explicit Infra escalation.

MariaDB finalizer completion does not imply data PVC deletion. Platform must
inventory the attributable PVC and apply its explicit retain/delete data
policy before retiring the Database Server document.
