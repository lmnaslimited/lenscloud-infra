# Platform Handoff: Release Group App Install And Bench Upgrade

Date: 2026-07-16
Infra workitem: `INF-027`

## Status

Infra has corrected the execution model for app-aware Bench Commands.

The previous model used `ghcr.io/lmnaslimited/lenscloud-bench-command-runner`
as the execution image for `site_bootstrap`, `site_app`, and `bench.update`.
That is no longer the canonical model because that image bakes in an app set
and cannot safely migrate or install apps for arbitrary Release Groups.

The canonical model is now:

> App-aware Bench Command Jobs run inside the target Release Group runtime
> image, digest-pinned, and mount the Bench sites volume exactly like the Bench
> runtime pods.

This matches the existing Docker Swarm pattern where the one-shot `migration`
service uses the same Release Group image as the stack.

## Command Families

| Flow | Family | Command | Execution image |
| --- | --- | --- | --- |
| New Site bootstrap app install | `site_bootstrap` | `site_bootstrap.install_apps` | Target Release Group runtime image |
| Existing Site app install | `site_app` | `site_app.install` | Current/target Release Group runtime image containing the requested app |
| Bench update/migration | `bench` | `bench.update` | `next_release` runtime image |

Existing non-app-aware command families continue to use the generic
`lenscloud-bench-command-runner` path. This preserves existing Platform
behavior for maintenance mode, developer mode, site config, CORS, site setup,
OAuth, backup/restore status-style commands, LATP, and the `bench_test.status`
smoke path.

## Platform Must Adapt

Platform must stop creating `site_bootstrap`, `site_app`, and `bench.update`
Jobs with:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:<digest>
```

For these three app-aware families, Platform must create Jobs with the Release
Group runtime image digest:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:<64-hex-digest>
```

Do not use mutable tags in Job specs. Resolve the Release Group tag to an
immutable digest before creating the Job.

## Platform Implementation Sequence

Platform should implement three separate action paths. Do not collapse them
into one generic app-install flow.

1. New Site bootstrap app install

   - Trigger after the base Frappe Site exists and before the Site is handed to
     the customer as ready/usable.
   - Use command family `site_bootstrap`.
   - Use command `site_bootstrap.install_apps`.
   - Use the Site creation Release Group runtime image digest.
   - Install only Release Group child apps where `install_at_site_creation` is
     checked.
   - Sort by `install_sequence`.

2. Existing Site app install

   - Trigger only from an explicit Platform/customer action after the Site is
     already Ready.
   - Use command family `site_app`.
   - Use command `site_app.install`.
   - Use the current Bench Release Group runtime image digest, or the updated
     runtime image digest after a successful Bench upgrade rollout.
   - Install only apps included in the Site's Bench Release Group and present
     in the selected runtime image.

3. Bench update

   - Trigger only after all active Sites on the Bench are scheduled and tested.
   - Use command family `bench`.
   - Use command `bench.update`.
   - Run the migration Job with the Bench `next_release` runtime image digest.
   - After migration succeeds, update the Bench runtime image, wait for runtime
     rollout, verify assets are fresh, then move release pointers.

## Bench Update Job Contract

Platform should render `bench.update` as the Kubernetes equivalent of the Swarm
`migration` service.

Required image:

```text
target Bench next_release image digest
```

Required command:

```bash
bench --site all set-config -p maintenance_mode 1
bench --site all set-config -p pause_scheduler 1
bench --site all migrate
bench --site all set-config -p maintenance_mode 0
bench --site all set-config -p pause_scheduler 0
```

Required target:

- Bench only.
- No Site target.
- Only after every active Site on the Bench is scheduled and tested.

Required Job metadata:

```yaml
labels:
  lenscloud.io/managed-by: platform
  lenscloud.io/resource-kind: bench-command
annotations:
  lenscloud.io/bench-command-family: bench
  lenscloud.io/bench-command: bench.update
```

Required Job safety shape:

- `restartPolicy: Never`
- `automountServiceAccountToken: false`
- `backoffLimit <= 1`
- one container
- non-privileged container
- no `envFrom`
- no Secret volumes

Required volume shape:

Platform must mirror the target Bench pod's sites mount. If the Bench pod uses
`subPath: frappe-sites`, the Job must use the same subPath. If the Bench pod
mounts the PVC root directly, the Job must mount the root directly.

Example for the current operator layout:

```yaml
volumeMounts:
  - name: sites
    mountPath: /home/frappe/frappe-bench/sites
    subPath: frappe-sites
    readOnly: false
  - name: sites-assets
    mountPath: /home/frappe/frappe-bench/sites/assets
    subPath: frappe-sites/assets
    readOnly: false
volumes:
  - name: sites
    persistentVolumeClaim:
      claimName: <bench-sites-pvc>
  - name: sites-assets
    persistentVolumeClaim:
      claimName: <bench-sites-pvc>
```

