# Release Group App Install And Bench Upgrade Runner Evidence

Date: 2026-07-13
Workitem: `INF-027`

## Scope

Infra runner source and admission family support for:

- `site_bootstrap.install_apps`
- `site_app.install`
- `bench.update`

## Source Changes

- `bench-command-runner/runner.py`
  - adds the three commands to the runner allowlist;
  - validates ordered app batches;
  - rejects `frappe` as an install app;
  - skips already-installed apps idempotently;
  - runs app install through Frappe installer APIs in the target Site context;
  - supports bench-only `bench.update` requests without a Site target;
  - runs `bench --site all migrate` for Bench update in the Bench context;
  - returns sanitized result details and display payloads.
- `manifests/access/lenscloud-platform-rbac.yaml`
  - admits `site_bootstrap`, `site_app`, and `bench` Bench Command families
    using the existing runner/admission guardrails.
- `scripts/59-test-bench-command-runner-local.sh`
  - verifies ordered app install, idempotent retry, existing Site install,
    `frappe` rejection, bench-only update, and rejection of a Site target on
    `bench.update`.

## Positive Local Evidence

Commands run:

```sh
python3 -m py_compile bench-command-runner/runner.py
scripts/59-test-bench-command-runner-local.sh
docker build --platform linux/amd64 -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.12 bench-command-runner
docker image inspect ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.12 --format '{{.Id}} {{json .RepoDigests}}'
```

Result:

```text
Bench command runner local verification passed.
Local image ID: sha256:811df7d8594c5390b13eea1c2fb01c32e26f69c424312043e5dbbb2553b6ef7b
RepoDigests: []
```

Positive coverage:

- `site_bootstrap.install_apps` installed `erpnext`, then `hrms` in submitted order;
- retry of the same bootstrap command skipped both already-installed apps;
- `site_app.install` installed `payments`;
- `bench.update` accepted a Bench-only target and returned `target_release`;
- existing secret-safety grep remained active across all new commands.

## Negative Local Evidence

Verified:

- `site_app.install` rejects `frappe`;
- `bench.update` rejects a target containing `site`;
- existing sensitive-output grep did not find DB password, OAuth secret,
  token, private key, or secret field names in termination summaries.

## Cleanup Evidence

Local verification uses a temporary directory created by `mktemp -d` and removes
it on exit. No cluster resources are created by the local run.

Live cleanup evidence remains pending for:

- command Job;
- request ConfigMap;
- terminal Platform-labelled command Pod;
- temporary Secret, if any future command variant needs one;
- runner artifacts.

## Secret-Safety Proof

New request payloads carry only:

- stable app identifiers;
- optional `install_sequence` integers;
- target Release identifier for `bench.update`.

The runner never returns kubeconfig content, passwords, Secret values, private
keys, raw `site_config.json`, pod logs, or environment dumps. Failed app install
returns only `failed_app`, integer `exit_code`, and a sanitized short
`error_excerpt`.

## Image Publish And Digest Pin Status

Local image build for `v0.1.12` passed. Registry publish was not performed in
this run because the approval reviewer rejected `docker buildx build --push` as
external data export to GHCR. Without a registry push there is no immutable
`ghcr.io/...@sha256:<digest>` RepoDigest to pin in admission.

## Live Evidence Pending

Still required before completion:

- publish the `v0.1.12` runner image;
- pin the new digest in admission policy;
- apply admission update to the test cluster;
- prove positive ordered app install on a real Site;
- prove idempotent app install retry;
- prove existing Site app install;
- prove `bench.update` against an approved target Bench;
- prove rejection of wrong namespace, wrong Bench, wrong Site, invalid command,
  unsafe Job shape, Secret access, and pod-log access;
- prove cleanup of Jobs, ConfigMaps, terminal Pods, temporary Secrets if any,
  and runner artifacts.
