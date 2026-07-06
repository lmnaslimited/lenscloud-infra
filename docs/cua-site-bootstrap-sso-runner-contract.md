# CUA Site Bootstrap And SSO Runner Contract

## Status

This contract is traceable through `docs/infra-workitems.md`:

- `INF-020` CUA native setup API readiness gate: Complete
- `INF-021` CUA setup wizard runner gate: Ready for Verification
- `INF-022` CUA OAuth runner gate: Blocked
- `INF-023` CUA user/access runner gate: Blocked
- `INF-024` CUA end-to-end runner handoff: Blocked

Source handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-site-bootstrap-sso-runner-20260703.md
```

No CUA runner code, RBAC, image build, or cluster mutation is authorized by
this document. It defines the implementation boundary and the next proof gates.

The setup wizard path does not require a custom LensCloud branding/bootstrap
app. Frappe v16 provides the first-class setup API required for the setup
commands.

## Objective

LensCloud Platform needs Central User Access (CUA) to make a newly provisioned
Frappe Site usable without sharing Site Administrator credentials. The target
experience is:

1. Customer signs in to LensCloud Platform.
2. Customer creates or opens a Site.
3. Platform confirms setup, OAuth, and user access state.
4. Customer opens the Site through Platform-backed access.

Infra will support this through the existing Bench Command Job/API pattern.
Platform will not call target Site HTTP APIs with Administrator credentials.

## Ownership Boundary

### Platform Owns

- Customer, Subscription, Landscape, Environment, and Site policy resolution.
- Site Bootstrap State and Site Access Grant records.
- Setup input resolution and validation.
- OAuth settings and customer-facing access policy.
- Deciding which CUA command is allowed.
- Creating labelled Bench Command request ConfigMaps and Jobs through the
  restricted Kubernetes API.
- Orchestration Action Logs, UI progress, retry, and Platform evidence.
- Customer-facing `Open Site` behavior.

### Infra Owns

- Runner image source, build, publication, and digest pinning.
- Runner command allowlist and typed validation.
- RBAC and admission guardrails.
- Safe Bench/Site execution mechanics inside approved Runtime Namespaces.
- Secret-safe status/result summaries.
- Live verification, negative security proof, cleanup, and Platform handoff.

### Target Site Image Owns

The target Bench image must include Frappe v16 or a compatible Frappe version
that exposes the native setup wizard API:

```text
frappe.is_setup_complete
frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps
frappe.desk.page.setup_wizard.setup_wizard.setup_complete
```

No additional LensCloud branding/bootstrap app is required for setup wizard
status or completion.

OAuth and user/access work should use standard Frappe APIs or bench-executed
standard Frappe methods first. Add a branding app expansion only if standard
APIs prove insufficient during `INF-022` or `INF-023`.

## Native Frappe Setup API Contract

### `site_setup.status`

Purpose:

- Return whether the target Site setup wizard is complete.
- Return safe next-action information for Platform.

Implementation source:

```text
frappe.is_setup_complete()
frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps()
```

Expected sanitized result fields:

```json
{
  "setup_complete": false,
  "setup_required": true,
  "pending_apps": ["frappe", "erpnext"],
  "message": "Setup wizard is pending",
  "warnings": [],
  "version": "1"
}
```

### `site_setup.complete`

Purpose:

- Complete the setup wizard using Platform-resolved setup inputs.
- Be idempotent when setup is already complete.

Implementation source:

```text
frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
```

Expected sanitized result fields:

```json
{
  "setup_complete": true,
  "changed": true,
  "message": "Setup wizard completed",
  "warnings": [],
  "version": "1"
}
```

The native method returns `{"status": "ok"}` when the Site is already setup. If
`trigger_site_setup_in_background` is enabled it may return
`{"status": "registered"}`; the runner must then poll `site_setup.status` until
completion or timeout.

The runner must not return Administrator passwords, user passwords, OAuth client
secrets, raw setup documents, raw site config, DB passwords, tokens, private
keys, tracebacks, pod logs, or full environment dumps.

## Command Gate Matrix

| Infra ID | Command family | Commands | Current status | Unblock condition |
| --- | --- | --- | --- | --- |
| `INF-020` | native setup API readiness | Frappe API contract review | Complete | Frappe v16 provides status and setup completion APIs |
| `INF-021` | `site_setup` | `site_setup.status`, `site_setup.complete` | Ready for Verification | Runner source implemented; needs image publish, digest pin, and live proof on a real Site |
| `INF-022` | `oauth` | `oauth.status`, `oauth.configure` | Blocked | `INF-021` complete; standard Frappe API path chosen or branded method gap documented |
| `INF-023` | `user`, `site_access` | `user.ensure`, `user.disable`, `user.roles.set`, `site_access.status` | Blocked | `INF-021` complete; standard Frappe API path chosen or branded method gap documented |
| `INF-024` | CUA E2E | full setup, OAuth, user/access sequence | Blocked | `INF-020` through `INF-023` complete with evidence |

Until a gate is complete, the runner must return `Unsupported` with
`COMMAND_UNSUPPORTED` for the associated commands.

## Request Shape

CUA commands extend the existing Bench Command request stored in
`request.json`. Requests must remain non-secret.

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260706-0001",
  "command": "site_setup.status",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "context": {
    "customer": "CUST-0001",
    "subscription": "SUB-0001",
    "site": "SITE-0001",
    "correlationId": "ORCH-20260706-0001"
  },
  "args": {},
  "timeoutSeconds": 300,
  "requestedBy": "Administrator"
}
```

