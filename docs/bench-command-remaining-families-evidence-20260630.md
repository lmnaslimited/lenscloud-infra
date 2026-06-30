# Bench Command Remaining Families Evidence - 2026-06-30

## Scope

Infra workitem:

```text
INF-017 Remaining Bench Command runner families
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/bench-command-remaining-families-20260629.md
```

This evidence is non-secret. It does not include kubeconfig contents, tokens,
passwords, database credentials, private keys, Kubernetes Secret values, raw
`site_config.json`, backup file contents, pod logs, or full environment dumps.

## Decision

Infra can safely support metadata-only `backup.status` now.

Infra must keep `backup.create`, restore, Bench Test trigger, and LATP commands
as `Unsupported / COMMAND_UNSUPPORTED` until separate safety contracts exist.

The attempted `backup.create` path proved that a vanilla `bench backup` command
inside the current runner shape is not operator-layout safe enough to enable:
the real Frappe Operator sites PVC layout and Bench runtime context require a
dedicated backup execution contract. Infra will not fake success or expose raw
backup/storage internals to Platform.

## Runner Image

Published and admission-pinned image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.4
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:eebfa0199c328207b14a949fa6232954a203a3937b1eed4930e9c3ec95b654d6
```

Admission policy:

```text
manifests/access/lenscloud-platform-rbac.yaml
policy: lenscloud-platform-bench-command-job-create
observed generation after apply: 6
```

## Supported Matrix

| Family | Command | Status | Notes |
| --- | --- | --- | --- |
| `maintenance_mode` | `enable`, `disable`, `status` | Supported | Live path/display evidence exists |
| `developer_mode` | `enable`, `disable`, `status` | Supported | Local/source verified; Platform policy should usually reject enable in production |
| `site_config` | `set`, `unset`, `get` for approved keys | Supported | Sensitive keys rejected |
| `cors` | `allowlist.update`, `allowlist.get` | Supported | Wildcard origin rejected |
| `backup` | `backup.status` | Supported | Metadata-only count/latest display; no file contents |
| `backup` | `backup.create` | Unsupported | Requires a separate operator-compatible backup execution contract |
| `restore` | `restore.preview`, `restore.execute`, `restore.status` | Unsupported | Requires destructive restore runbook, confirmation, and isolation rules |
| `bench_test` | `bench_test.trigger` | Unsupported | Production suite contract pending |
| `latp` | `latp.trigger`, `latp.status` | Unsupported | LATP source/runner contract pending |

## Local Verification

Script:

```text
scripts/59-test-bench-command-runner-local.sh
```

Summary:

```text
maintenance_mode.enable: passed
developer_mode.enable: passed
site_config.set/get approved key: passed
cors.allowlist.update/get: passed
backup.status display: passed
backup.create unsupported: passed
restore.preview unsupported: passed
sites-root layout: passed
frappe-sites layout: passed
sensitive key rejection: passed
```

## Live Verification

Scripts:

```text
scripts/60-verify-bench-command-production-runner.sh
scripts/61-verify-real-bench-runner-site-path.sh
scripts/62-verify-bench-command-remaining-families.sh
```

Runtime target:

```text
namespace: lenscloud-runtime-eu
bench: run-20260629-free-prod-bench
site CR: run-20260629-free-prod-site
site host: run-20260629-free-prod-site.cloud.lmnaslens.com
sites PVC: run-20260629-free-prod-bench-sites
```

Live result summary:

```text
Bench Command production runner verification passed.
Runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:eebfa0199c328207b14a949fa6232954a203a3937b1eed4930e9c3ec95b654d6
Positive command: maintenance_mode.enable
Negative non-runner image: denied

Real Bench runner sites path verification passed.
Positive command: maintenance_mode.status
Detected layout: frappe-sites
Display block: Maintenance mode

Bench Command remaining families verification passed.
Positive command: backup.status
Unsupported commands: backup.create, restore.preview
Sanitized result summaries: present
Temporary resource prefix: run-20260630-0540-remaining-runner
```

## Cleanup Proof

Verifier prefixes:

```text
run-20260630-0540-bench-runner
run-20260630-0540-real-bench-runner
run-20260630-0540-remaining-runner
```

Cleanup result:

```text
temporary Jobs: removed
temporary ConfigMaps: removed
post-cleanup grep for verifier prefixes: no matching resources
```

Preserved resources:

```text
FrappeBench/lenscloud-runtime-eu/run-20260629-free-prod-bench: Ready
FrappeSite/lenscloud-runtime-eu/run-20260629-free-prod-site: Ready
MariaDB/default/frappe-mariadb: preserved
operators, namespaces, Traefik, TLS, PVCs: preserved
```

## Platform Handoff

Platform may consume `backup.status` as a supported read/status command.

Expected safe display shape:

```json
{
  "display": {
    "label": "Backups",
    "value": "0 available",
    "kind": "backup-status",
    "rawValue": {
      "count": 0,
      "latest": null
    },
    "safe": true
  }
}
```

Platform must continue to treat these commands as Unsupported:

```text
backup.create
restore.preview
restore.execute
restore.status
bench_test.trigger
latp.trigger
latp.status
```

## Remaining Production Gaps

- Operator-compatible backup creation contract.
- Backup retention/location policy and evidence model.
- Restore preview/execute runbook with destructive confirmation.
- Bench Test trigger/status production suite definition.
- LATP trigger/status source and non-destructive result model.
- NetworkPolicy/resource quotas for command Jobs.
