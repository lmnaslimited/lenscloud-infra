# Platform Handoff - CUA OAuth Configure Failure Follow-Up - 2026-07-07

## Infra Workitem

`INF-025` CUA OAuth configure runner failure follow-up.

## Status

Complete as diagnosis and handoff.

This does not reopen `INF-022`. The OAuth runner remains live-verified and
usable. The failed Platform run was caused by invalid target Site state.

## Source

Platform handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-oauth-configure-runner-failed-20260707.md
```

Platform commit verified:

```text
f8bfdbd
```

Infra evidence:

```text
lenscloud-infra/docs/evidence/cua/oauth-configure-runner-failed-20260707.md
```

## Target Checked

```text
namespace: lenscloud-runtime-eu
bench: run-20260702-free-prod-bench
site: run-20260706-cua-134515.cloud.lmnaslens.com
frappesite: run-20260706-cua-134515
```

## Root Cause

The kept CUA Site has an invalid Frappe `encryption_key` shape in
`site_config.json`.

Non-secret key-shape evidence:

```text
has_encryption_key: true
encryption_key_length: 48
base64_decoded_length: 36
```

Expected Frappe/Fernet key shape:

```text
encryption_key_length: 44
base64_decoded_length: 32
```

`oauth.configure` writes `Social Login Key.client_secret`, which is a Frappe
Password field. Frappe rejects the write when the Site encryption key is
invalid.

Sanitized direct diagnostic:

```text
ValidationError Encryption key is in invalid format!
```

This is not a Platform request-shape issue, not a missing Secret mount, and not
an admission/RBAC issue.

## Platform Request Shape

No Platform request-shape change is required.

The observed Platform request was correct:

- OAuth fields in ConfigMap were non-secret;
- `client_secret_source` was `mounted_file`;
- the short-lived Secret was mounted read-only at `/lenscloud/secrets`;
- `LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH` pointed to the mounted file;
- the pinned runner image digest was used;
- Platform cleanup removed Job, ConfigMap, terminal Pod, and short-lived OAuth
  Secret.

## Kept Site Safety

Infra did not rotate or repair the kept Site encryption key.

The Site has at least one encrypted `User.password` row:

```text
auth_row_groups: 1
auth_group User password 1
```

Changing the Site encryption key without an explicit operator decision can break
decryption of existing Password fields.

## Platform Action

Platform should retry `configure_site_oauth` unchanged only after one of these
actions is complete:

1. Recreate the CUA test Site with a valid generated `encryption_key`.
2. Explicitly approve Infra/operator repair of the kept throwaway Site, accepting
   that existing encrypted Password rows may need reset.

Platform should add or keep a preflight that treats invalid target Site
encryption-key shape as a Site repair/recreate condition before running
`oauth.configure`.

## Current Platform Go/No-Go

- Go: OAuth runner contract remains valid.
- Go: Platform may retry unchanged on a healthy Site.
- No-Go: Do not keep retrying `oauth.configure` against
  `run-20260706-cua-134515.cloud.lmnaslens.com` until that Site is repaired or
  recreated.

## Secrets

No OAuth client secret, Kubernetes Secret value, kubeconfig, token, private key,
or password value was exposed in evidence.
