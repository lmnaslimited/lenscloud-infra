# LensCloud Message Envelope Evidence - 2026-07-20

## Scope

Infra workitem:

```text
INF-028 LensCloud message envelope for runner/operator failures
```

Platform-to-Infra contract:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/lenscloud-message-envelope-runner-contract-20260720.md
```

This evidence is non-secret. It includes no kubeconfig, token, password,
private key, Kubernetes Secret value, raw `site_config.json`, pod log, Redis
credential, OAuth secret, or full environment dump.

## Implemented Contract

Canonical envelope nesting is the nested `message` object on failed or
unsupported scoped POC results:

```json
{
  "phase": "Failed",
  "code": "INVALID_ARGUMENTS",
  "command": "site_setup.complete",
  "commandId": "local-generic",
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
  },
  "redacted": true
}
```

Existing top-level `phase`, `code`, `command`, `commandId`, `target`,
`summary`, `changed`, `details`, `display`, and `redacted` fields are preserved
for backward compatibility. Successful scoped commands do not emit `message`.

Machine-readable catalog:

```text
bench-command-runner/message_catalog.v1.json
```

## Message IDs

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

All are `message_type=Error`, `source=Runner`, `destination=Platform`,
`resolution_owner=Infra`, and `retryability=Retry After Infra Action`.

## Local Contract Tests

Command:

```bash
python3 -m unittest bench-command-runner/test_message_envelope.py
```

Result:

```text
Ran 4 tests in 1.045s
OK
```

Coverage:

- every failed POC operation returned nested `message.message_id`;
- every `message.params` value was a JSON object;
- storage, queue overload, bootstrap install failure, timeout, unsupported,
  generic runner failure, and unknown fallback mapped to stable IDs;
- a second bootstrap failure with a different command ID kept the same stable
  message ID;
- configured canaries were absent from all termination payloads;
- successful `site_setup.status` had no failure message and kept `display`;
- all failure envelopes used the same nested shape.

## Backward Compatibility Smoke

Command:

```bash
scripts/59-test-bench-command-runner-local.sh
```

Result:

```text
Bench command runner local verification passed.
```

This preserved the existing success/display contract for:

- `maintenance_mode.*`
- `developer_mode.*`
- `site_config.*`
- `cors.allowlist.*`
- `backup.status`
- `site_setup.status`
- `site_setup.complete`
- `oauth.status`
- `oauth.configure`

Existing unsupported runner-pending checks still return
`phase=Unsupported`, `code=COMMAND_UNSUPPORTED`, and no `display`.

## Controlled Evidence

Controlled command IDs from `test_message_envelope.py`:

| Command ID | Command | Expected ID | Result |
| --- | --- | --- | --- |
| `local-unsupported` | `site_bootstrap.install_apps` | `LC-INFRA-COMMAND-0001` | passed |
| `local-storage` | `site_setup.status` against missing site path | `LC-INFRA-STORAGE-0001` | passed |
| `local-queue` | `site_setup.complete` with fake queue overload | `LC-INFRA-QUEUE-0001` | passed |
| `local-timeout` | `oauth.status` with fake timeout | `LC-INFRA-TIMEOUT-0001` | passed |
| `local-bootstrap_a` | `site_bootstrap.install_apps` with fake failed app | `LC-INFRA-BOOTSTRAP-0001` | passed |
| `local-generic` | `site_setup.complete` with rejected sensitive args | `LC-INFRA-RUNNER-0002` | passed |
| `local-unknown` | `oauth.status` with forced unknown failure | `LC-INFRA-UNKNOWN-0001` | passed |
| `local-success` | `site_setup.status` success | no failure message | passed |

Security evidence:

```text
Negative canaries checked:
must-not-leak
db_password
admin_password
client_secret
token=
private_key
BEGIN 

Result: absent from every tested termination payload.
```

## Cleanup

The automated contract tests and local smoke used only temporary directories
created under the host temp directory. Both registered shell/Python cleanup
handlers removed those directories on exit. No Kubernetes resources were
created, changed, or deleted for this pass.

Protected baseline was not touched:

- `MariaDB/default/frappe-mariadb`: not touched
- operator namespaces and CRDs: not touched
- Traefik/wildcard TLS/Certbot/edge: not touched
- Platform kubeconfig/token material: not touched
- infrastructure Secrets/private keys: not touched
- unlabelled or non-Platform-owned runtime resources: not touched

## Image And Live Status

Runner image digest created:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
```

Repo admission manifest is pinned to this digest in:

```text
manifests/access/lenscloud-platform-rbac.yaml
```