If the Bench pod does not have a separate assets mount, omit the
`sites-assets` mount from the command Job too.

## App Install Job Contract

For New Site bootstrap, Platform derives the app list from Release Group child
rows where `install_at_site_creation` is checked.

For existing Site app install, Platform may install only apps included in the
Site's Bench Release Group and present in the selected runtime image.

Platform must:

- exclude `frappe`;
- sort by ascending `install_sequence`, with empty values last;
- use stable app identifiers, not display labels;
- reject duplicate apps in one request;
- reject apps outside the Bench Release Group;
- render one ordered `bench --site <site> install-app <app>` command per app;
- retry idempotently by treating an already-installed app as skipped/success.

Example command body:

```bash
bench --site customer.example.com install-app erpnext
bench --site customer.example.com install-app hrms
```

The Job image must be the Release Group runtime image that contains those apps.

## Admission Policy

Infra admission now allows the app-aware families only when the container image
matches:

```text
^ghcr\.io/lmnaslimited/lensdocker/lens-pure@sha256:[0-9a-f]{64}$
```

The existing generic runner image remains allowed only for non-app-aware
families. The `bench_test.status` busybox smoke exception remains unchanged.

Admission still denies:

- unlabelled Jobs;
- unapproved command families;
- mutable runtime image tags;
- the old runner image for `site_bootstrap`, `site_app`, and `bench`;
- more than one container;
- privileged containers;
- `envFrom`;
- service-account token mounts;
- Secret volumes except the existing OAuth client-secret exception for OAuth.

## Platform Upgrade Gates

Before creating `bench.update`, Platform must require:

- every active Site on the Bench has `upgrade_state = Scheduled`;
- every active Site has passed the required upgrade test;
- `upgrade_tested`, `tested_on`, and `tested_by` are populated;
- `next_release` belongs to the Bench Release Group;
- `next_release` has an immutable runtime image digest;
- the target Bench sites PVC and mount/subPath shape are known.

After a successful `bench.update`, Platform may move:

```text
current_release = next_release
next_release = empty/null
```

Platform must not move the Bench release pointers before the migration Job
succeeds.

## Result Handling

For direct runtime-image Jobs, Platform should read the Kubernetes Job and Pod
terminal state and map it into the existing action result UI.

Minimum success fields:

```json
{
  "phase": "Succeeded",
  "summary": "Bench update completed",
  "details": {
    "target_release": "v16.14.3",
    "operation": "bench --site all maintenance/pause/migrate",
    "exit_code": 0
  },
  "redacted": true
}
```

Minimum failure fields:

```json
{
  "phase": "Failed",
  "summary": "Bench update failed",
  "details": {
    "target_release": "v16.14.3",
    "operation": "bench --site all maintenance/pause/migrate",
    "exit_code": 1,
    "error_excerpt": "<sanitized tail>"
  },
  "redacted": true
}
```

Do not expose Secret values, kubeconfig material, raw `site_config.json`, DB
passwords, private keys, access tokens, environment dumps, or full logs.

## Infra Verification

Infra local/static verification:

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

Live verification on a test cluster:

```bash
scripts/58-verify-platform-bench-command.sh
```

This verifies that:

- existing `bench_test.status` behavior still works;
- digest-pinned Release Group runtime images are admitted for app-aware
  commands;
- the old runner image is denied for app-aware commands;
- unsafe Jobs and Secret-volume Jobs are denied;
- Platform still lacks pod-log and Secret list/read access.

## Platform Acceptance Tests

Platform should complete these tests before marking this work item done:

1. Create a New Site and install Release Group apps selected for site creation.
2. Retry the same app install and show already-installed apps as skipped.
3. Install a newly available Release Group app on an existing Site.
4. Create a Bench on `lens-pure:v16.14.2`.
5. Schedule and test every active Site on that Bench.
6. Run `bench.update` with the `lens-pure:v16.14.3` runtime image digest.
7. Confirm `bench --site all migrate` succeeds from the runtime-image Job.
8. Confirm Platform moves `current_release` only after Job success.
9. Confirm a mutable tag image is denied.
10. Confirm the old `lenscloud-bench-command-runner` image is denied for
    `bench.update`.

## References

Infra SOP:

```text
docs/test-cluster-build-handoff-sop.md
```

Runtime-image command templates:

```text
docs/testing/bench-command-runner/site_bootstrap_install_apps_template.yaml
docs/testing/bench-command-runner/site_app_install_template.yaml
docs/testing/bench-command-runner/bench_update_runtime_image_template.yaml
```
