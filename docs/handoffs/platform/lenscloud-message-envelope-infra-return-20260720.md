# Platform Handoff: LensCloud Message Envelope Infra Return - 2026-07-20

## Status

Infra implemented the source-side LensCloud message envelope for the scoped
POC runner operations and verified it locally.

Infra workitem:

```text
INF-028 LensCloud message envelope for runner/operator failures
Status: Ready for Verification
```

Source Platform-to-Infra contract:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/lenscloud-message-envelope-runner-contract-20260720.md
```

Infra revision:

```text
base commit: 5de2908
working tree: contains INF-028 source/catalog/test/evidence changes
```

Runner image digest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
```

The repo admission manifest is pinned to this digest. Live admission apply and
verification passed on 2026-07-21.

Manager checkout note:

```text
manager: 116.203.22.81:/root/lenscloud-infra
local repo used as canonical
previous manager checkout backup: /root/lenscloud-infra.backup-20260721-001545
```

## Canonical Envelope

Infra selected the nested `message` object as the canonical shape. Existing
top-level fields remain for compatibility.

Complete sanitized example:

```json
{
  "phase": "Failed",
  "code": "INVALID_ARGUMENTS",
  "command": "site_setup.complete",
  "commandId": "local-generic",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "runner-test-bench",
    "site": "runner-test.localhost"
  },
  "summary": "site_setup.complete args contain a sensitive key",
  "changed": false,
  "redacted": true,
  "message": {
    "message_id": "LC-INFRA-RUNNER-0002",
    "message_type": "Error",
    "source": "Runner",
    "destination": "Platform",
    "params": {
      "operation": "site_setup.complete",
      "reason": "INVALID_ARGUMENTS"
    },
    "safe_summary": "Runner command failed.",
    "details_ref": null
  }
}
```

Platform should parse `message.message_id` and `message.params` when present.
Do not regex `summary` first when Infra supplied `message.message_id`.

## Catalog

Machine-readable catalog:

```text
lenscloud-infra/bench-command-runner/message_catalog.v1.json
```

Final IDs:

| Message ID | Meaning | Required params | Optional params |
| --- | --- | --- | --- |
| `LC-INFRA-RUNNER-0001` | runner image digest rejected/stale/not admitted | `operation`, `reason` | `requested_image_digest`, `admitted_image_digest` |
| `LC-INFRA-RUNNER-0002` | generic runner failure | `operation`, `reason` | `exit_code` |
| `LC-INFRA-STORAGE-0001` | Bench sites PVC/mount/subPath/site path failure | `operation`, `reason`, `mount_kind` | `layout`, `pvc` |
| `LC-INFRA-UNKNOWN-0001` | bounded unknown Infra fallback | `operation`, `reason` | none |
| `LC-INFRA-QUEUE-0001` | target runtime setup/background jobs did not drain | `operation`, `reason` | `queue`, `queued_count` |
| `LC-INFRA-BOOTSTRAP-0001` | bootstrap/default app installation failed | `operation`, `reason` | `app`, `exit_code` |
| `LC-INFRA-TIMEOUT-0001` | scoped command timeout | `operation`, `reason`, `timeout_seconds` | none |
| `LC-INFRA-COMMAND-0001` | scoped command unsupported by this runner path | `operation`, `reason` | none |

Infra adopted the provisional IDs and added:

```text
LC-INFRA-QUEUE-0001
LC-INFRA-BOOTSTRAP-0001
LC-INFRA-TIMEOUT-0001
LC-INFRA-COMMAND-0001
```

Platform-owned IDs remain reserved and are not emitted by Infra:

```text
LC-PLATFORM-QUEUE-0001
LC-PLATFORM-BOOTSTRAP-0001
LC-PLATFORM-UNKNOWN-0001
```

## Verification

Evidence:

```text
lenscloud-infra/docs/lenscloud-message-envelope-evidence-20260720.md
```

Automated contract test:

```bash
python3 -m unittest bench-command-runner/test_message_envelope.py
```

Result:

```text
Ran 4 tests in 1.045s
OK
```

Backward-compatibility smoke:

```bash
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
Bench command runner local verification passed.
```

Live admission verification:

```bash
MANAGER_KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
PLATFORM_KUBECONFIG=/root/lenscloud-infra/.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
scripts/58-verify-platform-bench-command.sh
```

Result:

```text
Bench Command Job/API RBAC verification passed.
Accepted Bench Command runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
Accepted Bench Command runner image for site_setup.status: admitted
Stale Bench Command runner image for site_setup.status: denied
Generic runner image for site_setup.complete: denied
```

Live INF-028 envelope verification:

```text
runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
prefix: run-20260721-0023-inf028
result: INF-028 live envelope verification passed
```

Covered live command IDs:

| Command ID | Command | Result |
| --- | --- | --- |
| `run-20260721-0023-inf028-success` | `site_setup.status` | `Succeeded`, no failure `message`, safe `display` |
| `run-20260721-0023-inf028-storage` | `site_setup.status` | `LC-INFRA-STORAGE-0001` |
| `run-20260721-0023-inf028-generic` | `oauth.status` | `LC-INFRA-RUNNER-0002` |
| `run-20260721-0023-inf028-timeout` | `oauth.status` | `LC-INFRA-TIMEOUT-0001` |
| `run-20260721-0023-inf028-unknown` | `oauth.status` | `LC-INFRA-UNKNOWN-0001` |
| `run-20260721-0025-inf028-oauth-configure` | `oauth.configure` | `LC-INFRA-RUNNER-0002` |

