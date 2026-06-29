# Platform Bench Command Job/API Handoff

## Purpose

LensCloud Platform enforces Site Control Profile runtime policy through an
approved Bench Command Job/API contract. Platform must not invent unsupported
`FrappeSite` CRD fields for controls such as maintenance mode, developer mode,
site config, CORS, Bench Test, LATP, backup, or restore.

Platform owns:

- policy resolution from Subscription, Landscape, Environment, and Site Control
  Profile;
- deciding whether a command is allowed for the target customer/site;
- creating the request and command Job through the Kubernetes API;
- action logs, UI progress, retry, and evidence.

Infra/operator owns:

- namespace-scoped RBAC;
- command allowlist;
- Job admission guardrails;
- typed request/response contract;
- sanitized status and result summaries;
- verification and cleanup evidence.

## Current Mode

This handoff defines the Kubernetes Job/ConfigMap API mode.

Platform uses its restricted Kubernetes client to create:

1. one request `ConfigMap`;
2. one labelled `Job`.

The Job must run in an approved Runtime Namespace such as
`lenscloud-runtime-eu`. The kubeconfig context default namespace may remain
unchanged; Platform must pass the selected namespace explicitly.

The Phase 1 verification proves:

- Platform can create/read/delete only the required command ConfigMaps and
  Jobs in an approved runtime namespace;
- admission denies unsafe Job shapes;
- a positive harmless command Job completes and emits a sanitized result;
- Secret listing, pod logs, default namespace mutation, and unapproved namespace
  mutation remain denied.

Platform may run live `bench_test.status` smoke through this Job/ConfigMap
contract in `lenscloud-runtime-eu`.

## Ownership Model

Bench Command execution is an Infra runtime capability, not a Release Group
image responsibility.

LensCloud Platform owns customer policy and intent:

- which command is allowed for a Site;
- when the command should run;
- which approved Runtime Namespace, Bench, and Site are targeted;
- action logs, UI progress, retries, and customer-facing evidence.

Infra owns the command execution substrate:

- runner image source, build, publication, and digest pinning;
- image pull access for every approved Runtime Namespace;
- admission policy and RBAC;
- runner verification, cleanup, and non-secret evidence;
- the command contract and supported/unsupported matrix.

Platform must not ask every Release image to include the runner, and Platform
must not create a `Release Group` for the runner image. Release Groups continue
to describe customer Bench images such as `lens-pure`; the runner image is a
separate Infra-approved helper used only by temporary Bench Command Jobs.

Infra completed live runner verification for the pinned runner image with
`maintenance_mode.enable` on 2026-06-28. Platform may now integrate the
implemented runner commands behind Site Control policy, while keeping
runner-pending families explicitly `Unsupported`.

Infra has added production runner source for safe Site Control operations in:

```text
bench-command-runner/
```

The current runner image is published and admission-pinned:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
```

Live positive proof for the runner capability passed on 2026-06-28 after the
GHCR package was made publicly pullable by the EU worker. The current `v0.1.1`
image was live-verified again on 2026-06-29.

Real Frappe Operator sites PVC proof passed on 2026-06-29 with
`maintenance_mode.status` against:

```text
namespace: lenscloud-runtime-eu
bench: run-20260629-free-prod-bench
site: run-20260629-free-prod-site.cloud.lmnaslens.com
sites PVC: run-20260629-free-prod-bench-sites
detected layout: frappe-sites
```

## Runtime Namespace Scope

Allowed only in namespaces approved by Infra:

```text
lenscloud.io/runtime-namespace=true
lenscloud.io/managed-by=platform
lenscloud.io/managed-runtime=true
```

Do not run Bench Command Jobs in:

- `default`;
- operator namespaces;
- edge/TLS namespaces;
- unapproved customer namespaces;
- system namespaces.

`MariaDB/default/frappe-mariadb` is protected and is never mutated by this
contract.

## Request Schema

The request is stored in a ConfigMap key named `request.json`.

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260625-0001",
  "command": "maintenance_mode.enable",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "run-20260625-public-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "args": {
    "enabled": true
  },
  "timeoutSeconds": 300,
  "requestedBy": "Administrator",
  "reason": "Apply submitted Site Control Profile SCP-Prod-01"
}
```

