# CUA Site Setup Runner Evidence - 2026-07-06

## Workitem

`INF-021` CUA setup wizard runner gate.

## Status

In live verification.

The runner source and local verification are complete. The updated runner image
has been published and admission has been updated in source. Live cluster
verification must prove the pinned image against a real Platform-managed
Bench/Site before Platform enables customer workflows.

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
frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps()
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

## Live Verification Command

After publishing the new runner image and pinning the digest in admission, run:

```bash
RUNNER_IMAGE='ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:2905fb71dfb449258214a7b76016a67d9b98bd66ea378394f98d791ab293dad5' \
REAL_BENCH='<platform-managed-bench>' \
REAL_SITE='<platform-managed-site.cloud.lmnaslens.com>' \
REAL_SITES_PVC='<platform-managed-bench-sites-pvc>' \
./scripts/64-verify-cua-site-setup-runner.sh
```

The live verifier proves:

- `site_setup.status` before completion;
- `site_setup.complete`;
- `site_setup.status` after completion;
- idempotent second completion;
- sensitive setup key rejection;
- cleanup of temporary request ConfigMaps and Jobs.

## Cleanup Proof

Local verification used only temporary filesystem resources through `mktemp`
and cleaned them on exit.

No cluster resources were created by this implementation pass.

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

- Apply the admission/RBAC manifest to the target cluster.
- Run `scripts/64-verify-cua-site-setup-runner.sh` against a real
  Platform-managed Bench/Site.
- Capture live proof before enabling Platform customer workflows.
- Keep OAuth, user, and site access commands blocked until setup proof is live.
