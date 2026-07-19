# Platform Handoff: Bench Upgrade Assets And Runner Digest Contract

Date: 2026-07-19
Infra incidents: `INC-20260719-001`, `INC-20260719-002`
Source infra handoff:
`docs/handoffs/infra/bench-upgrade-assets-and-runner-digest-20260719.md`

## Decision

Use upstream Frappe Operator `v4.1.1` for the Bench upgrade asset fix.

Infra proved `v4.1.1` on the manager cluster with a disposable end-to-end test:

- live operator manager image:
  `ghcr.io/vyogotech/frappe-operator:4.1.1`;
- test Bench:
  `run-20260719-v411-072443-bench`;
- test Site:
  `run-20260719-v411-072443-site.cloud.lmnaslens.com`;
- initial Bench runtime image:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.2`;
- migration Job runtime image:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0`;
- final Bench runtime image:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3`;
- final `FrappeBench.status.initializedImage`:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3`;
- migration Job completed with pod exit code `0`;
- upgraded Site root returned HTTP `200`;
- upgraded CSS asset returned HTTP `200`:
  `/assets/frappe/dist/css/website.bundle.JTHFRTK2.css`;
- nginx PVC had non-empty
  `/home/frappe/frappe-bench/sites/assets/assets.json`.

No custom LensCloud operator image is required for this incident if target
clusters are upgraded to upstream `v4.1.1` and Bench runtime images use new
immutable version tags.

Keep the `lmnaslimited/frappe-operator` fork only as the fallback path for
future LensCloud-specific patches or if digest-pinned Bench CR image support is
required later.

## Why v4.1.1 Fixes Assets

`v4.1.1` records the Bench image that successfully initialized assets in:

```text
FrappeBench.status.initializedImage
```

When `spec.imageConfig.repository:tag` changes, the operator recreates the
Bench init Job. That init Job syncs bundled release assets from the runtime
image cache into the shared Sites PVC:

```text
source:      /home/frappe/assets_cache
destination: /home/frappe/frappe-bench/sites/assets
```

This matches the release image build behavior from the Frappe Docker custom
Containerfile: app assets are built into `/home/frappe/assets_cache`, and the
operator copies them to the path nginx serves.

## Platform Bench Upgrade Flow

For a Bench release upgrade, Platform must keep the same operational shape as
the existing Swarm migration flow:

1. Ensure every Site on the Bench is scheduled and tested for the target
   release.
2. Run an app-aware `bench.update` Job with the target Release Group runtime
   image digest.
3. The command must run the whole Bench migration, not per-site migrations:

   ```bash
   cd /home/frappe/frappe-bench
   bench --site all set-config maintenance_mode 1
   bench --site all set-config pause_scheduler 1
   bench --site all migrate
   bench --site all set-config maintenance_mode 0
   bench --site all set-config pause_scheduler 0
   ```

4. Patch the `FrappeBench` runtime image to the new immutable version tag.
5. Wait for the Bench Deployments to roll out.
6. Wait until:

   ```text
   FrappeBench.status.initializedImage == <repository>:<new_tag>
   ```

7. Verify assets before marking the Bench or Site UI ready.

Platform must not update the contents behind an existing Bench runtime tag and
expect the operator to detect a change. Publish a new version tag for every
Release Group runtime change, for example:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.4
```

## Platform Asset Readiness Rule

After `bench.update` succeeds and Platform patches the Bench runtime image,
Platform must wait for operator asset initialization and then verify:

1. Site root HTML returns HTTP `200`.
2. Current HTML contains generated `/assets/...css` and `/assets/...js`
   references.
3. Representative generated CSS and JS URLs from the current HTML return
   HTTP `200`.
4. Only then mark the upgraded Bench/Site UI ready.

Root HTML `200` alone is not enough.

For the reported production incident Sites, re-check current generated asset
URLs after the operator upgrade. The originally reported examples were:

```text
https://tharahub.cloud.lmnaslens.com/assets/frappe/dist/css/website.bundle.D4ZWF75O.css
https://tharahub.cloud.lmnaslens.com/assets/erpnext/dist/css/erpnext-web.bundle.QMNL65W2.css
https://brandkite2e0717.cloud.lmnaslens.com/assets/frappe/dist/css/website.bundle.D4ZWF75O.css
https://brandkite2e0717.cloud.lmnaslens.com/assets/erpnext/dist/css/erpnext-web.bundle.QMNL65W2.css
```

Use fresh URLs parsed from current HTML as the source of truth.

## Runner Digest Contract

Generic, non-app-aware Bench Commands still use the generic runner image.
Platform must not hardcode it in code. Read it from the cluster contract:

```text
namespace: lenscloud-platform-system
name: lenscloud-platform-cluster-contract
key: bench_command_runner_image
```

Command:

```bash
kubectl --kubeconfig "$PLATFORM_KUBECONFIG" \
  -n lenscloud-platform-system get configmap \
  lenscloud-platform-cluster-contract \
  -o jsonpath='{.data.bench_command_runner_image}{"\n"}'
