# Bench Command Production Runner Evidence - 2026-06-27

## Scope

Infra workitem:

```text
INF-011 Bench Command production runner/API
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/infra-handoff-bench-command-production-runner-20260627.md
```

This evidence is non-secret. No kubeconfig, token, password, private key,
database credential, Kubernetes Secret value, raw backup content, pod log, or
full environment dump is included.

## Architecture Confirmation

The Bench Command runner is an Infra-owned helper image and cluster capability.
It is not a customer Bench Release image and must not be registered in
LensCloud Platform as a normal `Release Group`.

Platform consumes the runner through the Bench Command Job/API contract only
after Infra proves it in the target cluster. Platform remains responsible for
policy, intent, action logs, UI state, and request creation through the
restricted Kubernetes API; Infra remains responsible for runner image build,
publish, pull access, admission, RBAC, verification, and cleanup evidence.

## Implemented Repo Artifacts

Runner source:

```text
bench-command-runner/runner.py
bench-command-runner/Dockerfile
bench-command-runner/README.md
```

Local verification:

```text
scripts/59-test-bench-command-runner-local.sh
```

Documentation control:

```text
docs/documentation-governance-agent.md
docs/infra-workitems.md
```

## Implemented Commands

The runner implements these safe Site Control commands through mounted
`site_config.json` for the target Site:

| Command | Status |
| --- | --- |
| `maintenance_mode.enable` | Implemented, local verification passed |
| `maintenance_mode.disable` | Implemented |
| `maintenance_mode.status` | Implemented, local verification passed |
| `developer_mode.enable` | Implemented, local verification passed |
| `developer_mode.disable` | Implemented |
| `developer_mode.status` | Implemented |
| `site_config.set` | Implemented for approved non-sensitive keys |
| `site_config.unset` | Implemented for approved non-sensitive keys |
| `site_config.get` | Implemented for approved non-sensitive keys |
| `cors.allowlist.update` | Implemented, wildcard origin rejected |
| `cors.allowlist.get` | Implemented |

Approved default site config keys:

```text
maintenance_mode
developer_mode
allow_cors
server_script_enabled
client_script_enabled
```

## Runner-Pending Commands

The following commands remain contracted but return `Unsupported /
COMMAND_UNSUPPORTED` until the relevant production runner flow is finalized:

| Command | Reason |
| --- | --- |
| `backup.create` | backup storage/retention contract pending |
| `backup.status` | backup metadata contract pending |
| `restore.preview` | restore runbook and destructive confirmation pending |
| `restore.execute` | restore runbook and destructive confirmation pending |
| `restore.status` | restore status source pending |
| `bench_test.trigger` | test runner/suite contract pending |
| `bench_test.status` | current Platform smoke path exists; production suite status source pending |
| `latp.trigger` | LATP runner contract pending |
| `latp.status` | LATP status source pending |

## Local Verification

Command:

```bash
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
maintenance_mode.enable: Succeeded, changed true
maintenance_mode.status: Succeeded
developer_mode.enable: Succeeded, changed true
site_config.set server_script_enabled: Succeeded, changed true
cors.allowlist.update: Succeeded, changed true
backup.create: Unsupported / COMMAND_UNSUPPORTED
site_config.get db_password: Failed / INVALID_ARGUMENTS with no sensitive key leak
Bench command runner local verification passed.
```

Sanitized output sample:

```json
{"changed":true,"command":"site_config.set","details":{"key":"server_script_enabled","value":1},"phase":"Succeeded","redacted":true,"summary":"Set approved site_config key server_script_enabled"}
```

Secret-redaction proof:

- test fixture contained `db_password = must-not-leak`;
- local verifier failed the run if `must-not-leak`, password-like keys, tokens,
  private keys, or secrets appeared in termination summaries;
- verification passed after the sensitive-key rejection summary was made
  generic.

## Image And Live Verification Status

The runner source and Dockerfile are ready. The production image has been built,
pushed, pinned by digest, and added to the live admission policy.

2026-06-29 update: INF-015 replaced the original `v0.1.0` runner with `v0.1.1`
to support the real Frappe Operator `frappe-sites/<site>/site_config.json`
layout. The current pinned image is listed below. The original INF-011 image
history remains available in Git history.

Image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.1
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
```

Build and push summary:

```text
docker build --platform linux/amd64: passed
docker push: passed
published digest: sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
```

Container smoke summary:

```text
command: maintenance_mode.enable
docker_status: 0
phase: Succeeded
changed: true
redaction_check: pass
```

The smoke fixture contained a fake `db_password` value. The termination summary
did not contain the fake password value or the `db_password` key.

Live admission update:

```text
manifest: manifests/access/lenscloud-platform-rbac.yaml
policy: lenscloud-platform-bench-command-job-create
status: live-applied
approved production image: runner digest above
temporary verification exception: busybox:1.36 for bench_test.status only
```

Standard RBAC/Job API verification after the admission update:

```text
Restricted LensCloud Platform RBAC verification passed for lenscloud-runtime-eu.
Bench Command Job/API RBAC verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive command family: bench_test
Sanitized result summary: present
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod log read: denied
Unapproved namespace and default namespace creation: denied
```

Production runner positive live proof:

```text
script: scripts/60-verify-bench-command-production-runner.sh
command: maintenance_mode.enable
status: passed
runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
sanitized result summary: present
negative non-runner image: denied
```

Retest on 2026-06-28 before package visibility was corrected:

```text
temporary prefix: run-20260628-1453-bench-runner
result: blocked at the same ImagePullBackOff / GHCR 401 Unauthorized gate
cleanup: no matching temporary resources remained after verifier exit
```

Final INF-011 verification on 2026-06-28 after the package was made public:

```text
temporary prefix: run-20260628-1503-bench-runner
result: passed
positive command: maintenance_mode.enable
sanitized result summary: present
negative non-runner image: denied
cleanup: no matching temporary resources remained after verifier exit
```

Current `v0.1.1` verification is recorded in:

```text
docs/bench-command-real-site-path-evidence-20260629.md
```

Admission negative proof:

```text
attempt: maintenance_mode.enable with busybox:1.36
result: denied
reason: policy requires the approved runner image for non-verification commands
```

Cleanup proof:

```text
temporary prefix: run-20260627-1536-bench-runner
temporary Job: removed
temporary Pod: removed
temporary ConfigMaps: removed
post-cleanup grep in lenscloud-runtime-eu: no matching resources
```

Platform may now integrate implemented runner commands behind Site Control
policy and per-command acceptance. Runner-pending families must continue to
return `Unsupported / COMMAND_UNSUPPORTED`.

## Protected Baseline

No protected baseline resource was changed by this production runner pass.
Admission was updated live, and temporary verifier resources were cleaned.

The protected baseline remains:

```text
MariaDB/default/frappe-mariadb
operator namespaces and CRDs
Traefik/TLS/Certbot resources
Platform kubeconfig and token material
infrastructure Secrets and private keys
```

## Remaining Production Gaps

- Backup storage/metadata contract.
- Restore signed runbook and destructive confirmation.
- Bench Test and LATP production runner contracts.
- NetworkPolicy/resource quotas for command Jobs.
- Platform command availability should enable only implemented/policy-approved
  commands. Runner-pending families must remain `Unsupported`.
