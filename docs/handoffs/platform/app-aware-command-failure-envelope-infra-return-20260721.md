# Platform Handoff: App-Aware Command Failure Envelope Infra Return - 2026-07-21

## Source Contract

- Platform-to-Infra handoff:
  `apps/lenscloud/docs/handoffs/infra/app-aware-command-failure-envelope-recovery-20260721.md`
- Stage gate:
  `apps/lenscloud/docs/stage-gates/app-aware-command-failure-recovery-20260721.md`

## Infra Revision

- Base commit: `5de2908`
- Return commit: uncommitted working tree
- Runtime/release image digest used for proof:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0`
- Evidence:
  `lenscloud-infra/docs/app-aware-command-failure-envelope-evidence-20260721.md`

## Ownership Decision

Infra did not move app-aware commands onto the generic Bench Command runner and
did not weaken admission. The correct envelope source for these commands is the
Release-runtime script that Platform generates for app-aware Jobs.

Infra proved that the digest-pinned Release runtime can emit the same canonical
nested `message` envelope as the generic runner contract, with
`source = Release Runtime`, while admission continues to deny the generic
runner for `site_setup.complete`, `site_bootstrap.*`, `site_app.*`, and
`bench.*`.

## Controlled-Failure Contract

Acceptance-only fault identifiers:

| Fault identifier | Command | Message ID |
| --- | --- | --- |
| `APP_INSTALL_FAILED` | `site_bootstrap.install_apps` | `LC-INFRA-BOOTSTRAP-0001` |
| `QUEUE_OVERLOADED` | `site_setup.complete` | `LC-INFRA-QUEUE-0001` |

Gate rules:

- use only digest-pinned Release runtime images;
- keep normal app-aware admission policy active;
- do not accept arbitrary commands;
- do not mount Secrets for the controlled tests;
- emit only sanitized JSON through `/dev/termination-log`;
- if a fault identifier is missing or unauthorized, emit
  `LC-INFRA-UNKNOWN-0001` with `reason=FAULT_NOT_AUTHORIZED`.

## Classification And Recovery Contract

| Command/condition | Supplied message ID | Safe params | State inspection before retry | Retry/idempotency rule |
| --- | --- | --- | --- | --- |
| `site_bootstrap.install_apps` controlled failure | `LC-INFRA-BOOTSTRAP-0001` | `operation`, `reason=APP_INSTALL_FAILED`, `app`, `exit_code` | inspect installed apps | skip already-installed apps; retry missing apps once after fault/capacity is healthy |
| `site_setup.complete` queue failure | `LC-INFRA-QUEUE-0001` | `operation`, `reason=QUEUE_OVERLOADED`, `queue`, `queued_count` | inspect setup state and queue health | return idempotent success if already complete; otherwise retry only when no setup command is queued/running |
| Timeout | `LC-INFRA-TIMEOUT-0001` | `operation`, `reason=TIMEOUT`, `timeout_seconds` | inspect installed-app/setup state | no blind retry until state is known |
| Unknown/unauthorized fault | `LC-INFRA-UNKNOWN-0001` | `operation`, bounded `reason` | operator inspection required | no blind customer retry |

## Automated Verification

Prior admission verifier:

```text
scripts/58-verify-platform-bench-command.sh
Bench Command Job/API RBAC verification passed.
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
```

Live app-aware verifier:

```text
app-aware live envelope and recovery verification passed
setup-complete app-aware failure and idempotent recovery passed
unauthorized app-aware fault gate verification passed
```

## Live Bootstrap Failure And Recovery Evidence

Target:

```text
Bench: run-20260716-e2e-update-132858-bench
Site: run-20260716-e2e-update-132858-site.cloud.lmnaslens.com
Prefix: run-20260721-0034-appaware
```

Failed:

```text
Job: run-20260721-0034-appaware-bootstrap-fail
Pod: run-20260721-0034-appaware-bootstrap-fail-pctpd
Message ID: LC-INFRA-BOOTSTRAP-0001
Params: {"operation":"site_bootstrap.install_apps","reason":"APP_INSTALL_FAILED","app":"erpnext","exit_code":1}
```

Recovered:

```text
Job: run-20260721-0034-appaware-bootstrap-recover
Pod: run-20260721-0034-appaware-bootstrap-recover-h5l88
Result: Succeeded, state=already_installed
```

## Live Setup-Complete Failure And Recovery Evidence

Target:

```text
Bench: run-20260702-free-prod-bench
Site: tharahub.cloud.lmnaslens.com
Prefix: run-20260721-0044-setup-recovery
```

Failed:

```text
Job: run-20260721-0044-setup-recovery-fail
Pod: run-20260721-0044-setup-recovery-fail-2t8zn
Message ID: LC-INFRA-QUEUE-0001
Params: {"operation":"site_setup.complete","reason":"QUEUE_OVERLOADED","queue":"default","queued_count":750}
```

Recovered:

```text
Job: run-20260721-0044-setup-recovery-recover
Pod: run-20260721-0044-setup-recovery-recover-bhprg
Result: Succeeded, setup_complete=true, idempotent=true
```

## Secret-Safety Evidence

The live verifier rejected any payload containing:

```text
password
token=
client_secret
private_key
BEGIN 
redis://
Traceback
```

No raw traceback, Redis URL, password, token, kubeconfig, Site config,
environment dump, or Kubernetes Secret value was present in the captured
termination summaries.

## Cleanup Evidence

Final cleanup probe:

```text
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n lenscloud-runtime-eu get job,pod -o name | grep -E 'run-20260721-0034-appaware|run-20260721-0044-setup-recovery|run-20260721-0048-appaware-unauth'
```

Result:

```text
no output
```

## Remaining Caveats

Infra proved the Release-runtime envelope and recovery contract with direct
app-aware Kubernetes Jobs. Platform action-log persistence and customer
progress snapshots still require Platform to run the same nested
`summary.message` through `run_app_aware_job` and `finish_action_log`.

## Platform Acceptance

- Contract accepted: pending Platform review
- Platform parser/persistence changes required: use `summary.message` from
  app-aware Release-runtime Jobs and persist it with `matched_by = Infra Supplied`
- Customer provisioning recovery resumed: pending Platform acceptance
*** Add File: /Users/arunkumar.ganesan/lensk8s/lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/app-aware-command-failure-envelope-infra-return-20260721.md
# Platform Handoff: App-Aware Command Failure Envelope Infra Return - 2026-07-21

## Source Contract

- Platform-to-Infra handoff:
  `docs/handoffs/infra/app-aware-command-failure-envelope-recovery-20260721.md`
- Stage gate:
  `docs/stage-gates/app-aware-command-failure-recovery-20260721.md`

## Infra Revision

- Base commit: `5de2908`
- Return commit: uncommitted working tree
- Runtime/release image digest used for proof:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0`
- Canonical Infra evidence:
  `lenscloud-infra/docs/app-aware-command-failure-envelope-evidence-20260721.md`

