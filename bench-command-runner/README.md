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

Build example:

```bash
docker build \
  -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.9 \
  bench-command-runner
```

Published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

The published digest above includes the OAuth runner source. It still requires
admission application and live verification with:

```bash
scripts/65-verify-cua-oauth-runner.sh
```

Cluster pull access must be verified in each runtime environment before
Platform enables newly implemented commands.

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
