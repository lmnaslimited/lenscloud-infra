# Bench Command Result Display Evidence - 2026-06-29

## Scope

Infra workitem:

```text
INF-016 Bench Command sanitized result display contract
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/bench-command-result-display-contract-20260629.md
```

This evidence is non-secret. No kubeconfig, token, password, private key,
database credential, Kubernetes Secret value, raw `site_config.json` content,
pod log, or full environment dump is included.

## Implemented Contract

The runner now returns a top-level `display` object for supported read/status
commands:

```json
{
  "display": {
    "label": "Maintenance mode",
    "value": "Off",
    "kind": "boolean",
    "rawValue": 0,
    "safe": true
  }
}
```

Platform should render `display.value` only when `display.safe` is `true`.
`details` remains structured diagnostic context and should not be rendered
directly unless the command/key is explicitly known safe.

## Safe Display Mappings

| Command | Label | Kind | Value |
| --- | --- | --- | --- |
| `maintenance_mode.status` | `Maintenance mode` | `boolean` | `On` / `Off` |
| `developer_mode.status` | `Developer mode` | `boolean` | `On` / `Off` |
| `site_config.get` key `maintenance_mode` | `Maintenance mode` | `boolean` | `On` / `Off` |
| `site_config.get` key `developer_mode` | `Developer mode` | `boolean` | `On` / `Off` |
| `site_config.get` key `server_script_enabled` | `Server script` | `boolean` | `On` / `Off` |
| `site_config.get` key `client_script_enabled` | `Client script` | `boolean` | `On` / `Off` |
| `site_config.get` key `allow_cors` | `CORS allowlist` | `origin-list` | safe origin list |
| `cors.allowlist.get` | `CORS allowlist` | `origin-list` | safe origin list |

Boolean/flag rule:

```text
0 / false -> Off
1 / true  -> On
```

## Redaction And Failure Behavior

Sensitive `site_config.get` keys are rejected before values are returned. Keys
matching password, token, secret, private key, credential, cookie, or
authorization patterns return:

```text
phase: Failed
code: INVALID_ARGUMENTS
summary: site_config key is not approved
display: absent
```

Unsupported commands return:

```text
phase: Unsupported
code: COMMAND_UNSUPPORTED
display: absent
```

Target/path failures return sanitized `phase`, `code`, and `summary` only.

## Image

Published and admission-pinned image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.2
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:ab69e3ff24584e268bfa92f44c5d71e680ce1780cc8a4a9a5ce1e60b3e4bf4e7
```

Admission policy:

```text
manifests/access/lenscloud-platform-rbac.yaml
policy: lenscloud-platform-bench-command-job-create
observed generation after apply: 4
```

## Verification

Local verifier:

```text
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
maintenance_mode.status display block: passed
developer_mode.status display block: passed
site_config.get server_script_enabled display block: passed
cors.allowlist.get display block: passed
sensitive key rejection: passed
sites-root layout: passed
frappe-sites layout: passed
```

Generic live runner verifier:

```text
scripts/60-verify-bench-command-production-runner.sh
```

Result:

```text
Bench Command production runner verification passed.
Runtime namespace: lenscloud-runtime-eu
Runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:ab69e3ff24584e268bfa92f44c5d71e680ce1780cc8a4a9a5ce1e60b3e4bf4e7
Positive command: maintenance_mode.enable
Sanitized result summary: present
Negative non-runner image: denied
Temporary resource prefix: run-20260629-1817-bench-runner
```

Real Bench sites path and display verifier:

```text
scripts/61-verify-real-bench-runner-site-path.sh
```

Result:

```text
Real Bench runner sites path verification passed.
Runtime namespace: lenscloud-runtime-eu
Bench: run-20260629-free-prod-bench
Site: run-20260629-free-prod-site.cloud.lmnaslens.com
Sites PVC: run-20260629-free-prod-bench-sites
Positive command: maintenance_mode.status
Detected layout: frappe-sites
Display block: Maintenance mode
Sanitized result summary: present
Temporary resource prefix: run-20260629-1817-real-bench-runner
```

Cleanup proof:

```text
temporary Job: removed
temporary ConfigMap: removed
post-cleanup grep for verifier prefixes: no matching resources
```

## Platform Handoff Prompt

```text
Pull lenscloud-infra main at the commit that contains INF-016 Complete.

Read:
- docs/infra-workitems.md
- docs/platform-bench-command-handoff.md
- docs/bench-command-result-display-evidence-20260629.md

Update Platform result rendering for Bench Command actions:

1. Prefer top-level `display` when present and `display.safe == true`.
2. Render:
   - display.label
   - display.value
   - display.kind for formatting hints
3. Keep `details` available for backend assertions and audit context, but do
   not directly render `details.value` unless the command/key is explicitly
   known safe.
4. For boolean display kinds, render `On` / `Off` exactly as supplied by Infra.
5. For `origin-list`, render the safe origin list.
6. If `display` is absent, render sanitized `phase`, `code`, and `summary`.
7. Add tests proving:
   - `maintenance_mode.status` shows `Maintenance mode: Off` or `On`;
   - `developer_mode.status` shows `Developer mode: Off` or `On`;
   - `site_config.get` for approved keys shows the safe display value;
   - `cors.allowlist.get` shows only safe origins;
   - sensitive keys and runner-pending commands do not expose display values.

Use runner image:
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:ab69e3ff24584e268bfa92f44c5d71e680ce1780cc8a4a9a5ce1e60b3e4bf4e7

Do not expose kubeconfig, tokens, Secrets, DB passwords, private keys, pod logs,
raw site_config.json content, or full environment dumps.
```

## Remaining Gaps

- Backup storage/metadata contract.
- Restore runbook and destructive confirmation.
- Bench Test trigger/status production suite contract.
- LATP trigger/status production contract.
- NetworkPolicy/resource quotas for command Jobs.
