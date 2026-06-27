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

The runner source and Dockerfile are ready, but a production image has not yet
been built, pushed, pinned by digest, applied to admission policy, or live-tested
inside the cluster.

Build example:

```bash
docker build \
  -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.0 \
  bench-command-runner
```

Before enabling Platform UI controls beyond current `bench_test.status`, Infra
must:

1. build and publish the runner image;
2. pin the digest in the Platform/Infra handoff;
3. update admission policy to allow only the approved runner image;
4. run live proof against a temporary test Site/Bench;
5. capture cleanup proof for every temporary Job, ConfigMap, Bench, Site, and
   PVC if created.

## Protected Baseline

No live cluster mutation was performed by this production runner source pass.

The protected baseline remains:

```text
MariaDB/default/frappe-mariadb
operator namespaces and CRDs
Traefik/TLS/Certbot resources
Platform kubeconfig and token material
infrastructure Secrets and private keys
```

## Remaining Production Gaps

- Runner image publication and digest pinning.
- Live command proof for implemented commands.
- Admission policy image allowlist update after digest is available.
- Backup storage/metadata contract.
- Restore signed runbook and destructive confirmation.
- Bench Test and LATP production runner contracts.
- NetworkPolicy/resource quotas for command Jobs.
- Platform command availability should only enable locally implemented commands
  after live image verification; all others must remain `Unsupported`.
