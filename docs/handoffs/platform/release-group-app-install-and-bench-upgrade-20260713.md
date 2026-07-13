# Platform Handoff: Release Group App Install And Bench Upgrade Runner

Date: 2026-07-13
Infra workitem: `INF-027`

## Status

Infra runner source support is implemented and locally verified.

Local runner image build passed for:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.12
local image ID: sha256:811df7d8594c5390b13eea1c2fb01c32e26f69c424312043e5dbbb2553b6ef7b
```

The image was not pushed to GHCR in this run because the approval reviewer
rejected registry publish as external data export. Since the image was not
pushed, there is no immutable registry RepoDigest to pin yet.

The currently pinned production digest remains:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

Do not treat the new commands as live-cluster verified until Infra publishes,
pins, applies, and proves a new runner image.

## Commands

| Flow | Command | Target |
| --- | --- | --- |
| New Site bootstrap app install | `site_bootstrap.install_apps` | Bench + Site |
| Existing Site app install | `site_app.install` | Bench + Site |
| Bench update/migration | `bench.update` | Bench only |

## Request Schemas

New Site bootstrap:

```json
{
  "command": "site_bootstrap.install_apps",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "bench-name",
    "site": "customer-site.example"
  },
  "args": {
    "install_apps": [
      {
        "app": "erpnext",
        "install_sequence": 20
      },
      {
        "app": "hrms",
        "install_sequence": 30
      }
    ]
  }
}
```

Existing Site install:

```json
{
  "command": "site_app.install",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "bench-name",
    "site": "customer-site.example"
  },
  "args": {
    "apps": [
      {
        "app": "payments",
        "install_sequence": 30
      }
    ]
  }
}
```

Bench update:

```json
{
  "command": "bench.update",
  "target": {
    "namespace": "lenscloud-runtime-eu",
    "bench": "bench-name"
  },
  "args": {
    "target_release": "v16.14.2"
  }
}
```

## Response Schemas

App install:

```json
{
  "phase": "Succeeded",
  "summary": "Installed requested apps",
  "details": {
    "attempted_apps": ["erpnext", "hrms"],
    "installed_apps": ["erpnext"],
    "skipped_apps": ["hrms"],
    "failed_app": null,
    "exit_code": 0,
    "error_excerpt": null
  },
  "redacted": true
}
```

Idempotent retry:

```json
{
  "phase": "Succeeded",
  "summary": "All requested apps already installed",
  "details": {
    "attempted_apps": ["erpnext", "hrms"],
    "installed_apps": [],
    "skipped_apps": ["erpnext", "hrms"],
    "failed_app": null,
    "exit_code": 0
  },
  "redacted": true
}
```

Bench update:

```json
{
  "phase": "Succeeded",
  "summary": "Bench update completed",
  "details": {
    "target_release": "v16.14.2",
    "operation": "bench --site all migrate",
    "exit_code": 0,
    "error_excerpt": null
  },
  "redacted": true
}
```

## Supported / Unsupported Matrix

New source-supported commands:

- `site_bootstrap.install_apps`
- `site_app.install`
- `bench.update`

Still unsupported:

- `backup.create`
- `restore.preview`
- `restore.execute`
- `restore.status`
- `bench_test.trigger`
- `latp.trigger`
- `latp.status`
- `user.ensure`
- `user.disable`
- `user.roles.set`
- `site_access.status`

## Admission And RBAC

Updated admission source allows Bench Command families:

- `site_bootstrap`
- `site_app`
- `bench`

Existing guardrails remain:

- approved runtime namespace only;
- pinned runner image only;
- one container;
- no service-account token;
- no `envFrom`;
- no privileged container;
- no Secret mounts for these non-OAuth commands;
- no Secret reads/lists;
- no pod-log access;
- terminal pod cleanup only for Platform-labelled Bench Command Pods.

Live rejection evidence is still pending for wrong namespace, wrong Bench, wrong
Site, invalid command, unsafe Job shape, Secret access, and pod-log access.

## Platform Integration Prompt

Platform should:

- derive `site_bootstrap.install_apps` from Release Group child rows where
  `install_at_site_creation` is checked;
- exclude `frappe`;
- sort by ascending `install_sequence`, with empty values last;
- send stable app identifiers, not display labels;
- call `site_app.install` only for apps included in the Bench Release Group;
- require `upgrade_tested`, `tested_on`, and `tested_by` before marking a Site
  `upgrade_state = Scheduled`;
- require every active Site on the Bench to be Scheduled before `bench.update`;
- require target Release to belong to the Bench Release Group;
- surface attempted, installed, skipped, failed app, exit code, sanitized error
  excerpt, target Release, and cleanup status.

## Evidence

Local source evidence:

```text
docs/release-group-app-install-and-bench-upgrade-evidence-20260713.md
```

Commands passed:

```sh
python3 -m py_compile bench-command-runner/runner.py
scripts/59-test-bench-command-runner-local.sh
```

Remaining Infra gaps:

- new runner image publish;
- new digest pin in admission;
- live ordered app install proof;
- live idempotent retry proof;
- live existing Site app install proof;
- live Bench update proof;
- live cleanup and secret-safety proof.
