# Platform Handoff - CUA Site Setup Runner - 2026-07-06

## Infra Workitem

`INF-021` CUA setup wizard runner gate.

## Status

Source implemented and ready for image publication/live verification.

Platform must not enable customer-facing `site_setup` workflows until Infra
publishes the new runner image, pins the digest in admission, runs live
verification, and updates this handoff with final evidence.

## Implemented Runner Commands

- `site_setup.status`
- `site_setup.complete`

These commands use native Frappe setup wizard APIs:

```text
frappe.is_setup_complete()
frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps()
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

- keep `site_setup` disabled until Infra returns live verification evidence;
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

Live evidence remains pending until the new runner image is published and
admission-pinned.

## Remaining Infra Gaps

- Publish the new runner image.
- Pin the new runner digest in admission.
- Apply admission/RBAC changes to the target cluster.
- Run live verification against a real Platform-managed Bench/Site.
- Update this handoff and `docs/infra-workitems.md` after live proof.
