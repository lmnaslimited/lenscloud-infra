# Release Group App Install And Bench Upgrade Evidence

Date: 2026-07-16
Workitem: `INF-027`

## Scope

Infra corrected app-aware Bench Command execution for:

- `site_bootstrap.install_apps`
- `site_app.install`
- `bench.update`

The final model is Release Group runtime-image execution. These commands must
run inside the target Release Group runtime image, for example:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<64-hex-digest>
```

The generic `lenscloud-bench-command-runner` image remains the execution path
for existing non-app-aware Bench Command families.

## Why The Model Changed

Live testing showed that using the generic runner image for `bench.update`
fails when the target Release Group image contains apps that are not present in
the runner image. The concrete failure was a `brandkit` import failure while
updating to a runtime image that contained `brandkit`.

That proved the runner image was carrying app composition, which is the wrong
architecture. App composition belongs to the Release Group runtime image and
Platform Release Group data.

## Source Changes

- `manifests/access/lenscloud-platform-rbac.yaml`
  - keeps existing generic runner admission for non-app-aware command
    families;
  - allows app-aware families `site_bootstrap`, `site_app`, and `bench` only
    with digest-pinned `ghcr.io/lmnaslimited/lensdocker/lens-pure` images;
  - keeps the existing `bench_test.status` busybox smoke exception;
  - keeps existing guardrails for one container, no service-account token, no
    `envFrom`, non-privileged execution, and Secret-volume denial except the
    OAuth client-secret exception.
- `scripts/58-verify-platform-bench-command.sh`
  - adds server-side dry-run verification that a digest-pinned runtime image is
    admitted for `bench.update`;
  - adds denial verification that the old runner image is not admitted for
    app-aware `bench.update`;
  - adds denial verification that mutable `lens-pure:<tag>` images are not
    admitted for app-aware commands;
  - keeps existing positive `bench_test.status`, RBAC, Secret, pod-log, and
    unsafe-Job checks.
- `docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml`
  - now renders a runtime-image app install Job.
- `docs/testing/bench-command-runner/site_app_install_template.yaml`
  - adds the explicit existing-Site runtime-image app install Job.
- `docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml`
  - adds the runtime-image Bench update Job equivalent to the Swarm migration
    service.
- `docs/test-cluster-build-handoff-sop.md`
  - documents the two execution paths and Release Group runtime-image
    enablement.
- `docs/handoffs/platform/release-group-app-install-and-bench-upgrade-20260713.md`
  - gives Platform the implementation contract.
- `../lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/release-group-app-install-and-bench-upgrade-20260713.md`
  - mirrors the Platform handoff in the Platform app docs.

## Local Verification

Commands run:

```bash
bash -n scripts/58-verify-platform-bench-command.sh
python3 -m py_compile bench-command-runner/runner.py
scripts/59-test-bench-command-runner-local.sh
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_stream(File.read(f)); puts "ok #{f}" }' \
  manifests/access/lenscloud-platform-rbac.yaml \
  docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml \
  docs/testing/bench-command-runner/site_app_install_template.yaml \
  docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml
```

Results:

```text
Bench command runner local verification passed.
ok manifests/access/lenscloud-platform-rbac.yaml
ok docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml
ok docs/testing/bench-command-runner/site_app_install_template.yaml
ok docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml
```

Regression coverage preserved:

- maintenance mode enable/status;
- developer mode enable/status;
- site config set/get;
- CORS allowlist update/get;
- backup status and unsupported backup/restore paths;
- site setup status/complete/idempotent behavior;
- OAuth configure/status and local-dev issuer validation;
- sensitive-output redaction checks;
- app-aware commands `site_bootstrap.install_apps`, `site_app.install`, and
  `bench.update` now return `COMMAND_UNSUPPORTED` in the generic runner.

## Live Verification

Applied on the manager cluster on 2026-07-16:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply \
  -f manifests/access/lenscloud-platform-rbac.yaml
```

Apply result included:

```text
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create configured
```

Live verifier run:

```bash
scripts/58-verify-platform-bench-command.sh
```

Result:

```text
Bench Command Job/API RBAC verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive command family: bench_test
Sanitized result summary: present
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
Negative unlabelled Job: denied
Negative Secret volume Job: denied
Secret listing and pod log read: denied
Unapproved namespace and default namespace creation: denied
```

Live proof:

