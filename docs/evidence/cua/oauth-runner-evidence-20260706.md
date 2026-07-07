# CUA OAuth Runner Evidence - 2026-07-06

## Infra Workitem

`INF-022` CUA OAuth runner gate.

## Status

Complete.

Runner source, admission contract, local verification, and Platform handoff are
updated. The runner image has been built and published, the admission manifest
has been pinned to the published digest, the admission update has been applied
to the EU cluster, and `scripts/65-verify-cua-oauth-runner.sh` passed live on
2026-07-07. Platform may adapt OAuth through the Bench Command path.

Published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.10
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741
```

Build output confirmed the local image architecture as:

```text
linux/amd64
```

Remote digest verification:

```bash
docker buildx imagetools inspect ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.10
```

Summary:

```text
Digest: sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741
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

RUNNER_IMAGE=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741 \
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

## Live Verification Result

Applied admission on the manager from `/root/lenscloud-infra`:

```bash
kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml
```

Live verifier:

```bash
RUNNER_IMAGE=ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:e003d3f49a1225ccc37df1147bc7f2d1ca704518b90575fc5ad4c4af4ffc7741 \
REAL_BENCH=run-20260702-free-prod-bench \
REAL_SITE=run-20260702-free-site.cloud.lmnaslens.com \
REAL_SITES_PVC=run-20260702-free-prod-bench-sites \
TEST_PREFIX=run-20260707-cua-oauth \
PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
./scripts/65-verify-cua-oauth-runner.sh
```

Result summary:

```text
CUA OAuth runner verification passed.
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: run-20260702-free-site.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
Positive commands: oauth.status, oauth.configure
Negative checks: direct client_secret arg rejected; non-oauth Secret volume denied
Temporary resource prefix: run-20260707-cua-oauth
```

Cleanup proof:

```text
No Jobs, ConfigMaps, Secrets, or Pods remained with prefixes:
- run-20260707-cua-oauth
- run-20260707-cua-oauth-debug
- run-20260707-cua-oauth-rootcause
```

The verifier-created target Site `Social Login Key` provider
`lenscloud_oauth_smoke` was removed after evidence capture.

Preserved runtime resources:

```text
FrappeBench/run-20260702-free-prod-bench: Ready
FrappeSite/run-20260702-free-site: Ready
PVC/run-20260702-free-prod-bench-sites: Bound
```

RBAC recheck:

```text
Restricted LensCloud Platform RBAC verification passed for lenscloud-runtime-eu.
```

Root-cause note from the first failed attempt:

`oauth.configure` writes a Frappe Password field. The target Site must have a
valid Fernet-compatible `encryption_key` in `site_config.json`. The existing
test Site had an invalid key shape; Infra repaired only that controlled test
Site before rerunning the verifier. Platform-created Sites must ensure the
encryption key is valid before OAuth configuration.

## Secret Redaction Proof

Local verifier uses a fake OAuth secret and fails if the value appears in the
termination summary. The runner also rejects a request containing
`client_secret` directly in args.

Evidence intentionally does not include kubeconfig contents, tokens, Secret
values, OAuth client secrets, DB passwords, private keys, pod logs, raw Site
config, or full environment dumps.

## Remaining Gaps

- Platform must create/manage the Platform-side OAuth Client.
- Platform must provide target Site OAuth client secrets through short-lived
  Kubernetes Secrets only.
- Platform-created Sites must have valid Frappe encryption keys before
  `oauth.configure`.
- `INF-023` user/access commands remain unimplemented.
