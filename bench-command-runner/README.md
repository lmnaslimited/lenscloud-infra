# LensCloud Bench Command Runner

This runner is the production-side implementation source for the Bench Command
Job/API contract.

## Architecture Position

The runner is an Infra-owned helper image. It is not a LensCloud Platform
Release Group image and it should not replace the customer Bench image.

Customer Benches continue to run their selected Release image, for example a
`lens-pure` or customer-specific Frappe image. Bench Command Jobs use this
runner image only as a controlled execution vehicle for approved operational
commands.

Platform consumes the runner through the documented Bench Command Job/API
contract after Infra has:

1. built and published the runner image;
2. pinned the digest in admission policy;
3. verified image pull access in the target cluster;
4. run live positive and negative command checks;
5. recorded cleanup and non-secret evidence.

Do not require every Release image to include this runner unless a future
architecture workitem explicitly changes the contract.

It is designed to run inside a Bench-compatible image with the target Bench
sites directory mounted at:

```text
/home/frappe/frappe-bench/sites
```

The runner supports both supported sites PVC layouts:

```text
/home/frappe/frappe-bench/sites/<site>/site_config.json
/home/frappe/frappe-bench/sites/frappe-sites/<site>/site_config.json
```

The Frappe Operator layout verified on 2026-06-29 is the second form:
`frappe-sites/<site>/site_config.json`.

Optional environment:

```text
BENCH_PATH=/home/frappe/frappe-bench
BENCH_SITES_PATH=/home/frappe/frappe-bench/sites
BENCH_COMMAND_REQUEST=/lenscloud/request/request.json
```

The runner:

- reads one request JSON file;
- validates command, target, and typed args;
- mutates only approved `site_config.json` keys for supported controls;
- returns sanitized JSON through the container termination log;
- returns a stable `display` object for supported read/status commands;
- does not use the Kubernetes API;
- does not require Kubernetes Secret mounts except for the approved
  `oauth.configure` client-secret file mount;
- does not print full environment dumps, DB passwords, tokens, or private keys.

Display contract:

```json
{
  "display": {
    "label": "Maintenance mode",
    "value": "Off",
    "kind": "boolean",
    "rawValue": 0,
    "safe": true
  }
}
```

Platform may render `display.value` only when `display.safe` is `true`.
Failed and unsupported commands do not include `display`.

Current implemented commands:

- `maintenance_mode.enable`
- `maintenance_mode.disable`
- `maintenance_mode.status`
- `developer_mode.enable`
- `developer_mode.disable`
- `developer_mode.status`
- `site_config.set`
- `site_config.unset`
- `site_config.get`
- `cors.allowlist.update`
- `cors.allowlist.get`
- `site_setup.status`
- `site_setup.complete`
- `oauth.status`
- `oauth.configure`
- `backup.status`

`backup.status` is metadata-only. It returns backup count/latest-file metadata
from the approved Site backup directory and never returns backup file contents.

Contracted but runner-pending commands return `Unsupported /
COMMAND_UNSUPPORTED`:

- `backup.create`
- `restore.preview`
- `restore.execute`
- `restore.status`
- `bench_test.trigger`
- `bench_test.status`
- `latp.trigger`
- `latp.status`
- `site_bootstrap.install_apps`
- `site_app.install`
- `bench.update`

Build example:

```bash
docker build \
  -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.12 \
  bench-command-runner
```

Current published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.11
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

The published digest above includes the local-dev OAuth HTTP gate for
`INF-026`. It still requires admission application and live verification with:

```bash
scripts/65-verify-cua-oauth-runner.sh
```

Cluster pull access must be verified in each runtime environment before
Platform enables newly implemented commands.

`v0.1.12` local build passed for `INF-027` with local image ID
`sha256:811df7d8594c5390b13eea1c2fb01c32e26f69c424312043e5dbbb2553b6ef7b`.
It has not been pushed to GHCR yet, so there is no immutable registry digest to
pin.

## App-Aware Release Group Commands

The generic `lenscloud-bench-command-runner` image must not execute app-aware
Release Group commands. The following commands are intentionally unsupported in
this runner:

- `site_bootstrap.install_apps`
- `site_app.install`
- `bench.update`

Those commands must run as direct Kubernetes Jobs inside the digest-pinned
Release Group runtime image, for example:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<digest>
```

See:

```text
docs/handoffs/platform/release-group-app-install-and-bench-upgrade-20260713.md
docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml
docs/testing/bench-command-runner/site_app_install_template.yaml
docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml
```

## OAuth Secret Boundary

`oauth.status` does not need a Secret mount.

`oauth.configure` requires the Platform OAuth client secret as a mounted file:

```text
/lenscloud/secrets/client_secret
```

The request ConfigMap must set:

```json
{"client_secret_source":"mounted_file"}
```

The request ConfigMap must not include `client_secret`. The runner rejects
direct `client_secret` args and returns only sanitized status fields such as
`secret_configured: true`.

## OAuth Local Dev Issuer

`oauth.configure` is HTTPS-only by default for `base_url`.

For local/dev CUA acceptance only, Platform may pass:

```json
{
  "base_url": "http://dev.localhost:8000",
  "allow_local_oauth_http": true
}
```

The runner accepts plain HTTP only when `allow_local_oauth_http` is a JSON
boolean `true` and `base_url` is loopback/local-dev: `localhost`,
`*.localhost`, or a loopback IP. Local HTTP is rejected when the flag is
missing or false, and non-local HTTP is always rejected.
