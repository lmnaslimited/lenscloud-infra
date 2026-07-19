# Platform Handoff: `site_setup.complete` Runner Failure

Date: 2026-07-19
Source Platform-to-Infra handoff:
`docs/handoffs/infra/site-setup-complete-runner-failed-20260719.md`

## Status

Infra diagnosed and fixed the cluster admission contract. Platform can continue
testing after adapting `site_setup.complete` to the Release runtime image path.

Infra base revision during the fix:

```text
lenscloud-infra: d98dea3 plus working-tree changes live-applied
```

## Root Cause

`site_setup.complete` was incorrectly treated as a generic runner command.

That was safe for early setup-only Sites, but it is wrong once a Release Group
app such as `brandkit` is installed. Frappe setup completion can execute
installed-app setup wizard hooks, so it must run inside the same Release Group
runtime image as the target Bench.

The target Site has:

```text
frappe
erpnext
brandkit
```

The generic runner image does not carry the full Release Group app inventory.
Therefore `site_setup.complete` must be classified as app-aware.

The reported Platform payload is valid non-secret setup data. No setup payload
field change is required for this incident.

## Contract Change

Use these images:

```text
site_setup.status    -> synced generic runner digest
site_setup.complete  -> Release Group runtime image digest
```

Current generic runner digest for `site_setup.status`:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

Current Release runtime digest for this Bench:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
```

Platform-created `site_setup.complete` Jobs must:

- use `lenscloud.io/bench-command-family: site_setup`;
- use `lenscloud.io/bench-command: site_setup.complete`;
- use the digest-pinned Release Group runtime image;
- mirror the target Bench Sites PVC mount shape exactly;
- write a sanitized JSON result to `/dev/termination-log`;
- avoid secrets, pod logs, service-account tokens, privileged containers,
  `envFrom`, and mutable image tags.

## Admission Fix

Infra updated and live-applied:

```text
lenscloud-infra/manifests/access/lenscloud-platform-rbac.yaml
```

Admission now enforces:

```text
site_setup.status    generic runner digest admitted
site_setup.complete  Release runtime digest admitted
site_setup.complete  generic runner digest denied
```

Live verifier output:

```text
Bench Command Job/API RBAC verification passed.
Accepted Bench Command runner image for site_setup.status: admitted
Stale Bench Command runner image for site_setup.status: denied
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
```

## Live Site State

Infra reproduced setup completion natively on:

```text
Site: brandkite2e0717.cloud.lmnaslens.com
Bench: run-20260702-free-prod-bench
Namespace: lenscloud-runtime-eu
```

The Site now reports:

```text
frappe.is_setup_complete = true
```

Runtime-image idempotency probe succeeded:

```text
Job: site-setup-complete-runtime-20260719
Image: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
Pod exit code: 0
Termination summary:
{"phase":"Succeeded","command":"site_setup.complete","summary":"Runtime image setup completion probe succeeded","redacted":true,"details":{"setup_complete":true,"idempotent":true}}
```

## Sanitized Diagnostic

The native Frappe call emitted this safe ERPNext warning during the manual
diagnosis:

```text
Fiscal Year End Date should be one year after Fiscal Year Start Date
```

The native call still completed with:

```text
{"status": "ok"}
```

Treat this as an ERPNext setup wizard warning, not a Platform payload blocker.
The actual blocker was image selection.

## Platform Retest

For `brandkite2e0717.cloud.lmnaslens.com`, Platform should continue from the
current Site rather than creating a fresh replacement only for this incident:

1. Run `site_setup.status` using the synced generic runner digest.
2. Expect setup status to report complete.
3. Do not rerun `site_setup.complete` through the generic runner.
4. For future Sites, run `site_setup.complete` using the Release runtime digest.
5. Continue OAuth status/configure only after final setup status is complete.
6. Verify current HTML-generated CSS/JS routes return HTTP 200.

For a clean E2E, create a fresh disposable customer Site and verify this order:

```text
site_bootstrap.install_apps -> Release runtime digest
site_setup.status           -> generic runner digest
site_setup.complete         -> Release runtime digest
site_setup.status           -> generic runner digest
oauth.status/configure      -> generic runner digest
```

## Pods Log Boundary

Infra recommends keeping `pods/log` denied to Platform. Platform should
continue using sanitized termination summaries and action-log diagnostics.
Infra remains the pod-log inspection boundary for runner internals.
