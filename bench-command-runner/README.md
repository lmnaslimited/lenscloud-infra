# LensCloud Bench Command Runner

This runner is the production-side implementation source for the Bench Command
Job/API contract.

It is designed to run inside a Bench-compatible image with the target Bench
sites directory mounted at:

```text
/home/frappe/frappe-bench/sites
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
  -t ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.0 \
  bench-command-runner
```

Published image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:c3e0922ca034c840ebd06c29b52794fec54c655b62444df60393f2ed5501d920
```

The live admission policy accepts this digest for production Bench Command Jobs.
Cluster pull access must be verified in each runtime environment before Platform
enables the implemented commands.
