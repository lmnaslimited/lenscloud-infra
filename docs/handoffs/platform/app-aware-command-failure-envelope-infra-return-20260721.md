# Platform Handoff: App-Aware Command Failure Envelope Infra Return - 2026-07-21

## Source Contract

- Platform-to-Infra handoff:
  `apps/lenscloud/docs/handoffs/infra/app-aware-command-failure-envelope-recovery-20260721.md`
- Stage gate:
  `apps/lenscloud/docs/stage-gates/app-aware-command-failure-recovery-20260721.md`

## Infra Revision

- Base commit: `603b894`
- Return commit: `4b56ce2`
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

## Controlled-Failure Invocation Contract

Platform-created app-aware Jobs may invoke acceptance faults only by adding the
non-secret Job annotation:

```text
lenscloud.io/acceptance-fault
```

Allowed values:

| Annotation value | Command | Expected message |
| --- | --- | --- |
| `APP_INSTALL_FAILED` | `site_bootstrap.install_apps` | `LC-INFRA-BOOTSTRAP-0001` |
| `QUEUE_OVERLOADED` | `site_setup.complete` | `LC-INFRA-QUEUE-0001` |

The Platform-generated Release-runtime Job must copy the annotation into this
container env var using the Kubernetes Downward API:

```yaml
env:
  - name: LENS_INFRA_ACCEPTANCE_FAULT
    valueFrom:
      fieldRef:
        fieldPath: metadata.annotations['lenscloud.io/acceptance-fault']
```

The Release-runtime script must then validate the value against the exact
command allowlist before emitting a controlled fault. Missing, empty,
wrong-command, or unknown values must emit:

```json
{
  "message_id": "LC-INFRA-UNKNOWN-0001",
  "params": {
    "operation": "<command>",
    "reason": "FAULT_NOT_AUTHORIZED"
  }
}
```

Authorization/environment gate:

- only Platform's System Manager controlled acceptance path may set the
  annotation;
- never expose this as a customer-facing API arg or setup default;
- do not store it on Customer, Subscription, Site, Plan, Release, or Release
  Group records;
- do not pass arbitrary shell snippets, app names, stderr, or secrets through
  this input;
- use only the digest-pinned Release runtime image;
- keep normal app-aware admission policy active.

Current live admission status:

```text
Server-side dry-run admitted the exact annotation plus Downward API env shape
for both site_bootstrap.install_apps and site_setup.complete on 2026-07-21.
```

Disable/removal after proof:

- omit `lenscloud.io/acceptance-fault` from all normal Jobs;
- remove the `LENS_INFRA_ACCEPTANCE_FAULT` env block from Platform-generated
  Jobs after the live acceptance window, or leave it only behind a
  System-Manager-only test helper that emits no value unless the annotation is
  present;
- verify no retained Job manifests contain the annotation outside the test
  prefixes recorded below.

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

Controlled-fault invocation dry-run:

```text
acceptance fault annotation/downward-env dry-run admitted for bootstrap and setup
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

## Unauthorized Fault Gate

Prefix:

```text
run-20260721-0048-appaware-unauth
```

Result:

```text
Message ID: LC-INFRA-UNKNOWN-0001
Params: {"operation":"site_bootstrap.install_apps","reason":"FAULT_NOT_AUTHORIZED"}
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

Infra has now documented the exact controlled-fault invocation contract that a
Platform-created Job may use. Platform action-log persistence and customer
progress snapshots still require Platform to run the two live retained
Action Log/recovery scenarios through `run_app_aware_job` and
`finish_action_log`.

## Platform Acceptance

- Infra direct Release-runtime envelope/recovery evidence: accepted by
  Platform in the 2026-07-21 follow-up.
- Controlled-fault invocation contract: supplied in this amendment.
- Platform parser/persistence changes required: use `summary.message` from
  app-aware Release-runtime Jobs and persist it with
  `matched_by = Infra Supplied`.
- Customer provisioning recovery resumed: pending Platform live acceptance.
