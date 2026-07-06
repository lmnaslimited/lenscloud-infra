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

The current runner image is published and pinned in the repo admission
manifest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

Live positive proof for the original runner capability passed on 2026-06-28
after the GHCR package was made publicly pullable by the EU worker. The `v0.1.8`
image with the display and metadata-only `backup.status` contracts was
live-verified on 2026-06-30. The `v0.1.9` image above includes OAuth source and
must still be applied and live-verified before Platform enables OAuth.

The `site_setup.status` and `site_setup.complete` commands are implemented and
live-verified through `INF-021`. Platform may integrate them through the Bench
Command Job/API path.

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
`bench-command`, use an unsupported command family, use envFrom, run
privileged, use a service-account token, use more than one container, or have
`restartPolicy` other than `Never`.

Secret-volume rule:

- all non-OAuth command families must not mount Secrets;
- `oauth.configure` may mount exactly one Secret volume named
  `oauth-client-secret`;
- the Secret volume must expose only the key `client_secret`;
- it must be mounted read-only at `/lenscloud/secrets`;
- the request ConfigMap, termination message, action logs, evidence, and
  browser responses must never contain the OAuth client secret value.

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
          image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

The Job may read the request ConfigMap and non-secret ConfigMaps required for
the command. Non-OAuth commands must not mount Kubernetes Secrets or dump
environment variables. `oauth.configure` may mount only the narrowly approved
short-lived client-secret Secret described above.

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
  "display": {
    "label": "Maintenance mode",
    "value": "On",
    "kind": "boolean",
    "rawValue": 1,
    "safe": true
  },
  "redacted": true
}
```

No Secret values, DB passwords, private keys, kubeconfig content, full env
dumps, or raw backup file contents may appear in the result.

## Result Display Contract

The runner may include a top-level `display` object for commands whose result is
safe and useful for a human UI. Platform should prefer `display` for the
operator-facing result text and keep `details` as structured diagnostic context.

Stable display fields:

| Field | Type | UI Safe | Meaning |
| --- | --- | --- | --- |
| `display.label` | string | Yes | Human label, for example `Maintenance mode` |
| `display.value` | string/list/number/null | Yes when `safe=true` | Human display value |
| `display.kind` | string | Yes | Renderer hint such as `boolean`, `origin-list`, `string`, `integer`, `empty` |
| `display.rawValue` | scalar/list/null | Yes when `safe=true` | Machine-friendly safe value |
| `display.safe` | boolean | Yes | Must be `true` before Platform renders `display.value` |

Platform must not render `details.value` directly unless the command/key is
explicitly known safe. `details` remains useful for audits and backend tests,
but `display` is the UI contract.

Boolean/flag display rule:

```text
0 / false -> Off
1 / true  -> On
```

Supported read/status display mappings:

| Command | Display label | Kind | Display value |
| --- | --- | --- | --- |
| `maintenance_mode.status` | `Maintenance mode` | `boolean` | `On` or `Off` |
| `developer_mode.status` | `Developer mode` | `boolean` | `On` or `Off` |
| `site_config.get` with `maintenance_mode` | `Maintenance mode` | `boolean` | `On` or `Off` |
| `site_config.get` with `developer_mode` | `Developer mode` | `boolean` | `On` or `Off` |
| `site_config.get` with `server_script_enabled` | `Server script` | `boolean` | `On` or `Off` |
| `site_config.get` with `client_script_enabled` | `Client script` | `boolean` | `On` or `Off` |
| `site_config.get` with `allow_cors` | `CORS allowlist` | `origin-list` | safe origin list |
| `cors.allowlist.get` | `CORS allowlist` | `origin-list` | safe origin list |

The runner rejects sensitive keys before returning a value. Any
`site_config.get` key matching password, token, secret, private key, credential,
cookie, or authorization patterns returns:

```text
phase: Failed
code: INVALID_ARGUMENTS
summary: site_config key is not approved
```

Failed or unsupported responses do not include a `display` object. Platform
should render the sanitized `summary`, `phase`, and `code` instead.

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
| `backup` | `backup.status` | Runner live-verified for metadata-only status | Returns backup count/latest metadata and safe `display`; never returns backup file contents |
| `backup` | `backup.create` | Unsupported / runner-pending | Live attempt proved vanilla `bench backup` is not operator-layout safe yet; requires a separate backup execution contract |
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

## CUA Site Bootstrap And SSO Commands

CUA Site bootstrap and SSO commands use the same Bench Command Job/API pattern.
The `site_setup` runner commands are implemented, admission-pinned, and
live-verified. `INF-022` adds target-Site Social Login Key management for the
Platform-owned OAuth Client. Runner source, image publication, repo digest pin,
and local verification are complete, but Platform must not enable OAuth
commands until Infra applies the admission update and records live verification
with `scripts/65-verify-cua-oauth-runner.sh`. User and site access commands
remain unsupported until their own gates are implemented and verified.

Canonical Infra gates:

- `INF-020` CUA native setup API readiness gate
- `INF-021` CUA setup wizard runner gate
- `INF-022` CUA OAuth runner gate
- `INF-023` CUA user/access runner gate
- `INF-024` CUA end-to-end runner handoff

Contract and next implementation prompt:

- [cua-site-bootstrap-sso-runner-contract.md](./cua-site-bootstrap-sso-runner-contract.md)
- [cua-site-bootstrap-sso-implementation-prompt-20260706.md](./cua-site-bootstrap-sso-implementation-prompt-20260706.md)

Planned CUA command families:

| Family | Commands | Current status | Gate |
| --- | --- | --- | --- |
| `site_setup` | `site_setup.status`, `site_setup.complete` | Supported / live-verified | Uses native Frappe setup APIs; see `INF-021` evidence |
| `oauth` | `oauth.status`, `oauth.configure` | Source/local verified; image published and repo-pinned; pending admission apply and live verification | `INF-022`; Platform owns OAuth Client, Infra runner owns target Site Social Login Key |
| `user` | `user.ensure`, `user.disable`, `user.roles.set` | Unsupported / blocked | `INF-023`; wait for OAuth live verification, then use standard Frappe APIs first |
| `site_access` | `site_access.status` | Unsupported / blocked | `INF-023`; wait for OAuth live verification, then use standard Frappe APIs first |

The setup wizard commands should use native Frappe v16 APIs:

```text
frappe.is_setup_complete
frappe.client_cache.get_doc("Installed Applications")
frappe.desk.page.setup_wizard.setup_wizard.setup_complete
```

OAuth setup uses the target Site's standard Frappe `Social Login Key` DocType.
Platform owns the Platform-side `OAuth Client` and passes non-secret Social
Login configuration through the request ConfigMap. The OAuth client secret must
be mounted as a short-lived Kubernetes Secret at
`/lenscloud/secrets/client_secret` and must never appear in ConfigMaps,
termination messages, action logs, evidence, or browser responses.

User/access work should use standard Frappe APIs or bench-executed standard
Frappe methods first. Add a branding app only if standard APIs prove
insufficient and the gap is documented.

Platform may enable `site_setup` for customer workflows after consuming the
dedicated `INF-021` handoff. OAuth must remain disabled in Platform until
`INF-022` live verification evidence is published. User and site access
commands must continue to return `Unsupported` with `COMMAND_UNSUPPORTED`.

### Backup Status Display

`backup.status` returns a safe display object:

```json
{
  "phase": "Succeeded",
  "command": "backup.status",
  "summary": "Read backup status",
  "display": {
    "label": "Backups",
    "value": "0 available",
    "kind": "backup-status",
    "rawValue": {
      "count": 0,
      "latest": null
    },
    "safe": true
  }
}
```

Platform may render the count/latest metadata. Platform must not expect or ask
Infra to return backup file contents, database dumps, passwords, Secret values,
or raw private files.

## RBAC Requirements

In approved runtime namespaces, Platform can:

- create/get/list/watch/delete Jobs;
- create/get/list/watch/update/patch/delete ConfigMaps;
- list/watch Pods for status inspection;
- delete terminal Platform-labelled Bench Command Pods after result capture;
- get/list/watch Services, PVCs, Events, and Ingresses.

Platform cannot:

- list Secrets;
- get individual Pods or read pod logs;
- delete running/non-terminal Pods;
- delete unlabelled Pods;
- create Jobs or ConfigMaps in `default`;
- mutate `default/frappe-mariadb`;
- mutate namespaces, CRDs, Nodes, operators, Traefik, TLS, or storage classes;
- access unapproved namespaces.

## Cleanup Behavior

Platform should delete command Jobs, request ConfigMaps, and terminal command
Pods after terminal state and evidence capture.

Pod cleanup contract:

- only after sanitized result capture;
- only in approved runtime namespaces;
- only Pods labelled `lenscloud.io/managed-by=platform`;
- only Pods labelled `lenscloud.io/resource-kind=bench-command`;
- only terminal Pods with phase `Succeeded` or `Failed`;
- no pod log reads;
- no Secret reads/lists;
- no default namespace cleanup.

The terminal Pod cleanup permission exists to prevent completed Bench Command
Pods from holding a Bench sites PVC through `kubernetes.io/pvc-protection`
after the owning Bench is deleted.

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
scripts/64-verify-cua-site-setup-runner.sh
```