## Ownership Decision

Infra did not move app-aware commands onto the generic Bench Command runner and
did not weaken admission. The correct envelope source for these commands is the
Release-runtime script that Platform generates for app-aware Jobs.

Infra proved the digest-pinned Release runtime can emit the canonical nested
`message` envelope with `source = Release Runtime`, while admission continues
to deny the generic runner for `site_setup.complete`, `site_bootstrap.*`,
`site_app.*`, and `bench.*`.

## Controlled-Failure Contract

| Fault identifier | Command | Message ID |
| --- | --- | --- |
| `APP_INSTALL_FAILED` | `site_bootstrap.install_apps` | `LC-INFRA-BOOTSTRAP-0001` |
| `QUEUE_OVERLOADED` | `site_setup.complete` | `LC-INFRA-QUEUE-0001` |

Unauthorized or missing fault identifiers return `LC-INFRA-UNKNOWN-0001` with
`reason=FAULT_NOT_AUTHORIZED`.

## Classification And Recovery Contract

| Command/condition | Supplied message ID | Safe params | State inspection before retry | Retry/idempotency rule |
| --- | --- | --- | --- | --- |
| `site_bootstrap.install_apps` controlled failure | `LC-INFRA-BOOTSTRAP-0001` | `operation`, `reason=APP_INSTALL_FAILED`, `app`, `exit_code` | inspect installed apps | skip already-installed apps; retry missing apps once after fault/capacity is healthy |
| `site_setup.complete` queue failure | `LC-INFRA-QUEUE-0001` | `operation`, `reason=QUEUE_OVERLOADED`, `queue`, `queued_count` | inspect setup state and queue health | return idempotent success if already complete; otherwise retry only when no setup command is queued/running |
| Timeout | `LC-INFRA-TIMEOUT-0001` | `operation`, `reason=TIMEOUT`, `timeout_seconds` | inspect installed-app/setup state | no blind retry until state is known |
| Unknown/unauthorized fault | `LC-INFRA-UNKNOWN-0001` | `operation`, bounded `reason` | operator inspection required | no blind customer retry |

