# Bench Command Job/API Evidence - 2026-06-25

## Scope

Infra workitem:

```text
INF-010 Bench Command Job/API for Site Controls
```

Platform requirement:

- Site Control Profile runtime enforcement must use an approved Bench Command
  Job/API.
- Platform must not invent unsupported `FrappeSite` CRD fields.

This evidence is non-secret. No kubeconfig, token, password, private key,
database credential, Kubernetes Secret value, or full environment dump is
included.

## Implemented Repo Artifacts

Contract:

```text
docs/platform-bench-command-handoff.md
```

Verification script:

```text
scripts/58-verify-platform-bench-command.sh
```

RBAC/admission source:

```text
manifests/access/lenscloud-platform-rbac.yaml
scripts/54-verify-platform-access.sh
scripts/56-register-platform-runtime-namespace.sh
```

Script number `56` is already used for Runtime Namespace registration, so the
Bench Command verifier is `58`.

## Contract Summary

Mode:

- Kubernetes API using request `ConfigMap` plus labelled `Job`.
- No Platform `kubectl` requirement.
- No invented `FrappeSite` fields.

Required labels:

```text
lenscloud.io/managed-by=platform
lenscloud.io/resource-kind=bench-command
lenscloud.io/resource-id=<platform-command-id>
```

Required annotations:

```text
lenscloud.io/bench-command-family=<family>
lenscloud.io/bench-command=<command>
lenscloud.io/bench-command-request=<request-configmap-name>
```

Admission guardrails for Platform-created command Jobs:

- approved runtime namespace only;
- approved command family only;
- one container;
- `restartPolicy: Never`;
- `backoffLimit <= 1`;
- no Kubernetes service-account token;
- no Secret volumes;
- no `envFrom`;
- non-privileged container.

## Supported Command Matrix

| Family | Commands | Current Status |
| --- | --- | --- |
| `backup` | `backup.create`, `backup.status` | `backup.status` live-verified by INF-017; `backup.create` runner-pending |
| `restore` | `restore.preview`, `restore.execute`, `restore.status` | Unsupported until restore runbook is finalized |
| `maintenance_mode` | `maintenance_mode.enable`, `maintenance_mode.disable`, `maintenance_mode.status` | Contracted, production runner pending |
| `developer_mode` | `developer_mode.enable`, `developer_mode.disable`, `developer_mode.status` | Contracted, production runner pending |
| `site_config` | `site_config.set`, `site_config.unset`, `site_config.get` | Contracted for approved keys only, production runner pending |
| `cors` | `cors.allowlist.update`, `cors.allowlist.get` | Contracted where supported, production runner pending |
| `bench_test` | `bench_test.trigger`, `bench_test.status` | Verification stub for `bench_test.status`; production runner pending |
| `latp` | `latp.trigger`, `latp.status` | Contracted, production runner pending |

2026-06-30 status update: INF-017 moved metadata-only `backup.status` to
live-verified. `backup.create`, restore, Bench Test trigger, and LATP remain
runner-pending. See
[bench-command-remaining-families-evidence-20260630.md](./bench-command-remaining-families-evidence-20260630.md).

2026-07-02 status update: INF-019 added live-verified cleanup for terminal
Platform-labelled Bench Command Pods. Platform can delete only terminal Pods
labelled `lenscloud.io/managed-by=platform` and
`lenscloud.io/resource-kind=bench-command` in approved runtime namespaces. Pod
logs, unlabelled/running Pod deletion, default namespace cleanup, and Secret
listing remain denied. See
[bench-command-pod-cleanup-rbac-evidence-20260702.md](./bench-command-pod-cleanup-rbac-evidence-20260702.md).

Unsupported behavior:

- Known but unavailable commands return `Unsupported` with
  `COMMAND_UNSUPPORTED`.
- Platform must show unsupported runtime enforcement truthfully.

## Repo-Side Validation

Shell syntax:

```text
bash -n scripts/54-verify-platform-access.sh scripts/56-register-platform-runtime-namespace.sh scripts/58-verify-platform-bench-command.sh
```

Result:

```text
passed
```

YAML parse:

```text
ruby -e 'require "yaml"; YAML.load_stream(File.read("manifests/access/lenscloud-platform-rbac.yaml")); puts "yaml ok"'
```

Result:

```text
yaml ok
```

## Live Verification Status

Live verification completed on 2026-06-25 against runtime namespace:

```text
lenscloud-runtime-eu
```

RBAC/admission apply summary:

```text
role.rbac.authorization.k8s.io/lenscloud-platform-runtime configured
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create created
validatingadmissionpolicybinding.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create created
```

The standard Platform access verifier passed:

```text
mariadb.k8s.mariadb.com/frappe-mariadb
true platform
No resources found in lenscloud-runtime-eu namespace.
Restricted LensCloud Platform RBAC verification passed for lenscloud-runtime-eu.
```

## Verification Commands Run

From the live manager:

```bash
cd /root/lenscloud-infra
kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml

PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
./scripts/54-verify-platform-access.sh

PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
./scripts/58-verify-platform-bench-command.sh
```

Bench Command verifier output summary:

```text
configmap/run-20260625-1335-bench-command-request created
job.batch/run-20260625-1335-bench-command-positive created
job.batch/run-20260625-1335-bench-command-positive condition met
job.batch "run-20260625-1335-bench-command-positive" deleted from lenscloud-runtime-eu namespace
configmap "run-20260625-1335-bench-command-request" deleted from lenscloud-runtime-eu namespace
Bench Command Job/API RBAC verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive command family: bench_test
Sanitized result summary: present
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod log read: denied
Unapproved namespace and default namespace creation: denied
```

## Cleanup Proof

Temporary resources used by the verifier:

```text
ConfigMap/lenscloud-runtime-eu/run-20260625-1335-bench-command-request
Job/lenscloud-runtime-eu/run-20260625-1335-bench-command-positive
```

Cleanup verification:

```bash
kubectl -n lenscloud-runtime-eu get job,configmap,pod --ignore-not-found |
  grep run-20260625-1335-bench-command || true
```

Result:

```text
no matching run-20260625-1335-bench-command resources remained
```

It does not delete:

```text
MariaDB/default/frappe-mariadb
PVC/default/storage-frappe-mariadb-0
operators
namespaces
Traefik/TLS/Certbot resources
```

Protected baseline verification:

```text
MariaDB/default/frappe-mariadb Ready / Running
ValidatingAdmissionPolicy/lenscloud-platform-bench-command-job-create present
ValidatingAdmissionPolicyBinding/lenscloud-platform-bench-command-job-create present
```

## RBAC Proof

The verifier proved:

Positive:

- create/get/delete ConfigMaps in approved runtime namespace;
- create/get/list/watch/delete Jobs in approved runtime namespace;
- list Pod status for sanitized termination summary.

Negative:

- no Secret listing;
- no pod log read access;
- no Job/ConfigMap creation in `default`;
- no Job creation in unapproved namespaces;
- no namespace mutation;
- admission rejects unlabelled Jobs;
- admission rejects Secret-volume Jobs;
- admission rejects unsafe Job shapes.

Direct negative RBAC checks after verification:

```text
get pods/log in lenscloud-runtime-eu: no
list secrets in lenscloud-runtime-eu: no
create jobs.batch in default: no
create configmaps in default: no
```

## Remaining Production Gaps

- Production bench-command runner image/API is not yet published.
- Actual `bench --site` execution for backup, restore, maintenance mode,
  developer mode, site config, CORS, Bench Test, and LATP remains runner/API
  work.
- Restore needs a signed destructive-operation runbook before enablement.
- Backup result storage and retention contract must be finalized.
- Per-command typed argument schema should be versioned in Platform and runner
  together.
- NetworkPolicy and resource quotas for command Jobs remain production
  hardening items.
