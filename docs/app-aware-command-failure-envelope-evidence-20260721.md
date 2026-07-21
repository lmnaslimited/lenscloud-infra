# App-Aware Command Failure Envelope Evidence - 2026-07-21

## Scope

Platform-to-Infra handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/app-aware-command-failure-envelope-recovery-20260721.md
```

Stage gate:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/stage-gates/app-aware-command-failure-recovery-20260721.md
```

This evidence is non-secret. It includes no raw traceback, Redis URL,
password, token, kubeconfig, Site config, environment dump, Kubernetes Secret
value, or OAuth secret.

## Runtime Target

Manager:

```text
116.203.22.81
```

Namespace:

```text
lenscloud-runtime-eu
```

Release runtime image:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
```

Admission posture:

- app-aware commands use the digest-pinned Release runtime image;
- generic `lenscloud-bench-command-runner` remains denied for
  `site_setup.complete`, `site_bootstrap.*`, `site_app.*`, and `bench.*`;
- mutable Release runtime tags remain denied.

Standard admission verifier already passed after the INF-028 digest apply:

```text
scripts/58-verify-platform-bench-command.sh
Bench Command Job/API RBAC verification passed.
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
```

## Controlled-Failure Contract

Infra used short-lived acceptance-only Release-runtime scripts with exact
allowlisted fault identifiers:

| Fault identifier | Command | Message ID |
| --- | --- | --- |
| `APP_INSTALL_FAILED` | `site_bootstrap.install_apps` | `LC-INFRA-BOOTSTRAP-0001` |
| `QUEUE_OVERLOADED` | `site_setup.complete` | `LC-INFRA-QUEUE-0001` |

Unauthorized or missing fault identifiers return:

```text
LC-INFRA-UNKNOWN-0001
reason = FAULT_NOT_AUTHORIZED
```

The controlled scripts did not accept arbitrary shell commands, did not mount
Secrets, did not use mutable images, and emitted only the canonical nested
`message` object to `/dev/termination-log`.

## Bootstrap Failure And Recovery

Target:

```text
Bench: run-20260716-e2e-update-132858-bench
Site: run-20260716-e2e-update-132858-site.cloud.lmnaslens.com
Prefix: run-20260721-0034-appaware
```

Failed Job:

```text
Job: run-20260721-0034-appaware-bootstrap-fail
Pod: run-20260721-0034-appaware-bootstrap-fail-pctpd
Command annotation: site_bootstrap.install_apps
```

Sanitized failure envelope:

```json
{
  "phase": "Failed",
  "command": "site_bootstrap.install_apps",
  "message": {
    "message_id": "LC-INFRA-BOOTSTRAP-0001",
    "message_type": "Error",
    "source": "Release Runtime",
    "destination": "Platform",
    "params": {
      "operation": "site_bootstrap.install_apps",
      "reason": "APP_INSTALL_FAILED",
      "app": "erpnext",
      "exit_code": 1
    },
    "safe_summary": "A required Site application could not be installed.",
    "details_ref": null
  },
  "redacted": true
}
```

Recovery Job:

```text
Job: run-20260721-0034-appaware-bootstrap-recover
Pod: run-20260721-0034-appaware-bootstrap-recover-h5l88
```

Recovery result:

```json
{
  "phase": "Succeeded",
  "command": "site_bootstrap.install_apps",
  "summary": "Site bootstrap app install completed",
  "apps": ["erpnext"],
  "state": "already_installed",
  "site": "run-20260716-e2e-update-132858-site.cloud.lmnaslens.com",
  "redacted": true
}
```

Retry/idempotency rule:

```text
Inspect installed apps first. If the requested app is already installed, skip
install and return success. If it is missing, retry install once only after the
fault is removed and the Release runtime/admission state is healthy.
```

## Setup-Complete Failure And Recovery

Setup state probe:

```text
Prefix: run-20260721-0041-setup-state
Result: tharahub.cloud.lmnaslens.com = true
```

Target:

```text
Bench: run-20260702-free-prod-bench
Site: tharahub.cloud.lmnaslens.com
Prefix: run-20260721-0044-setup-recovery
```

Failed Job:

```text
Job: run-20260721-0044-setup-recovery-fail
Pod: run-20260721-0044-setup-recovery-fail-2t8zn
Command annotation: site_setup.complete
```

Sanitized failure envelope:

```json
{
  "phase": "Failed",
  "command": "site_setup.complete",
  "message": {
    "message_id": "LC-INFRA-QUEUE-0001",
    "message_type": "Error",
    "source": "Release Runtime",
    "destination": "Platform",
    "params": {
      "operation": "site_setup.complete",
      "reason": "QUEUE_OVERLOADED",
      "queue": "default",
      "queued_count": 750
    },
    "safe_summary": "Target runtime background jobs did not drain in time.",
    "details_ref": null
  },
  "redacted": true
}
```

Recovery Job:

```text
Job: run-20260721-0044-setup-recovery-recover
Pod: run-20260721-0044-setup-recovery-recover-bhprg
```

Recovery result:

```json
{
  "phase": "Succeeded",
  "command": "site_setup.complete",
  "summary": "Site setup completion already complete",
  "setup_complete": true,
  "idempotent": true,
  "site": "tharahub.cloud.lmnaslens.com",
  "redacted": true
}
```

Retry/idempotency rule:

```text
Inspect setup state before retry. If setup is already complete, return
idempotent success and do not enqueue another setup. If setup is incomplete,
retry only after target queue capacity is healthy and no setup command is
queued or running.
```

## Unauthorized Fault Gate

Prefix:

```text
run-20260721-0048-appaware-unauth
```

Result:

```json
{
  "phase": "Failed",
  "command": "site_bootstrap.install_apps",
  "message": {
    "message_id": "LC-INFRA-UNKNOWN-0001",
    "message_type": "Error",
    "source": "Release Runtime",
    "destination": "Platform",
    "params": {
      "operation": "site_bootstrap.install_apps",
      "reason": "FAULT_NOT_AUTHORIZED"
    },
    "safe_summary": "Infra command failed with an unknown safe fallback.",
    "details_ref": null
  },
  "redacted": true
}
```

## Cleanup

Final cleanup probes:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n lenscloud-runtime-eu get job,pod -o name \
  | grep -E 'run-20260721-0034-appaware|run-20260721-0044-setup-recovery|run-20260721-0048-appaware-unauth'
```

Result:

```text
no output
```

## Caveat

These were Infra-owned Release-runtime Jobs that prove admission and the
canonical app-aware envelope/recovery contract at the runtime boundary.
Platform action-log persistence (`matched_by = Infra Supplied`) requires
Platform to run the same nested `summary.message` through
`run_app_aware_job`/`finish_action_log` in the next Platform acceptance pass.
