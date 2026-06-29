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
- does not use the Kubernetes API;
- does not require Kubernetes Secret mounts;
- does not print full environment dumps, DB passwords, tokens, or private keys.

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

Contracted but runner-pending commands return `Unsupported /
COMMAND_UNSUPPORTED`:

- `backup.create`
- `backup.status`
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
  -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.1 \
  bench-command-runner
```

Published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3c322afc631b7db49759059c6706a3f42668cfbf5017ee66b3f4c26d9235c49e
```

The live admission policy accepts this digest for production Bench Command Jobs.
Cluster pull access must be verified in each runtime environment before Platform
enables the implemented commands.
