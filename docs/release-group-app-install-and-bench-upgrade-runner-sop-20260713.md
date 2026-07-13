# Release Group App Install And Bench Update Runner SOP

Date: 2026-07-13
Workitem: `INF-027`

Use this SOP only after a new runner image is built and published from the
current `bench-command-runner/` source.

## Preflight

1. Confirm the target Runtime Namespace is approved and labelled for Platform.
2. Confirm the admission policy allows the new runner digest and command
   families `site_bootstrap`, `site_app`, and `bench`.
3. Confirm the test Bench and Site are disposable or explicitly approved.
4. Confirm `frappe` is not present in app install payloads.
5. Confirm the base Frappe Site already exists before app install commands run.

## Local Source Verification

Run:

```sh
python3 -m py_compile bench-command-runner/runner.py
scripts/59-test-bench-command-runner-local.sh
```

Expected:

```text
Bench command runner local verification passed.
```

## Live Positive Checks

Run `site_bootstrap.install_apps` against a real test Site:

```json
{
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
```

Expected:

- phase `Succeeded`;
- `attempted_apps` preserves submitted order;
- `installed_apps` names newly installed apps;
- `skipped_apps` names already-installed apps;
- `failed_app` is null;
- no secrets are returned.

Retry the same request. Expected:

- phase `Succeeded`;
- already-installed apps are in `skipped_apps`;
- command is idempotent.

Run `site_app.install` against an existing Ready/Active test Site:

```json
{
  "apps": [
    {
      "app": "payments",
      "install_sequence": 30
    }
  ]
}
```

Expected: app installed or safely skipped.

Run `bench.update` against a test Bench after Platform-side gates are satisfied:

```json
{
  "target_release": "v16.14.2"
}
```

Expected:

- target has Bench only, no Site;
- phase `Succeeded`;
- operation reports `bench --site all migrate`;
- target Release is echoed safely.

## Negative Checks

Verify rejection or denial for:

- app payload containing `frappe`;
- invalid app identifier;
- duplicate app in one payload;
- `bench.update` target containing a Site;
- wrong namespace;
- wrong Bench;
- wrong Site;
- invalid command;
- unsafe Job shape;
- Secret access;
- pod-log access;
- Secret mount on non-OAuth commands.

## Cleanup Proof

After each live command, prove absence or deletion of:

- command Job;
- request ConfigMap;
- terminal Platform-labelled command Pod;
- temporary Secret, if any;
- runner artifacts.

Do not read pod logs, Secret values, kubeconfig material, raw `site_config.json`,
passwords, private keys, or environment dumps for evidence.