```

The value must match:

```text
^ghcr\.io/lmnaslimited/lenscloud-bench-command-runner@sha256:[0-9a-f]{64}$
```

Current admitted runner digest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

This digest is cluster-level. It is not per Runtime Namespace, not per Release
Group, and does not need to match the Bench runtime release.

Before creating any live generic Bench Command Job, Platform must run a
server-side dry-run using the exact generated Job manifest. If dry-run is
denied and the admission message contains `approved execution image`, return:

```text
code: BENCH_COMMAND_RUNNER_IMAGE_REJECTED
operator_message: Bench Command runner image is not admitted by this cluster.
customer_message: Site setup is waiting for cluster configuration. Please retry after support resolves it.
```

Diagnostics may include the configured runner digest and Kubernetes admission
message. Do not expose kubeconfig, tokens, Secrets, or pod logs.

## Image Choice By Command Family

Use the generic runner digest only for non-app-aware command families, including:

```text
site_setup.status
oauth.status
oauth.configure
maintenance_mode.*
developer_mode.*
site_config.*
cors.*
backup/restore status-style commands
latp
```

Use the digest-pinned Release Group runtime image for app-aware commands:

```text
site_bootstrap.install_apps
site_app.install
bench.update
site_setup.complete
```

Required shape:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<release-digest>
```

Do not use the generic runner for app-aware commands. `site_setup.complete` is
app-aware because Frappe setup completion can execute installed-app setup hooks.
Do not use mutable runtime tags in Platform-created app-aware command Jobs.

## Infra Applied

Infra updated the canonical operator release manifest:

```text
lenscloud-infra/manifests/operators/frappe-operator-release-install.yaml
```

The manager cluster was live-applied and rolled out:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  apply -f /tmp/frappe-operator-v4.1.1-install.yaml

kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n frappe-operator-system rollout status \
  deployment/frappe-operator-controller-manager --timeout=5m
```

Verified live containers:

```text
kube-rbac-proxy=kubebuilder/kube-rbac-proxy:v0.13.1
manager=ghcr.io/vyogotech/frappe-operator:4.1.1
```

Infra also keeps the runner digest/admission verification in:

```text
lenscloud-infra/scripts/58-verify-platform-bench-command.sh
```

The verifier covers:

- Platform can read
  `lenscloud-platform-system/lenscloud-platform-cluster-contract`;
- `bench_command_runner_image` is digest-pinned;
- admitted generic runner image for non-app-aware commands;
- rejected stale generic runner digest;
- denial message contains `approved execution image`;
- admitted digest-pinned `lensdocker/lens-pure` for app-aware `bench.update`;
- rejected mutable `lens-pure:<tag>` and rejected generic runner image for
  app-aware commands.

## Fallback Route

Use the fork only if upstream `v4.1.1` fails on another live cluster or if
LensCloud later requires digest-pinned Bench CR images:

```text
https://github.com/lmnaslimited/frappe-operator
```

Build and package any custom operator image from the forked operator repo
itself. Do not build custom operator packages from `lenscloud-infra`, and do
not depend on uncommitted files on a disposable manager VM.

## No Regression Notes

Existing generic Bench Commands keep the generic runner path and the same
admission security posture. Admission still blocks unlabelled Jobs, mutable
app-aware runtime tags, unexpected Secret volumes, pod logs, service-account
tokens, privileged containers, multiple containers, and `envFrom`.