The manager checkout at `116.203.22.81:/root/lenscloud-infra` was replaced
with this local repo as canonical on 2026-07-21. The previous manager checkout
was retained at:

```text
/root/lenscloud-infra.backup-20260721-001545
```

Live admission apply:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -f manifests/access/lenscloud-platform-rbac.yaml
```

Result:

```text
configmap/lenscloud-platform-cluster-contract configured
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create configured
```

Cluster contract after apply:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
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
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Digest-pinned Release Group runtime image for site_setup.complete: admitted
Generic runner image for site_setup.complete: denied
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag: denied
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod log read: denied
Unapproved namespace and default namespace creation: denied
```

## Live INF-028 Envelope Verification

After the runner digest was admitted, Infra ran controlled live Bench Command
Jobs against the admitted runner image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
```

Live command prefix:

```text
run-20260721-0023-inf028
```

Result:

```text
INF-028 live envelope verification passed
success: phase=Succeeded code=None message_id=None
storage: phase=Failed code=TARGET_NOT_FOUND message_id=LC-INFRA-STORAGE-0001
generic: phase=Failed code=INVALID_ARGUMENTS message_id=LC-INFRA-RUNNER-0002
timeout: phase=Timed Out code=TIMEOUT message_id=LC-INFRA-TIMEOUT-0001
unknown: phase=Failed code=UNKNOWN_INFRA_FAILURE message_id=LC-INFRA-UNKNOWN-0001
```

Sanitized live results:

```json
{"kind":"success","command":"site_setup.status","commandId":"run-20260721-0023-inf028-success","phase":"Succeeded","message_id":null,"display":{"kind":"setup-status","safe":true,"value":"Pending"}}
{"kind":"storage","command":"site_setup.status","commandId":"run-20260721-0023-inf028-storage","phase":"Failed","code":"TARGET_NOT_FOUND","message_id":"LC-INFRA-STORAGE-0001","params":{"mount_kind":"bench-sites","operation":"site_setup.status","reason":"TARGET_NOT_FOUND"}}
{"kind":"generic","command":"oauth.status","commandId":"run-20260721-0023-inf028-generic","phase":"Failed","code":"INVALID_ARGUMENTS","message_id":"LC-INFRA-RUNNER-0002","params":{"operation":"oauth.status","reason":"INVALID_ARGUMENTS"}}
{"kind":"timeout","command":"oauth.status","commandId":"run-20260721-0023-inf028-timeout","phase":"Timed Out","code":"TIMEOUT","message_id":"LC-INFRA-TIMEOUT-0001","params":{"operation":"oauth.status","reason":"TIMEOUT","timeout_seconds":45}}
{"kind":"unknown","command":"oauth.status","commandId":"run-20260721-0023-inf028-unknown","phase":"Failed","code":"UNKNOWN_INFRA_FAILURE","message_id":"LC-INFRA-UNKNOWN-0001","params":{"operation":"oauth.status","reason":"UNKNOWN_INFRA_FAILURE"}}
```

Additional `oauth.configure` live POC operation:

```text
commandId: run-20260721-0025-inf028-oauth-configure
phase: Failed
code: INVALID_ARGUMENTS
message_id: LC-INFRA-RUNNER-0002
params: {"operation":"oauth.configure","reason":"INVALID_ARGUMENTS"}
safe_summary: Runner command failed.
```

The `oauth.configure` test intentionally omitted the mounted client-secret file
and did not place any secret value in the request ConfigMap.

Security evidence:

```text
Live envelope verifier checked the same canary denylist used by local tests.
No secret canary appeared in any tested termination payload.
```

Cleanup proof:

```text
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n lenscloud-runtime-eu get job,configmap,pod -o name | grep run-20260721-0023-inf028
result: no output

kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n lenscloud-runtime-eu get job,configmap,pod -o name | grep run-20260721-0025-inf028-oauth-configure
result: no output
```

Live POC coverage now includes:

- `site_setup.status` success and storage failure;
- `oauth.status` generic, timeout, and unknown fallback failures;
- `oauth.configure` generic failure with safe params.

`site_setup.complete` and `site_bootstrap.install_apps` live runner-envelope
tests remain deferred because live admission intentionally requires those
commands to run in the digest-pinned Release Group runtime image, not the
generic runner image.

## Remaining Gaps

- Live generic-runner envelope tests for `site_setup.complete` and
  `site_bootstrap.install_apps` remain deferred by the current app-aware
  admission boundary.
- End-to-end Platform action-log evidence for `matched_by = Infra Supplied`
  remains pending Platform parser integration.
- Operator scheduling/image-pull/admission failures are cataloged where known
  but not live-exercised in this source-only pass.
- Message envelopes outside the POC command set are deferred.