Platform must validate the request before creating Kubernetes resources:

- command is in the allowlist;
- target Cluster and Runtime Namespace are approved;
- target Bench and Site belong to the expected Platform records;
- Site belongs to the Subscription/Environment policy being enforced;
- typed args match the command schema;
- timeout is within the allowed range;
- command retry is safe or explicitly marked as a retry.

## Job Labels And Annotations

Every command Job must carry:

```yaml
metadata:
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: <platform-command-id>
    lenscloud.io/customer: <customer-id-when-applicable>
  annotations:
    lenscloud.io/bench-command-family: <family>
    lenscloud.io/bench-command: <command>
    lenscloud.io/bench-command-request: <request-configmap-name>
```

The admission policy denies Platform-created Jobs that are not labelled as
`bench-command`, use an unsupported command family, mount Secrets, use envFrom,
run privileged, use a service-account token, use more than one container, or
have `restartPolicy` other than `Never`.

## Job Shape

Required properties:

```yaml
spec:
  backoffLimit: 0
  template:
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
```

The Job may read the request ConfigMap and non-secret ConfigMaps required for
the command. It must not mount Kubernetes Secrets or dump environment variables.

The admission policy currently allows only:

- the pinned production runner digest above; or
- the legacy `busybox:1.36` image for the narrow `bench_test.status`
  verification exception.

## Real Bench Sites PVC Mount Contract

For real Frappe Operator-created Benches, Platform must mount the Bench sites
PVC at:

```text
/home/frappe/frappe-bench/sites
```

and set:

```text
BENCH_PATH=/home/frappe/frappe-bench
BENCH_COMMAND_REQUEST=/lenscloud/request/request.json
```

`BENCH_SITES_PATH` is optional. If set, it must point to the mounted sites
directory. The runner defaults it to:

```text
/home/frappe/frappe-bench/sites
```

The runner supports both site layouts:

```text
/home/frappe/frappe-bench/sites/<site>/site_config.json
/home/frappe/frappe-bench/sites/frappe-sites/<site>/site_config.json
```

The live Frappe Operator layout observed on 2026-06-29 is:

```text
/home/frappe/frappe-bench/sites/frappe-sites/<site>/site_config.json
```

Do not use a `subPath` for the standard runner path unless a future Infra
workitem changes the contract.

Mount mode:

- status/read commands may mount the sites PVC read-only;
- mutating commands such as `maintenance_mode.enable`,
  `maintenance_mode.disable`, `developer_mode.enable`,
  `developer_mode.disable`, `site_config.set`, `site_config.unset`, and
  `cors.allowlist.update` require write access to the same sites PVC;
- Platform must still enforce Site Control policy before creating a mutating
  command Job.

Platform must not expose or read `site_config.json` contents. The runner returns
only sanitized summaries.

## Response Schema

Platform reads the Kubernetes Job and related Pod status. The runner writes a
sanitized JSON summary to the container termination message.

Example sanitized result:

```json
{
  "phase": "Succeeded",
  "commandId": "BCMD-20260625-0001",
  "command": "maintenance_mode.enable",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "run-20260625-public-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "summary": "Maintenance mode enabled",
  "changed": true,
  "redacted": true
}
```

No Secret values, DB passwords, private keys, kubeconfig content, full env
dumps, or raw backup file contents may appear in the result.

## Status Phases

Platform should normalize Job state to:

| Phase | Meaning |
| --- | --- |
| `Queued` | Request recorded, Job not yet observed |
| `Running` | Job active |
| `Succeeded` | Job complete and sanitized result parsed |
| `Failed` | Job failed with sanitized reason |
| `Timed Out` | Job exceeded Platform timeout |
| `Unsupported` | Command family or command is known but not implemented |
| `Rejected` | Request failed Platform or admission validation |
| `Cleanup Pending` | Terminal state reached, cleanup not complete |
| `Cleaned` | Temporary resources removed |

## Error Codes

