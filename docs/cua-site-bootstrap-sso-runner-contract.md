# CUA Site Bootstrap And SSO Runner Contract

## Status

This contract is traceable through `docs/infra-workitems.md`:

- `INF-020` CUA image readiness gate: Planned
- `INF-021` CUA setup wizard runner gate: Blocked
- `INF-022` CUA OAuth runner gate: Blocked
- `INF-023` CUA user/access runner gate: Blocked
- `INF-024` CUA end-to-end runner handoff: Blocked

Source handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-site-bootstrap-sso-runner-20260703.md
```

No CUA runner code, RBAC, image build, or cluster mutation is authorized by
this document. It defines the implementation boundary and the next proof gates.

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

### Branding App Owns

For v1, the branding/bootstrap app should own only the setup wizard helper
methods that are difficult to perform safely through standard Frappe APIs.

OAuth and user/access work should use standard Frappe APIs or bench-executed
standard Frappe methods first. Add branding app expansion for OAuth/user only
if standard APIs prove insufficient during `INF-022` or `INF-023`.

## Minimum Branding App Method Contract

The new LensPure image must include a branding/bootstrap app that exposes these
bench-executable methods:

```text
lenscloud_branding.bootstrap.status
lenscloud_branding.bootstrap.complete_setup
```

The final method names may change only if `INF-020` records the replacement
contract before implementation.

### `lenscloud_branding.bootstrap.status`

Purpose:

- Return whether the target Site setup wizard is complete.
- Return safe next-action information for Platform.

Expected sanitized result fields:

```json
{
  "setup_complete": false,
  "setup_required": true,
  "message": "Setup wizard is pending",
  "warnings": [],
  "version": "1"
}
```

### `lenscloud_branding.bootstrap.complete_setup`

Purpose:

- Complete the setup wizard using Platform-resolved setup inputs.
- Be idempotent when setup is already complete.

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

The method must not return Administrator passwords, user passwords, OAuth client
secrets, raw setup documents, raw site config, DB passwords, tokens, private
keys, or full environment dumps.

## Command Gate Matrix

| Infra ID | Command family | Commands | Current status | Unblock condition |
| --- | --- | --- | --- | --- |
| `INF-020` | image readiness | image/tag/digest and method check | Planned | New LensPure image includes branding/bootstrap app and setup methods |
| `INF-021` | `site_setup` | `site_setup.status`, `site_setup.complete` | Blocked | `INF-020` complete, runner implemented, live proof on a real Site |
| `INF-022` | `oauth` | `oauth.status`, `oauth.configure` | Blocked | `INF-020` and `INF-021` complete; standard Frappe API path chosen or branded method gap documented |
| `INF-023` | `user`, `site_access` | `user.ensure`, `user.disable`, `user.roles.set`, `site_access.status` | Blocked | `INF-020` and `INF-021` complete; standard Frappe API path chosen or branded method gap documented |
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

`INF-020` must prove:

- image tag and digest;
- branding/bootstrap app installed in the image;
- setup methods exist by using a non-secret bench execution check.

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