## Automated Verification

Admission verifier:

```text
scripts/58-verify-platform-bench-command.sh
Bench Command Job/API RBAC verification passed.
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
```

Live app-aware verifier:

```text
app-aware live envelope and recovery verification passed
setup-complete app-aware failure and idempotent recovery passed
unauthorized app-aware fault gate verification passed
```

## Live Bootstrap Failure And Recovery Evidence

Target:

```text
Bench: run-20260716-e2e-update-132858-bench
Site: run-20260716-e2e-update-132858-site.cloud.lmnaslens.com
Prefix: run-20260721-0034-appaware
```

Failed:

```text
Job: run-20260721-0034-appaware-bootstrap-fail
Pod: run-20260721-0034-appaware-bootstrap-fail-pctpd
Message ID: LC-INFRA-BOOTSTRAP-0001
Params: {"operation":"site_bootstrap.install_apps","reason":"APP_INSTALL_FAILED","app":"erpnext","exit_code":1}
```

Recovered:

```text
Job: run-20260721-0034-appaware-bootstrap-recover
Pod: run-20260721-0034-appaware-bootstrap-recover-h5l88
Result: Succeeded, state=already_installed
```

## Live Setup-Complete Failure And Recovery Evidence

Target:

```text
Bench: run-20260702-free-prod-bench
Site: tharahub.cloud.lmnaslens.com
Prefix: run-20260721-0044-setup-recovery
```

Failed:

```text
Job: run-20260721-0044-setup-recovery-fail
Pod: run-20260721-0044-setup-recovery-fail-2t8zn
Message ID: LC-INFRA-QUEUE-0001
Params: {"operation":"site_setup.complete","reason":"QUEUE_OVERLOADED","queue":"default","queued_count":750}
```

Recovered:

```text
Job: run-20260721-0044-setup-recovery-recover
Pod: run-20260721-0044-setup-recovery-recover-bhprg
Result: Succeeded, setup_complete=true, idempotent=true
```

## Secret-Safety Evidence

The live verifier rejected any payload containing:

```text
password
token=
client_secret
private_key
BEGIN 
redis://
Traceback
```

No raw traceback, Redis URL, password, token, kubeconfig, Site config,
environment dump, or Kubernetes Secret value was present.

## Cleanup Evidence

Final cleanup probe:

```text
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n lenscloud-runtime-eu get job,pod -o name | grep -E 'run-20260721-0034-appaware|run-20260721-0044-setup-recovery|run-20260721-0048-appaware-unauth'
```

Result:

```text
no output
```

## Remaining Caveats

Infra proved the Release-runtime envelope and recovery contract with direct
app-aware Kubernetes Jobs. Platform action-log persistence and customer
progress snapshots still require Platform to run the same nested
`summary.message` through `run_app_aware_job` and `finish_action_log`.

## Platform Acceptance

- Contract accepted: pending Platform review
- Platform parser/persistence changes required: use `summary.message` from
  app-aware Release-runtime Jobs and persist it with `matched_by = Infra Supplied`
- Customer provisioning recovery resumed: pending Platform acceptance
