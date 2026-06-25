# Legacy Namespace Inventory - 2026-06-25

## Scope

Platform requested Infra verification after the Platform cleanup recorded in:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/cleanup-evidence-20260625.md
```

Question:

- Does legacy namespace `bench-lenscx-eu-public` exist?
- Do any old `FrappeBench` or `FrappeSite` resources remain there?

No kubeconfig, token, password, private key, or Kubernetes Secret value was
printed or stored in this evidence.

## Backlog

Tracked as `INF-009` in [infra-workitems.md](./infra-workitems.md).

## Commands Run

From the live EU manager using admin Kubernetes access:

```bash
kubectl get namespace bench-lenscx-eu-public --show-labels
kubectl -n bench-lenscx-eu-public get frappebench,frappesite,mariadb,pods,pvc,ingress,secret --ignore-not-found -o wide
kubectl get namespaces --show-labels | grep -E "lenscx|bench|lenscloud-runtime|platform" || true
kubectl get frappebench,frappesite -A --ignore-not-found -o wide
kubectl get mariadb -A --ignore-not-found -o wide
```

## Findings

### Legacy Namespace

`bench-lenscx-eu-public` does not exist.

Result:

```text
Error from server (NotFound): namespaces "bench-lenscx-eu-public" not found
```

Because the namespace is absent, there are no `FrappeBench`, `FrappeSite`,
`MariaDB`, Pod, PVC, Ingress, or Secret resources inside
`bench-lenscx-eu-public`.

### Approved Platform Runtime Namespace

Existing Platform-related namespaces:

```text
lenscloud-platform-system   Active
lenscloud-runtime-eu        Active
```

`lenscloud-runtime-eu` is the approved Platform runtime namespace. It is not
the legacy namespace requested for this inventory.

### Cluster-Wide Frappe Operator Resources

Although `bench-lenscx-eu-public` is absent, old smoke resources remain in the
`default` namespace:

```text
FrappeBench/default/dev-bench           Ready
FrappeBench/default/shared-db-bench-a   Ready
FrappeBench/default/shared-db-bench-b   Ready

FrappeSite/default/dev-site             Ready
FrappeSite/default/shared-db-site-a     Ready
FrappeSite/default/shared-db-site-b     Ready
FrappeSite/default/wildcard-smoke       Ready
```

Protected MariaDB baseline remains:

```text
MariaDB/default/frappe-mariadb          Ready / Running
```

Related default namespace resources include:

- running Pods for `dev-bench`, `shared-db-bench-a`, and `shared-db-bench-b`;
- PVCs:
  - `dev-bench-sites`
  - `shared-db-bench-a-sites`
  - `shared-db-bench-b-sites`
  - `storage-frappe-mariadb-0`
- Traefik Ingresses:
  - `shared-db-site-a-ingress`
  - `shared-db-site-b-ingress`
  - `wildcard-smoke-ingress`
- Services for the three old Benches and protected `frappe-mariadb`.

## Cleanup Assessment

For `bench-lenscx-eu-public`:

- no cleanup is required because the namespace does not exist.
- no resources can be removed there.

For old smoke resources in `default`:

- they are outside the Platform-approved runtime namespace contract;
- they pre-date the current Platform cleanup;
- they appear to be old Infra smoke resources;
- they may be safe to remove if Infra confirms no active test depends on them;
- `MariaDB/default/frappe-mariadb` and PVC `storage-frappe-mariadb-0` must be
  preserved.

Do not run cleanup without explicit approval.

## Proposed Cleanup Commands

No cleanup command is needed for `bench-lenscx-eu-public`.

If Infra approves cleanup of the old `default` smoke resources, use normal
operator deletion order:

```bash
kubectl -n default delete frappesite \
  dev-site \
  shared-db-site-a \
  shared-db-site-b \
  wildcard-smoke \
  --wait=false

kubectl -n default wait --for=delete frappesite/dev-site --timeout=10m
kubectl -n default wait --for=delete frappesite/shared-db-site-a --timeout=10m
kubectl -n default wait --for=delete frappesite/shared-db-site-b --timeout=10m
kubectl -n default wait --for=delete frappesite/wildcard-smoke --timeout=10m

kubectl -n default delete frappebench \
  dev-bench \
  shared-db-bench-a \
  shared-db-bench-b \
  --wait=false

kubectl -n default wait --for=delete frappebench/dev-bench --timeout=10m
kubectl -n default wait --for=delete frappebench/shared-db-bench-a --timeout=10m
kubectl -n default wait --for=delete frappebench/shared-db-bench-b --timeout=10m
```

Post-cleanup verification, if approved:

```bash
kubectl -n default get frappebench,frappesite --ignore-not-found
kubectl -n default get mariadb frappe-mariadb
kubectl -n default get pvc storage-frappe-mariadb-0
```

Do not delete:

```text
MariaDB/default/frappe-mariadb
PVC/default/storage-frappe-mariadb-0
```
