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
| `backup` | `backup.create`, `backup.status` | Contracted, production runner pending |
| `restore` | `restore.preview`, `restore.execute`, `restore.status` | Unsupported until restore runbook is finalized |
| `maintenance_mode` | `maintenance_mode.enable`, `maintenance_mode.disable`, `maintenance_mode.status` | Contracted, production runner pending |
| `developer_mode` | `developer_mode.enable`, `developer_mode.disable`, `developer_mode.status` | Contracted, production runner pending |
| `site_config` | `site_config.set`, `site_config.unset`, `site_config.get` | Contracted for approved keys only, production runner pending |
| `cors` | `cors.allowlist.update`, `cors.allowlist.get` | Contracted where supported, production runner pending |
| `bench_test` | `bench_test.trigger`, `bench_test.status` | Verification stub for `bench_test.status`; production runner pending |
| `latp` | `latp.trigger`, `latp.status` | Contracted, production runner pending |

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

Live apply and verification were attempted through the normal manager path, but
the execution approval guard blocked the change because it broadens the
Platform service-account authority on live infrastructure.

No workaround was attempted.

No live RBAC, admission policy, Job, Pod, ConfigMap, Secret, PVC, namespace, or
operator resource was changed by this pass.

## Verification Command To Run After Approval

From the live manager or approved Infra admin path:

```bash
cd /root/lenscloud-infra
git pull --ff-only

kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml

PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
./scripts/54-verify-platform-access.sh

PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu.kubeconfig \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
./scripts/58-verify-platform-bench-command.sh
```

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

## Cleanup Proof

No live temporary resources were created in this pass because the live apply was
blocked before verification.

The verification script uses a `run-YYYYMMDD-HHMM-bench-command` prefix and
registers a cleanup trap for:

- test Jobs;
- test request ConfigMap;
- unowned negative-test ConfigMap.

It does not delete:

```text
MariaDB/default/frappe-mariadb
PVC/default/storage-frappe-mariadb-0
operators
namespaces
Traefik/TLS/Certbot resources
```

## RBAC Proof Pending Live Run

The verifier is designed to prove:

Positive:

- create/get/delete ConfigMaps in approved runtime namespace;
- create/get/list/watch/delete Jobs in approved runtime namespace;
- read Pod status for sanitized termination summary.

Negative:

- no Secret listing;
- no pod log access;
- no Job/ConfigMap creation in `default`;
- no Job creation in unapproved namespaces;
- no namespace mutation;
- admission rejects unlabelled Jobs;
- admission rejects Secret-volume Jobs;
- admission rejects unsafe Job shapes.

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
