# CUA OAuth Configure Runner Failure Evidence - 2026-07-07

## Infra Workitem

`INF-025` CUA OAuth configure runner failure follow-up.

## Source

Platform handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-oauth-configure-runner-failed-20260707.md
```

Platform commit verified:

```text
f8bfdbd
```

## Target

```text
namespace: lenscloud-runtime-eu
bench: run-20260702-free-prod-bench
site: run-20260706-cua-134515.cloud.lmnaslens.com
frappesite: run-20260706-cua-134515
```

## Platform Observation

Platform successfully ran `oauth.status`, then `oauth.configure` reached the
runner and failed with:

```text
phase: Failed
code: RUNNER_FAILED
summary: oauth command failed with sanitized error
```

Platform cleanup removed Job, ConfigMap, terminal Pod, and short-lived OAuth
Secret.

## Infra Diagnosis

The Platform request shape was correct:

- non-secret OAuth fields in ConfigMap;
- `client_secret_source=mounted_file`;
- one short-lived Secret volume named `oauth-client-secret`;
- mounted read-only at `/lenscloud/secrets`;
- runner image digest `sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741`.

Non-secret Site key-shape check:

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

Direct non-secret Frappe diagnostic reproduced the underlying error:

```text
ValidationError Encryption key is in invalid format!
```

Encrypted row count check:

```text
auth_row_groups: 1
auth_group User password 1
```

## Root Cause

The kept CUA Site has an invalid Frappe `encryption_key` shape in
`site_config.json`. `oauth.configure` writes `Social Login Key.client_secret`,
which is a Frappe Password field. Frappe refuses to save that Password field
when the Site encryption key is invalid.

This is not an admission issue, not an OAuth request-shape issue, and not a
missing Secret mount.

## Safety Decision

Infra did not rotate or repair the kept Site encryption key because the Site
already has at least one encrypted `User.password` row. Rotating the key without
an explicit operator decision can break decryption of existing Password fields.

Infra created only the expected bench-local log directory needed for non-secret
diagnostics:

```text
/home/frappe/frappe-bench/run-20260706-cua-134515.cloud.lmnaslens.com/logs
```

No OAuth client secret, Kubernetes Secret value, kubeconfig, token, private key,
or password value was printed.

## Platform Action

Platform should not change the OAuth request shape.

Platform may retry `configure_site_oauth` unchanged only after the kept Site is
repaired or recreated with a valid Frappe encryption key.

Recommended options:

1. For this throwaway kept CUA Site, explicitly approve Infra/operator repair
   of the Site encryption key, accepting that existing encrypted Password rows
   may be invalidated.
2. Preferably recreate a fresh CUA test Site whose `encryption_key` is generated
   correctly before setup/OAuth.
3. Add a Platform preflight before OAuth configure that checks non-secret key
   shape or treats `INVALID_SITE_ENCRYPTION_KEY`/`RUNNER_FAILED` as a Site
   repair/recreate condition.

## Contract Status

`INF-022` remains Complete. OAuth runner live verification already passed on a
Site with a valid encryption key.

`INF-025` closes as diagnosis complete with no Platform request-shape change.
