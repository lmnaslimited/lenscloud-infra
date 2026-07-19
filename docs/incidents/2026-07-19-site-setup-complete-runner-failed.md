# Site Setup Complete Runner Failed

Date: 2026-07-19
Reported by: Platform
Source handoff:
`lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/site-setup-complete-runner-failed-20260719.md`

## Status

Resolved at infra/admission contract level; Platform adaptation/retest pending.

## Incident

Platform retried customer setup for:

```text
Site: brandkite2e0717.cloud.lmnaslens.com
Bench: run-20260702-free-prod-bench
Namespace: lenscloud-runtime-eu
Cluster: lenscloud-eu-dev
Action Log: ORCH-2026-00568
Command: site_setup.complete
```

The Job was admitted and started with the synced generic runner digest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

The runner failed with only the generic sanitized summary:

```text
phase: Failed
code: RUNNER_FAILED
summary: site setup command failed with sanitized error
```

## Root Cause

`site_setup.complete` was incorrectly classified as a generic runner command.
It is app-aware once Release Group apps are installed because Frappe setup
completion can execute installed-app setup wizard hooks.

The synced generic runner image contains the generic runner app inventory, not
the active Release Group app inventory. The live inspection showed the generic
runner image had `frappe` and `erpnext`, while the target Site had
`brandkit` installed:

```text
frappe
erpnext
```

Target Site app inventory:

```text
frappe
erpnext
brandkit
```

Therefore `site_setup.complete` must run in the digest-pinned Release Group
runtime image for the target Bench.

The Platform payload was valid non-secret setup data. No Platform setup field
change is required for this incident.

## Live Recovery

Infra reproduced the native setup completion path on the target Site with the
reported non-secret payload. Frappe returned setup complete:

```text
frappe.is_setup_complete = true
```

The native setup call printed a safe ERPNext fiscal-year warning:

```text
Fiscal Year End Date should be one year after Fiscal Year Start Date
```

but completed with:

```text
{"status": "ok"}
```

This warning is not a Platform payload blocker.

## Infra Fix

Infra changed admission so:

- `site_setup.status` remains a generic runner command;
- `site_setup.complete` must use
  `ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<release-digest>`;
- generic runner image is denied for `site_setup.complete`.

Live verifier result:

```text
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
```

Runtime-image idempotency probe against the target Site succeeded:

```text
Job: site-setup-complete-runtime-20260719
Image: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
Exit code: 0
Termination summary: Runtime image setup completion probe succeeded
setup_complete: true
idempotent: true
```

## Follow-Up

Platform must update action image selection:

```text
site_setup.status    -> generic runner digest from Cluster contract
site_setup.complete  -> Release Group runtime image digest
```

Infra remains the pod-log inspection boundary. Platform should continue to
consume sanitized termination summaries and Kubernetes admission messages; do
not grant general `pods/log` read for Bench Command Pods.
