# CUA Site Setup Runner Evidence - 2026-07-06

## Workitem

`INF-021` CUA setup wizard runner gate.

## Status

Complete.

The runner source and local verification are complete. The updated runner image
has been published, admission has been applied to the EU cluster, and live
cluster verification passed against a real Platform-managed Bench/Site.

## Files Changed

- `bench-command-runner/runner.py`
- `bench-command-runner/README.md`
- `scripts/59-test-bench-command-runner-local.sh`
- `scripts/64-verify-cua-site-setup-runner.sh`
- `manifests/access/lenscloud-platform-rbac.yaml`
- `docs/infra-workitems.md`
- `docs/platform-bench-command-handoff.md`
- `docs/handoffs/platform/cua-site-setup-runner-handoff-20260706.md`
- `lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/cua-site-setup-runner-20260706.md`

## Implementation Summary

Implemented Bench Command runner source for:

- `site_setup.status`
- `site_setup.complete`

The runner uses native Frappe setup APIs inside the target Bench/Site context:

```text
frappe.is_setup_complete()
frappe.client_cache.get_doc("Installed Applications")
frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
```

The runner does not call target Site HTTP APIs with Administrator credentials.
It does not use the Kubernetes API.

## Local Verification

Command:

```bash
./scripts/59-test-bench-command-runner-local.sh
python3 -m py_compile bench-command-runner/runner.py
bash -n scripts/64-verify-cua-site-setup-runner.sh scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
Bench command runner local verification passed.
```

## Published Runner Image

Tag:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.8
```

Digest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:2905fb71dfb449258214a7b76016a67d9b98bd66ea378394f98d791ab293dad5
```

Covered locally:

- existing Site Control commands still pass;
- `site_setup.status` returns Pending before completion;
- `site_setup.complete` completes setup in fake Frappe mode;
- `site_setup.status` returns Complete after completion;
- second `site_setup.complete` returns idempotent success;
- sensitive setup args are rejected with `INVALID_ARGUMENTS`;
- termination output does not contain the fake sensitive value.

## Admission/RBAC Change

`manifests/access/lenscloud-platform-rbac.yaml` now includes the
`site_setup` Bench Command family in the admission allowlist and pins the
`v0.1.8` runner digest above.

## Live Verification

Manager revision:

```text
6869dd2
```

Command:

```bash
RUNNER_IMAGE='ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:2905fb71dfb449258214a7b76016a67d9b98bd66ea378394f98d791ab293dad5' \
REAL_BENCH='run-20260702-free-prod-bench' \
REAL_SITE='run-20260702-free-site.cloud.lmnaslens.com' \
REAL_SITES_PVC='run-20260702-free-prod-bench-sites' \
EXPECT_PENDING_BEFORE_COMPLETE=0 \
PLATFORM_KUBECONFIG='.artifacts/lenscloud-eu.kubeconfig' \
RUNTIME_NAMESPACE='lenscloud-runtime-eu' \
TEST_PREFIX='run-20260706-cua-existing' \
./scripts/64-verify-cua-site-setup-runner.sh
```

Result:

```text
CUA site setup runner verification passed.
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260702-free-prod-bench
Site: run-20260702-free-site.cloud.lmnaslens.com
Sites PVC: run-20260702-free-prod-bench-sites
Positive commands: site_setup.status, site_setup.complete
Negative command: site_setup.complete with sensitive key rejected
Temporary resource prefix: run-20260706-cua-existing
No resources found in lenscloud-runtime-eu namespace.
```

The live verifier proved:

- `site_setup.status` before completion;
- `site_setup.complete`;
- `site_setup.status` after completion;
- idempotent second completion;
- sensitive setup key rejection;
- cleanup of temporary request ConfigMaps and Jobs.

## Cleanup Proof

Local verification used only temporary filesystem resources through `mktemp`
and cleaned them on exit.

Live verification created only temporary Jobs and request ConfigMaps with
prefix `run-20260706-cua-existing`. The verifier deleted them and confirmed no
resources remained with that label selector.

## Secret Redaction Proof

The local verifier rejects a request containing a fake sensitive key and checks
that the fake sensitive value is not present in the termination message.

The runner returns sanitized errors only. It does not include:

- kubeconfig contents or tokens;
- Kubernetes Secret values;
- Administrator passwords;
- user passwords;
- OAuth client secrets;
- DB passwords;
- private keys;
- raw pod logs;
- raw setup input dumps;
- raw `site_config.json`;
- full environment dumps.

## Remaining Gaps

- Platform may integrate `site_setup.status` and `site_setup.complete` through
  the Bench Command Job/API contract.
- OAuth runner source/local verification is now tracked under `INF-022`; the
  image is published and repo-pinned, but admission apply and live verification
  are still required before Platform enables it.
- User and site access commands remain unsupported until `INF-023` is
  implemented and live-verified.
