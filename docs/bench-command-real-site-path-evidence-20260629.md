# Bench Command Real Site Path Evidence - 2026-06-29

## Scope

Infra workitem:

```text
INF-015 Real Bench runner sites PVC path contract
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/infra-handoff-real-bench-runner-site-config-path-20260629.md
```

This evidence is non-secret. No kubeconfig, token, password, private key,
database credential, Kubernetes Secret value, raw `site_config.json` content,
pod log, or full environment dump is included.

## Root Cause

Platform mounted the real Bench sites PVC at:

```text
/home/frappe/frappe-bench/sites
```

The previous runner looked only for:

```text
/home/frappe/frappe-bench/sites/<site>/site_config.json
```

The real Frappe Operator-created sites PVC uses:

```text
/home/frappe/frappe-bench/sites/frappe-sites/<site>/site_config.json
```

Therefore `maintenance_mode.status` returned:

```text
TARGET_NOT_FOUND / site_config.json was not found
```

The PVC itself was healthy and Bound.

## Implemented Fix

Runner source:

```text
bench-command-runner/runner.py
```

The runner now supports both layouts:

```text
sites/<site>/site_config.json
sites/frappe-sites/<site>/site_config.json
```

It rejects ambiguous matches and still blocks path traversal. It reports the
detected layout in sanitized command details as either:

```text
sites-root
frappe-sites
```

The runner also supports optional `BENCH_SITES_PATH`; if unset, it defaults to:

```text
BENCH_PATH/sites
```

## Image

Published and admission-pinned image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.4
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:eebfa0199c328207b14a949fa6232954a203a3937b1eed4930e9c3ec95b654d6
```

Admission policy:

```text
manifests/access/lenscloud-platform-rbac.yaml
policy: lenscloud-platform-bench-command-job-create
observed generation after apply: 3
```

## Verification

Local verifier:

```text
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
passed for sites-root layout
passed for frappe-sites layout
sensitive-key redaction checks passed
```

Generic live runner verifier:

```text
scripts/60-verify-bench-command-production-runner.sh
```

Result:

```text
Bench Command production runner verification passed.
Runtime namespace: lenscloud-runtime-eu
Runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:eebfa0199c328207b14a949fa6232954a203a3937b1eed4930e9c3ec95b654d6
Positive command: maintenance_mode.enable
Sanitized result summary: present
Negative non-runner image: denied
Temporary resource prefix: run-20260629-0744-bench-runner
```

Real Bench sites path verifier:

```text
scripts/61-verify-real-bench-runner-site-path.sh
```

Target:

```text
namespace: lenscloud-runtime-eu
bench: run-20260629-free-prod-bench
site: run-20260629-free-prod-site.cloud.lmnaslens.com
sites PVC: run-20260629-free-prod-bench-sites
```

Result:

```text
Real Bench runner sites path verification passed.
Positive command: maintenance_mode.status
Detected layout: frappe-sites
Sanitized result summary: present
Temporary resource prefix: run-20260629-0745-real-bench-runner
```

Cleanup proof:

```text
temporary Job: removed
temporary ConfigMap: removed
temporary inspector Pod: removed
post-cleanup grep for run-20260629 verifier prefixes: no matching resources
```

## Platform Mount Contract

Platform should mount the Bench sites PVC at:

```text
/home/frappe/frappe-bench/sites
```

Set:

```text
BENCH_PATH=/home/frappe/frappe-bench
BENCH_COMMAND_REQUEST=/lenscloud/request/request.json
```

`BENCH_SITES_PATH` is optional. If Platform sets it, use:

```text
BENCH_SITES_PATH=/home/frappe/frappe-bench/sites
```

Do not use `subPath` for the standard contract.

Mount mode:

- status/read commands may mount the sites PVC read-only;
- mutating commands require write access to the same sites PVC;
- Platform must enforce Site Control policy before creating a mutating command
  Job.

Platform must not read or expose `site_config.json` contents. It should parse
only the runner's sanitized termination summary.

## Platform Handoff Prompt

```text
Pull lenscloud-infra main at the commit that contains INF-015 Complete.

Read:
- docs/infra-workitems.md
- docs/platform-bench-command-handoff.md
- docs/bench-command-real-site-path-evidence-20260629.md

Update Platform Bench Command Job generation to use:

- runner image:
  ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:eebfa0199c328207b14a949fa6232954a203a3937b1eed4930e9c3ec95b654d6
- Bench sites PVC mounted at:
  /home/frappe/frappe-bench/sites
- BENCH_PATH=/home/frappe/frappe-bench
- BENCH_COMMAND_REQUEST=/lenscloud/request/request.json
- optional BENCH_SITES_PATH=/home/frappe/frappe-bench/sites

Do not use a subPath for the standard sites PVC mount.

For status/read commands, mount the sites PVC read-only.
For mutating commands, mount the sites PVC read-write only after Site Control
policy authorizes the action.

Re-run the real Free Plan public Prod Site Control checks:
- maintenance_mode.status must succeed;
- sanitized layout should report frappe-sites;
- backup.create should remain Unsupported / COMMAND_UNSUPPORTED;
- command Jobs and request ConfigMaps must be cleaned after terminal state.

Do not expose kubeconfig, tokens, Secrets, DB passwords, private keys, pod logs,
raw site_config.json content, or full environment dumps.
```

## Remaining Gaps

- Backup creation/storage/retention contract.
- Restore runbook and destructive confirmation.
- Bench Test trigger/status production suite contract.
- LATP trigger/status production contract.
- NetworkPolicy/resource quotas for command Jobs.

Update: INF-017 completed metadata-only `backup.status` live verification on
2026-06-30. See
[bench-command-remaining-families-evidence-20260630.md](./bench-command-remaining-families-evidence-20260630.md).