| Code | Meaning |
| --- | --- |
| `COMMAND_UNSUPPORTED` | Known family/command is not implemented in the runner |
| `COMMAND_NOT_ALLOWED` | Platform policy does not allow the command for this Site |
| `INVALID_ARGUMENTS` | Args fail typed validation |
| `TARGET_NOT_FOUND` | Bench or Site cannot be verified |
| `TARGET_MISMATCH` | Bench/Site does not match Platform ownership/policy |
| `NAMESPACE_NOT_APPROVED` | Runtime Namespace lacks Platform approval |
| `ADMISSION_DENIED` | Kubernetes admission rejected the Job shape |
| `RBAC_DENIED` | Restricted identity lacks required permission |
| `TIMEOUT` | Command exceeded timeout |
| `RUNNER_FAILED` | Runner failed with sanitized detail |
| `SECRET_REDACTION_VIOLATION` | Output attempted to expose sensitive material |

## Command Matrix

| Family | Commands | Phase 1 Status | Notes |
| --- | --- | --- | --- |
| `backup` | `backup.create`, `backup.status` | Contracted, runner pending | Must return backup metadata only, not file contents or passwords |
| `restore` | `restore.preview`, `restore.execute`, `restore.status` | Unsupported until restore runbook is finalized | Must require explicit destructive confirmation and backup identity |
| `maintenance_mode` | `maintenance_mode.enable`, `maintenance_mode.disable`, `maintenance_mode.status` | Runner live-verified for `maintenance_mode.enable`; family ready for Platform integration and per-command acceptance | Uses approved site config key `maintenance_mode` |
| `developer_mode` | `developer_mode.enable`, `developer_mode.disable`, `developer_mode.status` | Runner source/local verified; ready for Platform policy-gated integration and per-command acceptance | Prod policy should normally reject enable |
| `site_config` | `site_config.set`, `site_config.unset`, `site_config.get` | Runner source/local verified for approved keys; ready for Platform policy-gated integration and per-command acceptance | Platform must validate key allowlist and value type |
| `cors` | `cors.allowlist.update`, `cors.allowlist.get` | Runner source/local verified; ready for Platform policy-gated integration and per-command acceptance | Wildcard origin rejected by runner |
| `bench_test` | `bench_test.trigger`, `bench_test.status` | Platform smoke available for `bench_test.status`; production suite runner pending | Phase 1 positive proof uses harmless `bench_test.status` contract check |
| `latp` | `latp.trigger`, `latp.status` | Contracted, runner pending | Production LATP must be non-destructive |

Known unsupported commands must return `Unsupported` with
`COMMAND_UNSUPPORTED`; Platform should show that truthfully and not claim live
runtime enforcement for that control.

## RBAC Requirements

In approved runtime namespaces, Platform can:

- create/get/list/watch/delete Jobs;
- create/get/list/watch/update/patch/delete ConfigMaps;
- list/watch Pods for status inspection;
- get/list/watch Services, PVCs, Events, and Ingresses.

Platform cannot:

- list Secrets;
- get individual Pods or read pod logs;
- create Jobs or ConfigMaps in `default`;
- mutate `default/frappe-mariadb`;
- mutate namespaces, CRDs, Nodes, operators, Traefik, TLS, or storage classes;
- access unapproved namespaces.

## Cleanup Behavior

Platform should delete command Jobs and request ConfigMaps after terminal state
and evidence capture.

Infra verification uses only `run-YYYYMMDD-HHMM-*` resources and cleans them
with manager credentials on exit if needed.

Do not delete:

```text
MariaDB/default/frappe-mariadb
PVC/default/storage-frappe-mariadb-0
operators
namespaces
Traefik/TLS/Certbot resources
```

## Example: Supported Verification Request

ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: run-20260625-1200-bench-command-request
  namespace: lenscloud-runtime-eu
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: run-20260625-1200-bench-command
  annotations:
    lenscloud.io/bench-command-family: bench_test
    lenscloud.io/bench-command: bench_test.status