Cleanup:

```text
no job/configmap/pod resources remain for run-20260721-0023-inf028
no job/configmap/pod resources remain for run-20260721-0025-inf028-oauth-configure
```

Controlled command IDs covered:

| Command ID | Command | Expected ID |
| --- | --- | --- |
| `local-unsupported` | `site_bootstrap.install_apps` | `LC-INFRA-COMMAND-0001` |
| `local-storage` | `site_setup.status` missing site path | `LC-INFRA-STORAGE-0001` |
| `local-queue` | `site_setup.complete` fake queue overload | `LC-INFRA-QUEUE-0001` |
| `local-timeout` | `oauth.status` fake timeout | `LC-INFRA-TIMEOUT-0001` |
| `local-bootstrap_a` | `site_bootstrap.install_apps` fake failed app | `LC-INFRA-BOOTSTRAP-0001` |
| `local-generic` | `site_setup.complete` rejected sensitive args | `LC-INFRA-RUNNER-0002` |
| `local-unknown` | `oauth.status` forced unknown failure | `LC-INFRA-UNKNOWN-0001` |
| `local-success` | `site_setup.status` success | no failure message |

Security evidence:

```text
canaries checked and absent from every tested termination payload:
must-not-leak
db_password
admin_password
client_secret
token=
private_key
BEGIN 
```

Cleanup evidence:

```text
Only local temp directories were created.
Python and shell cleanup handlers removed them.
No Kubernetes resources were created, changed, or deleted.
Protected baseline was not touched.
```

## Backward Compatibility

Existing top-level parsing can continue to read:

```text
phase
code
command
commandId
target
summary
changed
details
display
redacted
```

`display` is still absent for failed and unsupported commands. Successful
commands do not include a failure `message`.

## Platform Changes Required

Update `lenscloud.api.messages` and any Bench Command result parser to:

1. Prefer nested `message.message_id` when present.
2. Store exact `message.params` as JSON.
3. Resolve message metadata from Platform's catalog mirror using the Infra ID.
4. Set `matched_by = Infra Supplied`.
5. Keep legacy pattern matching only when `message.message_id` is absent.
6. Keep sanitizing defensively even though Infra sanitizes at source.

Update `Orchestration Action Log` attachment logic to retain:

```text
message_id
params
message_type
source
destination
safe_summary
details_ref
resolution_owner
retryability
matched_by = Infra Supplied
```

## Platform Retest Sequence

Run:

```bash
bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_message_framework
bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_provisioning_progress
bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_customer_site_setup
bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_bench_command
```

Then run the controlled Site provisioning retest after Infra publishes and pins
and live-admits the runner image containing this source:

```text
site_setup.status
site_setup.complete
site_setup.status
oauth.status
oauth.configure
oauth.status
```

Expected action-log proof:

```text
message_id = Infra supplied LC-INFRA-*
params = exact safe JSON object from termination payload
matched_by = Infra Supplied
resolution_owner = Infra
retryability = Retry After Infra Action
customer-safe rendering uses Platform catalog text, not raw stderr
```

## Remaining Deferred Classifications

- Platform action-log proof for `matched_by = Infra Supplied` waits for
  Platform parser integration and controlled provisioning retest.
- Live generic-runner envelope tests for `site_setup.complete` and
  `site_bootstrap.install_apps` remain deferred by the current app-aware
  admission boundary; live admission requires those commands to use a
  digest-pinned Release Group runtime image.
- Operator scheduling/image-pull/admission failures are cataloged where known
  but not live-exercised in this source-only pass.
- Message envelopes outside the POC command set remain deferred.

## Copy/Paste Platform Prompt

```text
You are in lenscloud-platform/frappe-bench/apps/lenscloud.

Read:
- docs/handoffs/platform/lenscloud-message-envelope-infra-return-20260720.md
- docs/handoffs/infra/lenscloud-message-envelope-runner-contract-20260720.md
- docs/stage-gates/integration-message-model-poc-20260720.md
- docs/stage-gates/site-provisioning-under-5min-20260720.md
- lenscloud/api/messages.py
- lenscloud/api/provisioning_progress.py

Implement Platform parsing for the Infra canonical nested runner envelope:

- Prefer result.message.message_id when present.
- Store result.message.params as the exact safe JSON object.
- Mark the action-log match as matched_by = Infra Supplied.
- Attach resolution owner, retryability, source, destination, type, and safe summary from the Platform catalog mirror.
- Keep legacy fallback pattern matching only when Infra did not supply a message_id.
- Do not remove existing phase/code/summary/display compatibility.
- Do not render raw stderr, pod logs, site_config.json, environment dumps, OAuth secrets, tokens, kubeconfigs, private keys, or Kubernetes Secret values.

Run:
- bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_message_framework
- bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_provisioning_progress
- bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_customer_site_setup
- bench --site dev.localhost run-tests --app lenscloud --module lenscloud.api.test_bench_command

After Infra publishes/pins the runner image containing INF-028, run the controlled Site provisioning retest:
site_setup.status -> site_setup.complete -> site_setup.status -> oauth.status -> oauth.configure -> oauth.status.

Record action-log evidence proving:
- matched_by = Infra Supplied
- Infra message_id and params are retained
- customer-safe/operator-safe rendering works
- unknown controlled failures map to LC-INFRA-UNKNOWN-0001
- successful provisioning still advances one stage at a time without duplicate commands

Update the message model and under-five-minute stage gates only after evidence passes.
```
