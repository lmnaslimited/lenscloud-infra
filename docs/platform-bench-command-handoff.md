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

Production backup/restore and control mutations still require a production
bench-command runner image or operator API implementation. Until that runner is
published, Platform can integrate the API shape and must show unsupported
runtime commands truthfully.

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
          image: <approved-runner-image>
```

The Job may read the request ConfigMap. It must not mount Kubernetes Secrets or
dump environment variables.

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
| `maintenance_mode` | `maintenance_mode.enable`, `maintenance_mode.disable`, `maintenance_mode.status` | Contracted, runner pending | Maps to approved `bench --site` or site config workflow |
| `developer_mode` | `developer_mode.enable`, `developer_mode.disable`, `developer_mode.status` | Contracted, runner pending | Prod policy should normally reject enable |
| `site_config` | `site_config.set`, `site_config.unset`, `site_config.get` | Contracted for approved keys only, runner pending | Platform must validate key allowlist and value type |
| `cors` | `cors.allowlist.update`, `cors.allowlist.get` | Contracted where supported, runner pending | Must normalize hostnames/origins and reject wildcards unless policy allows |
| `bench_test` | `bench_test.trigger`, `bench_test.status` | Verification stub available; production runner pending | Phase 1 positive proof uses harmless `bench_test.status` contract check |
| `latp` | `latp.trigger`, `latp.status` | Contracted, runner pending | Production LATP must be non-destructive |

Known unsupported commands must return `Unsupported` with
`COMMAND_UNSUPPORTED`; Platform should show that truthfully and not claim live
runtime enforcement for that control.

## RBAC Requirements

In approved runtime namespaces, Platform can:

- create/get/list/watch/delete Jobs;
- create/get/list/watch/update/patch/delete ConfigMaps;
- get/list/watch Pods, Services, PVCs, Events, and Ingresses.

Platform cannot:

- list Secrets;
- read pod logs;
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
```

Script number `56` is already used by Runtime Namespace registration, so the
Bench Command verifier uses `58`.

Expected summary:

```text
Bench Command Job/API RBAC verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive command family: bench_test
Sanitized result summary: present
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod logs: denied
Unapproved namespace and default namespace creation: denied
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

Start with `bench_test.status` as the positive contract path. Treat backup,
restore, maintenance mode, developer mode, site_config, CORS, Bench Test
trigger, and LATP trigger as contracted command families, but only mark runtime
enforcement complete when the runner/API supports the specific command.

Return:
- Platform files changed;
- request/response examples generated by Platform;
- action log evidence;
- unsupported-command behavior;
- cleanup proof;
- remaining runner/API gaps.
```
