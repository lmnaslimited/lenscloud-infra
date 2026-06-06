# Platform Live Orchestration Readiness

## Audit

Validated on June 6, 2026 against Infra revision `1d5d5f3`.

- Kubernetes API is reachable from the LensCloud Platform devcontainer.
- The Hcloud `lenscloud-platform-api` firewall rule contains exactly one current
  IPv4 `/32`; port `6443` is not open to `0.0.0.0/0`.
- Dynamic laptop IP changes are supported by:
  `scripts/52-authorize-platform-api.sh --watch`.
- `lenscloud-runtime-eu` and `lenscloud-platform-system` are Active.
- Service account `lenscloud-platform-system/lenscloud-platform` is present.
- The expected Roles and RoleBindings in `default` and
  `lenscloud-runtime-eu` are present.
- Host-side positive and negative RBAC checks pass.
- LensCloud's backend permission preflight returns
  `all_required_allowed: true`.

## Runtime Health

- Manager: `cx23`, 2 vCPU, 4 GB RAM, Ready.
- Worker: `cx33`, 4 vCPU, 8 GB RAM, Ready.
- MariaDB Operator: Ready.
- Frappe Operator: Ready.
- Traefik: Ready.
- `local-path` is the default StorageClass.
- Wildcard Headlamp HTTPS returns HTTP 200.
- Wildcard certificate expires September 3, 2026 at 14:49 UTC.
- Certbot renewal CronJob is active.
- Existing `default/frappe-mariadb` is Ready.
- Existing FrappeBench and FrappeSite resources are Ready.

The only current warning is a CoreDNS `DNSConfigForming` warning caused by the
host nameserver count. CoreDNS remains Ready and this does not block the
acceptance run.

## Capacity

Worker snapshot:

- actual CPU: about `239m` of 4 cores
- actual memory: about `2.1 GiB` used, `5.5 GiB` available
- scheduled CPU requests: `2375m`, 59%
- scheduled memory requests: `3718 MiB`, 47%
- local disk: about `59 GiB` free
- swap: 4 GiB, effectively unused
- running workload baseline: three Benches and one MariaDB

The cluster has enough capacity for each acceptance scenario when they are run
sequentially with lightweight smoke resources. It does not have comfortable
request headroom for all Public, Private Shared, and Private temporary
topologies to coexist.

Required order:

1. Run the Public scenario and capture evidence.
2. Remove only its `run-*` temporary resources if new resources were created.
3. Run Private Shared and capture evidence.
4. Remove its temporary resources.
5. Run Private and capture evidence.
6. Remove its temporary resources.

Stop live apply if any of these occur:

- a node is not Ready or reports MemoryPressure, DiskPressure, or PIDPressure;
- worker requested CPU exceeds 85%;
- worker requested memory exceeds 80%;
- worker available memory falls below 2 GiB;
- worker free disk falls below 30 GiB;
- an acceptance pod remains Pending for more than five minutes;
- an operator, Traefik, MariaDB, or wildcard TLS health check fails.

## Preservation Boundary

Do not delete or replace resources in `default`, including:

- `MariaDB/frappe-mariadb`
- `FrappeBench/dev-bench`
- `FrappeBench/shared-db-bench-a`
- `FrappeBench/shared-db-bench-b`
- `FrappeSite/dev-site`
- `FrappeSite/shared-db-site-a`
- `FrappeSite/shared-db-site-b`
- `FrappeSite/wildcard-smoke`
- their Secrets, PVCs, Services, workloads, or routes

Acceptance resources must use names beginning with a unique `run-*` prefix and
must be created only in `lenscloud-runtime-eu`.

## Scoped Cleanup

Run cleanup from the manager only after setting the exact acceptance prefix:

```bash
export RUN_PREFIX=run-YYYYMMDD-HHMM
export RUN_NAMESPACE=lenscloud-runtime-eu

case "$RUN_PREFIX" in
  run-*) ;;
  *) echo "RUN_PREFIX must begin with run-" >&2; exit 1 ;;
esac

for resource in \
  frappesites.vyogo.tech \
  frappebenches.vyogo.tech \
  mariadbs.k8s.mariadb.com \
  jobs.batch \
  secrets \
  persistentvolumeclaims
do
  kubectl -n "$RUN_NAMESPACE" get "$resource" -o name |
    while IFS=/ read -r kind name; do
      case "$name" in
        "$RUN_PREFIX"|"$RUN_PREFIX"-*)
          kubectl -n "$RUN_NAMESPACE" delete "$kind/$name" --ignore-not-found
          ;;
      esac
    done
done
```

Verify that the prefix is gone and the preserved baseline is still Ready:

```bash
if kubectl -n lenscloud-runtime-eu get \
  mariadb,frappebench,frappesite,pvc,secret |
  grep -q "$RUN_PREFIX"
then
  echo "Run-prefixed resources remain." >&2
  exit 1
fi

kubectl -n default get mariadb,frappebench,frappesite,pvc
```
