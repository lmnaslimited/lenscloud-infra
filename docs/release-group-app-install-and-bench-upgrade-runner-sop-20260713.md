# Release Group App Install And Bench Update Runtime-Image SOP

Date: 2026-07-16
Workitem: `INF-027`

This SOP supersedes the earlier app-aware `lenscloud-bench-command-runner`
model.

For `site_bootstrap.install_apps`, `site_app.install`, and `bench.update`, run
the Kubernetes Job inside the Release Group runtime image, not inside the
generic runner image.

The generic runner remains in use for existing non-app-aware Bench Commands.

Bench upgrades also depend on the Frappe Operator asset contract. The Release
runtime image must contain `/home/frappe/assets_cache/assets.json`, and the
operator-managed nginx Deployment must run the `assets-init` initContainer that
copies `/home/frappe/assets_cache/.` into the shared
`/home/frappe/frappe-bench/sites/assets` PVC mount before nginx starts.

## Preflight

1. Confirm the target Runtime Namespace is approved and labelled for Platform.
2. Confirm the admission policy is applied from
   `manifests/access/lenscloud-platform-rbac.yaml`.
3. Confirm Platform can read the cluster contract ConfigMap:

   ```bash
   kubectl --kubeconfig "$PLATFORM_KUBECONFIG" \
     -n lenscloud-platform-system get configmap \
     lenscloud-platform-cluster-contract \
     -o jsonpath='{.data.bench_command_runner_image}{"\n"}'
   ```

   This value is the canonical generic runner image for non-app-aware
   commands such as `site_setup.status`, `oauth.status`, and
   `oauth.configure`. Do not use the generic runner for
   `site_setup.complete`; setup completion can execute installed-app hooks and
   must use the Release Group runtime image digest.

4. Confirm the target Release Group runtime image is resolved to an immutable
   digest:

   ```text
   ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<64-hex-digest>
   ```

5. Confirm the test Bench and Site are disposable or explicitly approved.
6. Confirm `frappe` is not present in app install payloads.
7. Confirm the target app exists in the selected Release Group runtime image.
8. Confirm the Job sites PVC mount mirrors the Bench pod mount/subPath exactly.
9. Confirm the operator nginx Deployment has an `assets-init` initContainer
   after the Bench runtime image rollout.

## Local Verification

Run:

```bash
bash -n scripts/58-verify-platform-bench-command.sh
python3 - <<'PY'
from pathlib import Path
text = Path("manifests/access/lenscloud-platform-rbac.yaml").read_text()
assert "lensdocker/lens-pure@sha256" in text
assert "lenscloud-bench-command-runner" in text
assert "'site_bootstrap'," in text
assert "'site_app'," in text
assert "'bench'," in text
PY
```

Expected: no output and exit code `0`.

The generic runner source verifier may still be run to guard existing
non-app-aware behavior:

```bash
python3 -m py_compile bench-command-runner/runner.py
scripts/59-test-bench-command-runner-local.sh
```

## Admission Verification

On the manager VM:

```bash
export MANAGER_KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PLATFORM_KUBECONFIG=/secure/path/to/platform.kubeconfig
export RUNTIME_NAMESPACE=lenscloud-runtime-eu

scripts/58-verify-platform-bench-command.sh
```

Expected:

- `bench_test.status` still succeeds through the existing smoke exception.
- Platform can read the cluster contract ConfigMap and the configured runner
  digest is admitted for `site_setup.status`.
- A stale generic runner digest is denied with the admission message containing
  `approved execution image`.
- A digest-pinned `lensdocker/lens-pure` image is admitted for `bench.update`.
- The old generic runner image is denied for `bench.update`.
- Unlabelled Jobs are denied.
- Secret-volume Jobs are denied.
- Platform still cannot list/read Secrets or read pod logs.

## Live Positive Check: New Site App Install

Use:

```text
docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml
```

Required substitutions:

```bash
export TEST_NAME=rg-app-bootstrap-$(date -u +%Y%m%d%H%M%S)
export RUNTIME_NAMESPACE=lenscloud-runtime-eu
export RELEASE_GROUP_IMAGE='ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<digest>'
export REAL_SITE=<site-hostname>
export REAL_SITES_PVC=<bench-sites-pvc>
```

Before applying, edit the template so the `sites` mount/subPath matches the
target Bench pod. If the Bench pod does not use `subPath: frappe-sites`, remove
the `subPath` lines.

Expected:

- phase/job `Complete`;
- requested apps are installed in sorted `install_sequence` order;
- retry is idempotent or safely reports already-installed apps;
- no secrets are returned.

## Live Positive Check: Existing Site App Install

Use:

```text
docs/testing/bench-command-runner/site_app_install_template.yaml
```

Required substitutions:

```bash
export TEST_NAME=site-app-install-$(date -u +%Y%m%d%H%M%S)
export RUNTIME_NAMESPACE=lenscloud-runtime-eu
export RELEASE_GROUP_IMAGE='ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<digest>'
export REAL_SITE=<site-hostname>
export REAL_SITES_PVC=<bench-sites-pvc>
export INSTALL_APP=<release-group-app>
```

Before applying, edit the template so the `sites` mount/subPath matches the
target Bench pod.

The template renders the existing-Site command shape:

```bash
bench --site "$REAL_SITE" install-app "$INSTALL_APP"
```

Expected: app installed or safely skipped when already present.

## Live Positive Check: Bench Update

Use:

```text
docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml
```

Required substitutions:

```bash
export TEST_NAME=bench-update-$(date -u +%Y%m%d%H%M%S)
export RUNTIME_NAMESPACE=lenscloud-runtime-eu
export RELEASE_GROUP_IMAGE='ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<next-release-digest>'
export REAL_SITES_PVC=<bench-sites-pvc>
```

Before applying, edit the template so the `sites` mount/subPath matches the
target Bench pod.

Expected command sequence:

```bash
bench --site all set-config -p maintenance_mode 1
bench --site all set-config -p pause_scheduler 1
bench --site all migrate
bench --site all set-config -p maintenance_mode 0
bench --site all set-config -p pause_scheduler 0
```

Expected:

- target is Bench only, no Site;
- Job reaches `Complete`;
- `bench --site all migrate` runs from the `next_release` runtime image;
- operator rolls nginx with `assets-init` using the same Release runtime image;
- `assets-init` copies `/home/frappe/assets_cache/.` to
  `/home/frappe/frappe-bench/sites/assets/` on the shared assets PVC before
  nginx starts;
- maintenance mode and scheduler pause are returned to `0`.

After the runtime rollout, verify UI assets, not only root HTML:

```bash
curl -fsS "https://<site-hostname>" >/tmp/site.html
grep -o '/assets/[^"]*\\.css' /tmp/site.html | head -n 2
curl -fI "https://<site-hostname>/<generated-css-path-from-html>"
```

## Negative Checks

Verify rejection or denial for:

- mutable `lens-pure:<tag>` image in app-aware Job;
- old `lenscloud-bench-command-runner` image in app-aware Job;
- app payload containing `frappe`;
- invalid app identifier;
- duplicate app in one payload;
- app outside the Bench Release Group;
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
- request ConfigMap, if one was created;
- terminal Platform-labelled command Pod;
- temporary Secret, if any;
- test Bench/Site resources when disposable.

Do not read pod logs, Secret values, kubeconfig material, raw `site_config.json`,
passwords, private keys, or environment dumps for evidence.
