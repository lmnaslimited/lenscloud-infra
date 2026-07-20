# Site Setup Status Mount Failed

Date: 2026-07-20
Reported by: Platform/test team

## Status

Open. Platform must provide the exact failing Job YAML from the test cluster;
Infra SOP updated with the expected mount split.

## Incident

The team reported a `site_setup.status` Bench Command failure for:

```text
Test VM: 167.235.138.49
Command: site_setup.status
Command ID: BCMD-2026-00356
Job: bcmd-2026-00356-job
Site: ubuntu.testcloud.lmnaslens.com
Bench: eu-shared-bench-two
Namespace: lenscloud-runtime-eu
Bench runtime: lens-pure v16.14.1
Runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

The pod failed during OCI/containerd startup while creating a mountpoint under:

```text
/home/frappe/frappe-bench/sites/assets
```

This means the runner binary likely did not start.

The impacted Site was deleted after customer provisioning entered a
never-ending `site_setup.status` loop. Future proof must use a fresh disposable
Site on the same test cluster.

Platform-side loop prevention was added in the same incident pass:
failed `site_setup.status` results now mark setup as `Failed` instead of
`Required`.

## Contract

`site_setup.status` is a generic status command. It should mount the request
ConfigMap and the Bench sites PVC read-only. It should not mount
`/home/frappe/frappe-bench/sites/assets`.

Only app-aware runtime-image jobs mirror the Bench pod's separate assets mount,
and only when the target Bench pod uses that mount.

## Immediate Diagnostic Commands

On the failing manager VM:

```bash
ssh root@167.235.138.49

kubectl --kubeconfig "$MANAGER_KUBECONFIG" \
  -n lenscloud-runtime-eu get job bcmd-2026-00356-job -o yaml

kubectl --kubeconfig "$MANAGER_KUBECONFIG" \
  -n lenscloud-runtime-eu get pod \
  -l job-name=bcmd-2026-00356-job -o yaml

kubectl --kubeconfig "$MANAGER_KUBECONFIG" \
  -n lenscloud-runtime-eu get deploy \
  -l app.kubernetes.io/instance=eu-shared-bench-two -o yaml
```

If cleanup already removed the resources, rerun `site_setup.status` once and
capture the stored Platform Action Log manifest before cleanup details are
discarded.

## Acceptance

- The real `site_setup.status` Job has no `sites-assets` volume or mount.
- The real `site_setup.status` Job uses the same `sites` PVC subPath convention
  as the target Bench pod.
- A fresh status run reaches the runner and returns a normal command result.
- If a pod startup failure recurs, Platform surfaces a terminal failed setup
  state and does not keep looping on `site_setup.status`.
