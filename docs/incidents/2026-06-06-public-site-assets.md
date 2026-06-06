# Public Site HTTP 500 Incident

## Scope

- Date: June 6, 2026
- Run prefix: `run-20260606-0811`
- Namespace: `lenscloud-runtime-eu`
- Image: `ghcr.io/lmnaslimited/lensdocker/lenscx:v15.91.2`
- Affected Sites:
  - `run-20260606-0811-platform.cloud.lmnaslens.com`
  - `run-20260606-0811-customer.cloud.lmnaslens.com`

## Observed State

- Both FrappeBench resources reported `Ready`.
- Both FrappeSite resources reported `Ready` at observed generation 3.
- Site database creation and initialization succeeded.
- Site configuration contained the expected hostname, MariaDB service, logical
  database, Redis services, and redacted credential fields.
- Ingress rules and endpoints correctly routed each hostname to its Bench nginx
  service.
- Both public HTTPS routes returned HTTP 500.

No credential or Secret value was read or recorded.

## Root Cause

The custom image does not implement the Frappe Operator image asset contract.

The operator Bench initialization script copies prebuilt assets from:

```text
/home/frappe/assets_cache
```

The reference image `ghcr.io/vyogotech/frappe_base:latest` contains that
directory. Its initialization log includes `Syncing pre-built assets from
image to PVC`, and its resulting shared `sites/assets` volume contains
`assets.json`, `assets-rtl.json`, CSS, JavaScript, locale files, and app public
links.

The custom `lenscx:v15.91.2` image does not contain
`/home/frappe/assets_cache`. The operator initialization script treats the
directory as optional, silently skips asset synchronization, and exits
successfully. Both affected PVCs therefore had empty `sites/assets`
directories.

Gunicorn failed while rendering the first page:

```text
AttributeError: 'NoneType' object has no attribute 'get'
```

The failure occurred when Frappe attempted to resolve
`website.bundle.css` from the missing bundled asset manifest.

Database connectivity was functional. Ingress, nginx, Host routing, and
MariaDB placement were not the root cause.

## Status Semantics Gap

The operator currently marks:

- FrappeBench Ready after the initialization Job exits successfully and the
  component workloads are available;
- FrappeSite Ready after database/site initialization succeeds.

It does not verify that:

- `/home/frappe/assets_cache/assets.json` exists in the image;
- the shared `sites/assets/assets.json` exists and contains a mapping;
- the Site returns a successful HTTP response.

This permits operator Ready while the application returns HTTP 500.

## Required Corrections

### Release Image

Rebuild every operator-compatible release image so the final runtime stage
contains the output of `bench build` at:

```dockerfile
COPY --from=builder --chown=1000:0 \
  /home/frappe/frappe-bench/sites/assets \
  /home/frappe/assets_cache
```

The image validation gate must check at least:

- `/home/frappe/assets_cache/assets.json` exists;
- the JSON root is an object and is not empty;
- `assets-rtl.json` exists when produced by the target Frappe version;
- required app public assets and links are included;
- the image starts with the expected Frappe major version.

### Frappe Operator

Bench initialization should fail when the asset cache is missing or invalid.
It must not use an optional directory check or ignore copy failures for a
runtime image that requires shared assets.

Ready should require successful asset validation. Site Ready should eventually
include a configurable application health check, or expose a separate
`ApplicationReady` condition distinct from database initialization.

The repeated `frappe-operator-config` ConfigMap lookup errors should also be
resolved or downgraded when that ConfigMap is intentionally optional.

Site deletion must quiesce the Bench workloads before running `bench
drop-site`. During this incident, both deletion Jobs remained blocked while
gunicorn and scheduler processes held database connections. Scaling only the
incident Bench deployments to zero allowed both deletion Jobs and the normal
operator finalizers to complete. Cleanup did not require removing finalizers.

### LensCloud Platform

Release promotion must include an operator-image compatibility check before a
Release becomes deployable. At minimum, it should run an image validation Job
that verifies the asset cache contract.

LensCloud must continue to treat route HTTP 500 as failed application
readiness, even when the operator CR reports Ready. A successful Kubernetes
apply or Ready CR is not sufficient evidence of a usable Site.

The Release Group app metadata must also be complete so `spec.apps` reflects
the intended image applications. This was not the cause of this HTTP 500, but
an empty app declaration can produce an incomplete Site installation.

## Preservation And Cleanup

All resources in `default`, including `frappe-mariadb` and the pre-existing
Bench/Site baseline, are outside this incident cleanup boundary.

Only resources named `run-20260606-0811` or beginning with
`run-20260606-0811-` in `lenscloud-runtime-eu` may be deleted.

## Cleanup Result

Completed on June 6, 2026:

- both operator Site deletion Jobs completed successfully;
- both logical Site databases were removed;
- both FrappeSite and FrappeBench resources were deleted through their normal
  finalizers;
- remaining run-prefixed Secrets and PVCs were deleted;
- no resource with the incident prefix remains in `lenscloud-runtime-eu`;
- `default/frappe-mariadb` and all pre-existing Benches, Sites, PVCs,
  workloads, and routes remain healthy;
- Headlamp and all preserved wildcard HTTPS smoke routes return HTTP 200;
- the restricted positive and negative permission preflight passes.

The worker returned to the normal baseline with approximately 5.4 GiB
available memory and 56 GiB free local disk. Infrastructure capacity is
available for the remaining scenarios sequentially.

Live Site acceptance remains blocked, however, until an operator-compatible
release image with a valid `/home/frappe/assets_cache` is published and selected
by LensCloud. Reusing `lenscx:v15.91.2` would reproduce the HTTP 500 regardless
of Public, Private Shared, or Private database placement.
