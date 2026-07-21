# Infra Return - Customer Provisioning Job Latency Under Five Minutes

Date: 2026-07-21
From: Infra
To: Platform
Status: Returned with infra-side fix and Platform retest procedure
Request: `docs/handoffs/infra/customer-provisioning-job-latency-under5-20260721.md`

## Infra Commit Range

Current infra base: `a23258a`

Working tree changes:

- `scripts/66-verify-customer-provisioning-job-latency.sh`
- `docs/customer-provisioning-job-latency-evidence-20260721.md`
- this return handoff

## Changes Delivered

Infra installed a canonical live image prewarm DaemonSet:

```text
Namespace: lenscloud-runtime-eu
DaemonSet: lenscloud-command-image-prewarm
Status: desired=1 ready=1 available=1
```

The DaemonSet keeps both accepted execution images hot on the eligible worker:

```text
Release runtime:
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0

Generic runner:
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
```

Infra also added repeatable verifier:

```text
scripts/66-verify-customer-provisioning-job-latency.sh
```

The verifier records create/admission, Pod scheduling, image cache event,
container start/end, Job terminal condition, termination summary, and
watch-style terminal observation timing.

## Per-Command Timing Evidence

Evidence file:

```text
lenscloud-infra/docs/customer-provisioning-job-latency-evidence-20260721.md
```

After prewarm:

| Command | Cluster terminal result | Observed wait | Terminal to observed |
| --- | ---: | ---: | ---: |
| `site_bootstrap.install_apps` idempotent | 10.236s | 10.236s | 0.216s |
| `site_setup.complete` idempotent | 10.479s | 10.479s | 0.407s |
| `site_setup.status` | 10.265s | 10.265s | 0.635s |
| `oauth.status` | 10.558s | 10.558s | 0.861s |
| `oauth.configure` | 14.078s | 14.078s | 1.443s |

All probes reported image cache hits. Scheduling was 0-1s and container start
after schedule was 1s for the post-prewarm run.

## Image Warmth Evidence

Prewarm DaemonSet:

```text
NAME                              DESIRED   READY   AVAILABLE
lenscloud-command-image-prewarm   1         1       1
```

Pod events:

```text
release runtime image already present on machine
generic runner image already present on machine
```

## Operator-Side Completion Signal

The live Frappe Operator already supports app installation during initial site
creation:

```text
FrappeSite.spec.apps
FrappeSite.status.installedApps
FrappeSite.status.appInstallationStatus
FrappeSite.status.conditions[type=Ready]
```

Live customer Site `iron-monkey-0721081416` was created without
`spec.apps`, and the operator reported:

```text
appInstallationStatus: No apps specified - only frappe framework installed
```

Infra recommendation: Platform should pass default install-at-site-creation
apps such as `erpnext` into `FrappeSite.spec.apps` when creating the Site, then
use `status.installedApps`, `status.appInstallationStatus`, and the Ready
condition as the operator-native completion signal. This avoids the separate
post-ready `site_bootstrap.install_apps` Job for default creation apps. Keep
app-aware Jobs only for post-creation capability installs.

This is the biggest path to under five minutes. The 201.197s bootstrap interval
is real app installation work, not Kubernetes observation or image pull.

## Completion Delivery Contract

Platform may keep two-second polling, but watch is already authorized and
measured faster:

```text
system:serviceaccount:lenscloud-platform-system:lenscloud-platform can watch jobs.batch: yes
system:serviceaccount:lenscloud-platform-system:lenscloud-platform can watch pods: yes
system:serviceaccount:lenscloud-platform-system:lenscloud-platform can watch events: yes
```

There is no separate Frappe Operator callback for Platform-created Bench
Command Jobs. The reliable low-latency delivery contract is:

1. list the target Job/Pods by Platform labels and resourceVersion;
2. watch Jobs for `Complete` or `Failed`;
3. on reconnect, relist by exact Job name and labels so missed events do not
   lose terminal state;
4. after terminal state, read the terminal Pod summary before deleting
   resources;
5. publish customer-visible terminal progress before nonessential cleanup.

Live terminal Job state was watch-observable within 1.443s.

## Explanation Of Platform Outliers

`site_bootstrap.install_apps` at 201.197s:

- not reproduced as scheduling/image delay;
- release image was warm;
- direct idempotent app-aware probe completed in 10.236s observed;
- root cause is real post-creation app installation work.

Fix: use `FrappeSite.spec.apps` at Site creation for default creation apps and
consume operator status fields.

`oauth.status` at 134.733s:

- not reproduced by direct generic runner proof;
- generic runner image was warm;
- direct `oauth.status` completed in 10.558s observed;
- terminal-to-observed was 0.861s.

Platform should split this interval into command wait, route/HTTP verification,
socket delivery, and cleanup during the fresh customer retest.

## Retained Contracts

- Nested `summary.message` failure envelope is unchanged.
- Generic runner remains only for non-app-aware command families such as
  `site_setup.status`, `oauth.status`, and `oauth.configure`.
- `site_bootstrap.*`, `site_app.*`, `bench.*`, and `site_setup.complete`
  continue to require digest-pinned Release runtime images.
- Admission was not weakened.

## Remaining Caveats

- Infra cannot prove a fresh `erpnext` install under 90s through the separate
  post-ready Job path; that work is app/database initialization and measured
  201.197s in Platform evidence.
- The under-five-minute customer path depends on Platform moving default
  creation apps into `FrappeSite.spec.apps` and skipping the separate bootstrap
  Job when the operator reports the apps installed.
- Platform should continue to measure customer socket delivery separately from
  cluster terminal state and cleanup.

## Platform Retest Procedure

1. Keep `lenscloud-command-image-prewarm` ready.
2. Create a fresh customer Site with default install-at-site-creation apps in
   `FrappeSite.spec.apps`.
3. Watch or poll `FrappeSite.status.conditions[type=Ready]`,
   `status.installedApps`, and `status.appInstallationStatus`.
4. Do not run a separate `site_bootstrap.install_apps` Job for apps already
   requested in `spec.apps`.
5. Run `site_setup.complete`, `site_setup.status`, `oauth.configure`, and
   `oauth.status` normally.
6. Record command wait, terminal-to-observed, cleanup, route/HTTP verification,
   and socket delivery as separate intervals.
7. Expected cluster-side post-ready command budgets with warm images:
   `site_setup.status <= 15s`, `oauth.configure <= 30s`,
   `oauth.status <= 15s`, and terminal-to-observed `<= 2s`.