- existing `bench_test.status` behavior still works;
- digest-pinned `lensdocker/lens-pure` image is admitted for app-aware
  `bench.update`;
- old generic runner image is denied for app-aware `bench.update`;
- mutable `lens-pure:<tag>` image is denied for app-aware `bench.update`;
- unlabelled Job is denied;
- Secret-volume Job is denied;
- Platform cannot list/read Secrets;
- Platform cannot read pod logs;
- default/unapproved namespace creation remains denied.

## Runtime-Image E2E Verification

Disposable E2E resources:

```text
Bench: run-20260716-e2e-update-132858-bench
Site:  run-20260716-e2e-update-132858-site.cloud.lmnaslens.com
Namespace: lenscloud-runtime-eu
```

Image digests used by Platform-created command Jobs:

```text
v16.14.2: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:fb788e482326f49e93bf7aee96f606a8f6f347d55ba6412943da7d8ea6afa276
v16.14.3: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
```

Completed E2E sequence:

1. Created a disposable Bench with `lens-pure:v16.14.2`.
2. Created a disposable Site on that Bench and waited for `Ready`.
3. Ran `site_bootstrap.install_apps` through the restricted Platform
   kubeconfig using the v16.14.2 runtime digest.
4. Installed `erpnext` successfully.
5. Ran `bench.update` through the restricted Platform kubeconfig using the
   v16.14.3 runtime digest.
6. Bench-wide migration completed successfully with:

   ```bash
   bench --site all set-config -p maintenance_mode 1
   bench --site all set-config -p pause_scheduler 1
   bench --site all migrate
   bench --site all set-config -p maintenance_mode 0
   bench --site all set-config -p pause_scheduler 0
   ```

7. Verified `maintenance_mode=0` and `pause_scheduler=0`.
8. Patched the disposable `FrappeBench` runtime image tag to `v16.14.3` and
   verified gunicorn, nginx, scheduler, socketio, and worker deployments use
   `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3`.
9. Verified mounted assets matched the v16.14.3 image cache:

   ```text
   cache_assets_json_sha256=2b9035b4dfc942a5e456c3d89cccacb3eb9eb77320e4e93bfafc337314261284
   mounted_assets_json_sha256=2b9035b4dfc942a5e456c3d89cccacb3eb9eb77320e4e93bfafc337314261284
   brandkit_cache_dir_exists=1
   brandkit_mounted_dir_exists=1
   ```

10. Verified `brandkit` mounted asset files exist.
11. Fetched a concrete brandkit asset through the Site URL:

    ```text
    /assets/brandkit/js/demo_banner.js
    final HTTP status after redirect: 200
    body size: 12311 bytes
    ```

12. Ran `site_app.install` through the restricted Platform kubeconfig using
    the v16.14.3 runtime digest.
13. Installed `brandkit` successfully. Final `list-apps` output included:

    ```text
    frappe
    erpnext
    brandkit
    ```

Remaining Platform implementation requirement:

- wire `site_bootstrap.install_apps` into first-time Site bootstrap immediately
  after the base Site exists and before customer handoff;
- after `bench.update` succeeds, update the Bench runtime image to the
  `next_release`, wait for deployment rollout, verify assets are fresh, then
  allow newly available app installs such as `brandkit`.

Manual app-aware live checks for future clusters:

- New Site bootstrap installs ordered Release Group apps.
- Retrying the same app install is idempotent or safely skipped.
- Existing Site app install works only for apps in the Bench Release Group.
- Bench update runs:

  ```bash
  bench --site all set-config -p maintenance_mode 1
  bench --site all set-config -p pause_scheduler 1
  bench --site all migrate
  bench --site all set-config -p maintenance_mode 0
  bench --site all set-config -p pause_scheduler 0
  ```

- Bench update uses the `next_release` runtime image digest.
- Bench release pointers move only after Job success.

## Cleanup Evidence

Local verification uses temporary directories created by `mktemp -d` and
removes them on exit. No cluster resources are created by the local run.

Live cleanup evidence remains required for:

- command Jobs;
- request ConfigMaps, if created;
- terminal Platform-labelled command Pods;
- temporary Secrets, if any;
- disposable test Bench/Site resources.

## Secret-Safety Proof

The runtime-image Job model must not expose kubeconfig content, passwords,
Secret values, private keys, raw `site_config.json`, pod logs, full logs, or
environment dumps. Platform result mapping may include only sanitized status,
exit code, target release/app names, and short sanitized error excerpts.
