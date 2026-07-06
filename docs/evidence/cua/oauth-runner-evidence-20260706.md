# CUA OAuth Runner Evidence - 2026-07-06

## Infra Workitem

`INF-022` CUA OAuth runner gate.

## Status

Ready for live verification.

Runner source, admission contract, local verification, and Platform handoff are
updated. The runner image has been built and published, and the repo admission
manifest has been pinned to the published digest. The admission update must
still be applied to the cluster and live-verified with
`scripts/65-verify-cua-oauth-runner.sh` before Platform enables OAuth commands.

Published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.9
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

Build output confirmed the local image architecture as:

```text
linux/amd64
```

Remote digest verification:

```bash
docker buildx imagetools inspect ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.9
```

Summary:

```text
Digest: sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

## Implemented Source

- `bench-command-runner/runner.py`
- `scripts/59-test-bench-command-runner-local.sh`
- `scripts/65-verify-cua-oauth-runner.sh`
- `manifests/access/lenscloud-platform-rbac.yaml`

## Supported Commands

| Command | Status | Notes |
| --- | --- | --- |
| `oauth.status` | Source/local verified | Reads target Site `Social Login Key` state and returns only sanitized fields |
| `oauth.configure` | Source/local verified | Creates or updates target Site `Social Login Key`; OAuth client secret must arrive only through mounted file |

## Ownership Boundary Verified In Source

Platform owns the Platform-side `OAuth Client`.

Infra runner owns only the target Site `Social Login Key` setup:

- `provider`
- `provider_name`
- `social_login_provider`
- `enable_social_login`
- `client_id`
- `base_url`
- `authorize_url`
- `access_token_url`
- `redirect_url`
- `api_endpoint`
- `custom_base_url`
- `auth_url_data`
- `sign_ups`

The target `Social Login Key.client_secret` is required by Frappe but must not
be placed in the request ConfigMap. It must be mounted as:

```text
/lenscloud/secrets/client_secret
```

## Local Verification

Command:

```bash
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
Bench command runner local verification passed.
```

Covered OAuth checks:

- `oauth.status` reports missing provider before configuration.
- `oauth.configure` succeeds with non-secret args and mounted secret file.
- `oauth.status` reports enabled provider after configuration.
- `oauth.configure` rejects direct `client_secret` args.
- Termination summaries do not include the fake OAuth secret value.

Additional parser checks:

```bash
python3 -m py_compile bench-command-runner/runner.py
bash -n scripts/65-verify-cua-oauth-runner.sh
```

Both passed locally.

## Admission Contract Change

The admission family allowlist now includes:

```text
oauth
```

Secret-volume rule:

- all non-OAuth families remain denied from mounting Secrets;
- OAuth Jobs may mount exactly one Secret volume named `oauth-client-secret`;
- that Secret may expose only the key `client_secret`;
- the mount must be read-only at `/lenscloud/secrets`.

## Live Verification Required

After applying the updated admission manifest, run from the Infra/admin path:

```bash
kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml

RUNNER_IMAGE=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580 \
REAL_BENCH=<platform-managed-bench> \
REAL_SITE=<platform-managed-site> \
REAL_SITES_PVC=<bench-sites-pvc> \
scripts/65-verify-cua-oauth-runner.sh
```

The verifier must prove:

- `oauth.status` succeeds before configuration.
- `oauth.configure` succeeds with a mounted Secret file.
- `oauth.status` succeeds after configuration and reports enabled social login.
- direct `client_secret` args are rejected.
- non-OAuth Secret-volume Jobs are denied.
- temporary Jobs, ConfigMaps, and the verifier Secret are cleaned.

## Secret Redaction Proof

Local verifier uses a fake OAuth secret and fails if the value appears in the
termination summary. The runner also rejects a request containing
`client_secret` directly in args.

Evidence intentionally does not include kubeconfig contents, tokens, Secret
values, OAuth client secrets, DB passwords, private keys, pod logs, raw Site
config, or full environment dumps.

## Remaining Gaps

- Live cluster admission has not been applied in this pass.
- `scripts/65-verify-cua-oauth-runner.sh` has not been run against the live
  runtime Site in this pass.
- `INF-023` user/access commands remain blocked until OAuth live verification
  is complete.
