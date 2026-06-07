# Platform Live Orchestration Readiness

## Audit

Updated on June 7, 2026.

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
- The completed Public acceptance resources under
  `run-20260607-0623` may still be present pending exact-prefix cleanup.

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
- controlled runtime namespace: Public acceptance resources pending cleanup
- preserved database baseline: one MariaDB in `default`

The cluster has enough capacity for each acceptance scenario when they are run
sequentially with lightweight smoke resources. It does not have comfortable
request headroom for all Public, Private Shared, and Private temporary
topologies to coexist.

The corrected image passed the release-image compatibility gate:

- `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.1`
- digest:
  `sha256:86dd9bec4ef7ef255bff6596b15480e88b3fb27751e1c88b22167ff69fb4a2a2`
- Frappe `16.14.0`, ERPNext `16.13.1`
- Bench/Site Ready, HTTPS login 200, generated CSS 200, Administrator login
  passed

The asset incident is closed. See
[incidents/2026-06-06-public-site-assets.md](./incidents/2026-06-06-public-site-assets.md).

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

## Cleanup Boundary

Preserve:

- `MariaDB/default/frappe-mariadb`;
- operators, Traefik, wildcard TLS, Certbot, Headlamp, namespaces, RBAC, and
  cluster infrastructure;
- Kubernetes Secrets that are not owned by a Bench/Site being removed.

The one-time Public acceptance cleanup uses manager credentials because those
resources predate the ownership-label admission contract. After Platform adds
the required labels and lifecycle APIs, routine cleanup must use the restricted
Platform identity and must not require manager access.

New acceptance resources must use a unique `run-*` prefix in
`lenscloud-runtime-eu`.

## Scoped Cleanup

Run the guarded helper from the manager only after setting the exact acceptance
prefix:

```bash
RUN_PREFIX=run-20260607-0623 ./scripts/56-cleanup-platform-run.sh
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