Script number `56` is already used by Runtime Namespace registration, so the
Bench Command verifier uses `58`.
Terminal Pod cleanup verifier uses `63`.

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
Current v0.1.8 runner image: live-verified for CUA setup on 2026-07-06.
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
docs/bench-command-real-site-path-evidence-20260629.md
docs/bench-command-result-display-evidence-20260629.md
docs/bench-command-remaining-families-evidence-20260630.md
docs/evidence/cua/site-setup-runner-evidence-20260706.md
```

## Platform Agent Prompt

For CUA setup, Platform should use the dedicated handoff after Infra live proof:

```text
docs/handoffs/platform/cua-site-setup-runner-handoff-20260706.md
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/cua-site-setup-runner-20260706.md
```

`site_setup` may be enabled after Platform consumes the `INF-021` handoff and
keeps OAuth/user/site access commands unsupported.

Legacy Site Control prompt:

```text
Work inside lenscloud-platform.

Pull latest lenscloud-infra and start from:

- lenscloud-infra/docs/infra-workitems.md
- INF-017 Remaining Bench Command runner families
- lenscloud-infra/docs/platform-bench-command-handoff.md
- lenscloud-infra/docs/bench-command-remaining-families-evidence-20260630.md

Update Platform-side Site Control runtime enforcement against the current Infra
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

Infra runner source now implements maintenance mode, developer mode, approved
site_config keys, CORS allowlist, and metadata-only `backup.status`. The image
is published and admission-pinned. `maintenance_mode.enable`,
`maintenance_mode.status`, and `backup.status` have passed live verification
against the real Bench sites PVC.

Platform may integrate `backup.status` as a read/status action using the safe
top-level `display` object. Platform must continue to show `backup.create`,
restore commands, `bench_test.trigger`, and LATP commands as Unsupported until
Infra publishes a separate safe execution contract and live evidence.

Return:
- Platform files changed;
- request/response examples generated by Platform;
- action log evidence;
- `backup.status` display evidence;
- unsupported-command behavior;
- cleanup proof;
- remaining runner/API gaps.
```
