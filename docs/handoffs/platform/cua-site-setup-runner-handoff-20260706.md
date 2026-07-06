# Platform Handoff - CUA Site Setup Runner - 2026-07-06

## Infra Workitem

`INF-021` CUA setup wizard runner gate.

## Status

Complete. Source implemented, runner image published, admission pin applied,
and live verification passed against a real Platform-managed Bench/Site.

Platform may integrate `site_setup.status` and `site_setup.complete` through
the existing Bench Command Job/API path.

Published runner:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:2905fb71dfb449258214a7b76016a67d9b98bd66ea378394f98d791ab293dad5
```

## Implemented Runner Commands

- `site_setup.status`
- `site_setup.complete`

These commands use native Frappe setup wizard APIs:

```text
frappe.is_setup_complete()
frappe.client_cache.get_doc("Installed Applications")
frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
```

No LensCloud branding/bootstrap app is required for setup wizard completion.

## Request Examples

### `site_setup.status`

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260706-STATUS",
  "command": "site_setup.status",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "args": {},
  "timeoutSeconds": 300,
  "requestedBy": "LensCloud Platform"
}
```

### `site_setup.complete`

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260706-COMPLETE",
  "command": "site_setup.complete",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "args": {
    "language": "English",
    "email": "first.user@example.com",
    "full_name": "First User",
    "country": "United States",
    "timezone": "America/New_York",
    "currency": "USD"
  },
  "timeoutSeconds": 300,
  "requestedBy": "LensCloud Platform"
}
```

Do not include Administrator passwords, user passwords, OAuth client secrets, DB
passwords, tokens, private keys, or raw setup documents in request args.

## Response Examples

### Pending Status

```json
{
  "phase": "Succeeded",
  "command": "site_setup.status",
  "summary": "Setup wizard is pending",
  "changed": false,
  "details": {
    "setup_complete": false,
    "setup_required": true,
    "pending_apps": ["frappe"]
  },
  "display": {
    "label": "Setup wizard",
    "value": "Pending",
    "kind": "setup-status",
    "safe": true
  },
  "redacted": true
}
```

### Completed

```json
{
  "phase": "Succeeded",
  "command": "site_setup.complete",
  "summary": "Setup wizard completed",
  "changed": true,
  "details": {
    "setup_complete": true,
    "setup_required": false,
    "pending_apps": [],
    "idempotent": false
  },
  "display": {
    "label": "Setup wizard",
    "value": "Complete",
    "kind": "setup-status",
    "safe": true
  },
  "redacted": true
}
```

## Platform Expectations

Platform should:

- keep OAuth, user, and site access commands marked `Unsupported`;
- create request ConfigMaps and Jobs through the existing Python Kubernetes API
  Bench Command path;
- mount the target Bench sites PVC at `/home/frappe/frappe-bench/sites`;
- use read-only mount for `site_setup.status`;
- use read-write mount for `site_setup.complete`;
- parse only sanitized termination summaries;
- render `display.value` only when `display.safe=true`;
- log command phase, code, summary, details, and cleanup state in Orchestration
  Action Log;
- clean up terminal request ConfigMaps, Jobs, and terminal Bench Command Pods
  after evidence capture.

Platform must not:

- use kubectl;
- call the target Site HTTP API with Administrator credentials;
- create invented `FrappeSite` CRD fields;
- expose kubeconfig contents, tokens, Secret values, passwords, OAuth secrets,
  DB passwords, private keys, pod logs, raw setup input dumps, raw
  `site_config.json`, or full environment dumps.

## Infra Evidence

Local evidence:

```text
lenscloud-infra/docs/evidence/cua/site-setup-runner-evidence-20260706.md
```

Live verification script:

```text
lenscloud-infra/scripts/64-verify-cua-site-setup-runner.sh
```

Live verification passed:

```text
Manager revision: 6869dd2
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: run-20260702-free-site.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
Positive commands: site_setup.status, site_setup.complete
Negative command: site_setup.complete with sensitive key rejected
Temporary prefix: run-20260706-cua-existing
Cleanup proof: no resources found with that prefix
```

## Remaining Infra Gaps

- OAuth commands remain `Unsupported` until `INF-022`.
- User and site access commands remain `Unsupported` until `INF-023`.