data:
  request.json: |
    {
      "apiVersion": "lenscloud.io/v1",
      "kind": "BenchCommand",
      "command": "bench_test.status",
      "target": {
        "namespace": "lenscloud-runtime-eu",
        "bench": "verification",
        "site": "verification.localhost"
      },
      "args": {
        "mode": "status"
      },
      "timeoutSeconds": 60
    }
```

Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: run-20260625-1200-bench-command-positive
  namespace: lenscloud-runtime-eu
  labels:
    lenscloud.io/managed-by: platform
    lenscloud.io/resource-kind: bench-command
    lenscloud.io/resource-id: run-20260625-1200-bench-command
  annotations:
    lenscloud.io/bench-command-family: bench_test
    lenscloud.io/bench-command: bench_test.status
    lenscloud.io/bench-command-request: run-20260625-1200-bench-command-request
spec:
  backoffLimit: 0
  template:
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: bench-command
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              printf '%s\n' '{"phase":"Succeeded","command":"bench_test.status","sanitized":true}' > /dev/termination-log
```

The production runner image will replace the verification image and execute
approved `bench --site` operations in the target Bench/Site context.

## Verification

Infra verification script:

```bash
scripts/58-verify-platform-bench-command.sh
scripts/60-verify-bench-command-production-runner.sh
```

Script number `56` is already used by Runtime Namespace registration, so the
Bench Command verifier uses `58`.

Live verification passed on 2026-06-25. Expected/current summary:

```text
Bench Command Job/API RBAC verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive command family: bench_test
Sanitized result summary: present
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod log read: denied
Unapproved namespace and default namespace creation: denied
```

Production runner gate status:

```text
Runner image: published to GHCR and pinned by digest.
Admission: live-applied and denies non-runner maintenance_mode images.
Local container smoke: passed.
Live positive runner Job: passed for maintenance_mode.enable.
Current v0.1.1 runner image: live-verified on 2026-06-29.
Cleanup: temporary runner Job, ConfigMaps, and Pod removed.
```

Real Bench sites path verification on 2026-06-29:

```text
Real Bench runner sites path verification passed.
Positive command: maintenance_mode.status
Detected layout: frappe-sites
Sanitized result summary: present
Temporary resources: cleaned
```

Canonical evidence:

```text
docs/bench-command-job-evidence-20260625.md
docs/bench-command-production-runner-evidence-20260627.md
```

## Platform Agent Prompt

```text
Work inside lenscloud-platform.

Pull latest lenscloud-infra and start from:

- lenscloud-infra/docs/infra-workitems.md
- INF-010 Bench Command Job/API for Site Controls
- lenscloud-infra/docs/platform-bench-command-handoff.md
- lenscloud-infra/docs/bench-command-job-evidence-20260625.md

Implement Platform-side Site Control runtime enforcement against the Infra
Bench Command Job/API contract.

Platform responsibilities:

1. Resolve Site Control Profile policy from Subscription, Landscape,
   Environment, and Site.
2. Decide whether the command is allowed.
3. Validate command family, command, target Bench/Site, namespace, timeout, and
   typed args.
4. Create the request ConfigMap and labelled Job through the Python Kubernetes
   API only.
5. Watch Job and Pod status. Do not use kubectl.
6. Parse sanitized termination summary.
7. Record action logs, retry state, UI progress, and evidence.
8. Show unsupported commands as unsupported. Do not invent FrappeSite fields.
9. Never expose kubeconfig, tokens, Secret values, DB passwords, private keys,
   pod logs, or full env dumps.
10. Clean command Jobs and ConfigMaps after terminal state and evidence capture.

Start with `bench_test.status` as the live positive contract path.

Infra runner source now implements maintenance mode, developer mode, approved
site_config keys, and CORS allowlist locally, and the image is published and
admission-pinned. `maintenance_mode.enable` has passed live verification, so
Platform may integrate implemented runner commands behind Site Control policy
and per-command acceptance.

Backup, restore, Bench Test trigger, and LATP remain runner-pending or
unsupported as documented.

Return:
- Platform files changed;
- request/response examples generated by Platform;
- action log evidence;
- unsupported-command behavior;
- cleanup proof;
- remaining runner/API gaps.
```