`site_setup.complete` args may include only non-secret setup data, such as:

- company name;
- country;
- timezone;
- language;
- currency;
- fiscal year;
- first user email/name;
- role mapping.

OAuth args for future `INF-022` work may include issuer URL, client ID,
redirect URI, allowed scopes, provider label, and server-side secret reference
name if the final runner contract permits it. OAuth client secret values must
never be placed in ConfigMaps, action logs, evidence, or browser responses.

## Result Shape

The runner must write only sanitized summaries to the termination message.

```json
{
  "phase": "Succeeded",
  "code": "OK",
  "commandId": "BCMD-20260706-0001",
  "command": "site_setup.status",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "summary": "Setup wizard is pending",
  "customerSummary": "Your site setup is pending",
  "setup_complete": false,
  "retryable": true,
  "nextAction": "site_setup.complete",
  "redacted": true
}
```

Forbidden result content:

- kubeconfig contents or tokens;
- Kubernetes Secret values;
- Administrator password;
- user password;
- OAuth client secret;
- DB password;
- private keys;
- raw pod logs;
- raw setup documents;
- raw `site_config.json`;
- full environment dumps.

## Admin Password Boundary

Administrator password must not be a Platform input. If setup requires privileged
execution, the runner must use bench-executed methods or an Infra/operator-owned
secret reference that is never exposed to Platform users, action logs, request
ConfigMaps, or evidence.

## Verification Requirements

`INF-020` proved:

- the native Frappe setup method exists;
- setup completion is idempotent when the Site is already complete;
- setup status can be derived without custom app code;
- no special branding/bootstrap image is required for setup wizard completion.

`INF-021` must prove on one real Platform-managed Bench/Site:

- `site_setup.status` before completion;
- `site_setup.complete`;
- `site_setup.status` after completion;
- idempotent second completion;
- unsafe request rejection;
- no credential leakage;
- cleanup of request ConfigMap, Job, and terminal Pod.

`INF-022` and `INF-023` must stay blocked until `INF-021` is complete.

## Remaining Future DNS/SSO Scope

This contract does not add DNS automation. Standard customer Sites remain under
the wildcard edge contract for `*.cloud.lmnaslens.com`.

Customer-owned custom domains, per-customer certificate flows, and multi-region
origin routing remain future architecture items outside this CUA runner gate.
