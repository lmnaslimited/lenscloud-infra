# CUA OAuth Local Dev Base URL Runner Evidence - 2026-07-09

## Infra Workitem

`INF-026` CUA OAuth local-dev base URL runner contract.

## Requirement Source

Platform handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-oauth-local-dev-base-url-runner-20260707.md
```

Platform requested that `oauth.configure` accept the LensCloud Platform local
issuer:

```text
http://dev.localhost:8000
```

only when Platform explicitly passes:

```json
{"allow_local_oauth_http": true}
```

Plain HTTP for non-localhost issuers must remain rejected.

## Implementation Summary

Updated:

- `bench-command-runner/runner.py`
- `scripts/59-test-bench-command-runner-local.sh`
- `scripts/65-verify-cua-oauth-runner.sh`
- `bench-command-runner/README.md`
- `docs/cua-site-bootstrap-sso-runner-contract.md`
- `docs/platform-bench-command-handoff.md`
- `docs/test-cluster-build-handoff-sop.md`
- `manifests/access/lenscloud-platform-rbac.yaml`

Runner behavior:

- HTTPS `base_url` remains accepted without a local-dev flag.
- HTTP `base_url` is accepted only when `allow_local_oauth_http` is JSON
  boolean `true` and the host is `localhost`, `*.localhost`, or a loopback IP.
- Local HTTP is rejected when the flag is absent or false.
- Non-local HTTP is rejected even when the flag is true.
- `allow_local_oauth_http` is validation-only and is not written to the target
  Site `Social Login Key`.

## Local Verification

Executed from `lenscloud-infra`:

```bash
scripts/59-test-bench-command-runner-local.sh
python3 -m py_compile bench-command-runner/runner.py
bash -n scripts/65-verify-cua-oauth-runner.sh
bash -n scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
Bench command runner local verification passed.
```

The local verifier covered:

- positive `oauth.configure` with
  `base_url=http://dev.localhost:8000` and
  `allow_local_oauth_http=true`;
- persisted fake target state reports the request provider key
  `platform_oauth` and
  `base_url=http://dev.localhost:8000`;
- rejection of `base_url=http://dev.localhost:8000` when the flag is absent;
- rejection of `base_url=http://dev.localhost:8000` when the flag is false;
- rejection of `base_url=http://platform.example.com:8000` even when
  `allow_local_oauth_http=true`;
- direct `client_secret` arg rejection;
- no fake secret, DB password, private key, or token in termination summaries.

## Image Publication And Admission Pin

Image publication is complete. GHCR reports:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.11
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

Digest verification command:

```bash
docker buildx imagetools inspect ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.11
```

Verified output:

```text
Digest: sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

The repo admission manifest has been updated to pin that digest.

## Live Verification Attempt 1

Attempted on 2026-07-09 with the current Platform Settings values:

```text
oauth_provider_key=lenscloud
oauth_provider_name=LensCloud
oauth_base_url=http://dev.localhost:8000
allow_local_oauth_http=true
```

Target:

```text
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: run-20260707-cua-oauth.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
Temporary resource prefix: run-20260709-cua-oauth-local-http
```

Verifier command shape:

```bash
export RUNNER_IMAGE='ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef'
export REAL_BENCH=run-20260702-free-prod-bench
export REAL_SITE=run-20260707-cua-oauth.cloud.lmnaslens.com
export REAL_SITES_PVC=run-20260702-free-prod-bench-sites
export OAUTH_PROVIDER=lenscloud
export OAUTH_PROVIDER_NAME=LensCloud
export OAUTH_CLIENT_ID=<platform-oauth-client-id>
export OAUTH_BASE_URL=http://dev.localhost:8000
export OAUTH_ALLOW_LOCAL_HTTP=true
export OAUTH_REDIRECT_URL="https://${REAL_SITE}/api/method/frappe.integrations.oauth2_logins.custom/${OAUTH_PROVIDER}"

./scripts/65-verify-cua-oauth-runner.sh
```

Result: blocked before runner execution by live admission policy. The live
cluster still rejects the `v0.1.11` runner digest:

```text
The jobs "run-20260709-cua-oauth-local-http-status-before" is invalid:
ValidatingAdmissionPolicy 'lenscloud-platform-bench-command-job-create'
with binding 'lenscloud-platform-bench-command-job-create' denied request:
LensCloud Platform may create only labelled bench-command Jobs with an
approved command family, approved runner image, one non-privileged container,
no envFrom, no service-account token, restartPolicy Never, backoffLimit <= 1,
and no Secret volumes except the approved oauth-client-secret/client_secret
mount for oauth commands.
```

The available restricted Platform kubeconfig can create/delete namespace
Bench Command resources, but cannot patch or read cluster-scoped
`ValidatingAdmissionPolicy` resources. An admin/manager kubeconfig must apply
`manifests/access/lenscloud-platform-rbac.yaml` before the live verifier can
run the new image.

## Cleanup Proof

Local verifier cleanup removed its temporary directory through its shell trap.
The live admission-denied attempt was cleaned by exact resource name. Cleanup
verification:

```text
kubectl -n lenscloud-runtime-eu get job,configmap,pod \
  -l lenscloud.io/resource-id=run-20260709-cua-oauth-local-http

No resources found in lenscloud-runtime-eu namespace.

kubectl -n lenscloud-runtime-eu get secret \
  run-20260709-cua-oauth-local-http-oauth-client-secret --ignore-not-found

<no output>
```

## Status

Superseded by the successful 2026-07-10 run below.

## Live Verification - 2026-07-10

The manager VM admission pin was applied from `/root/lenscloud-infra`:

```text
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create configured
```

Live policy now allows:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

Verifier input:

```text
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: tara-communo-hub.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
OAuth provider: lenscloud
OAuth provider name: LensCloud
OAuth client ID: 08riiahaab
OAuth base URL: http://dev.localhost:8000
allow_local_oauth_http: true
Temporary resource prefix: run-20260710-cua-oauth-local-http
```

Result:

```text
CUA OAuth runner verification passed.
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: tara-communo-hub.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
Positive commands: oauth.status, oauth.configure with base_url=http://dev.localhost:8000 and allow_local_oauth_http=true
Negative checks: local HTTP without allow_local_oauth_http rejected; local HTTP with allow_local_oauth_http=false rejected; non-local HTTP with allow_local_oauth_http rejected; direct client_secret arg rejected; non-oauth Secret volume denied
Temporary resource prefix: run-20260710-cua-oauth-local-http
```

Cleanup proof:

```text
kubectl -n lenscloud-runtime-eu get job,configmap,pod \
  -l lenscloud.io/resource-id=run-20260710-cua-oauth-local-http

No resources found in lenscloud-runtime-eu namespace.

kubectl -n lenscloud-runtime-eu get secret \
  run-20260710-cua-oauth-local-http-oauth-client-secret --ignore-not-found

<no output>
```

No OAuth client secret, Kubernetes Secret value, kubeconfig, token, private
key, pod log, raw `site_config.json`, or full environment dump was recorded.

## Final Status

Complete. Platform may resume CUA OAuth acceptance with the `v0.1.11` runner
digest and the Platform Settings values above.
