# Customer Provisioning Job Latency Evidence - 2026-07-21

## Source Request

Platform handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/customer-provisioning-job-latency-under5-20260721.md
```

Platform measured fresh customer Site `iron-monkey-0721081416.cloud.lmnaslens.com`
at 492.885s total, with the largest command intervals:

| Command | Platform interval |
| --- | ---: |
| `site_bootstrap.install_apps` | 201.197s |
| `oauth.status` final verification | 134.733s |

## Infra Changes

- Added `scripts/66-verify-customer-provisioning-job-latency.sh`.
- Installed live DaemonSet `lenscloud-command-image-prewarm` in
  `lenscloud-runtime-eu`.
- Kept the existing nested `summary.message` contract unchanged.
- Kept Release-runtime admission unchanged for app-aware commands.

## Images

Generic runner:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3b71912830d3dac1465a7e3cfa03dd64c76b17826fd7614a6801e4c539813cf5
```

Release runtime:

```text
ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
```

Image warmth:

```text
DaemonSet: lenscloud-command-image-prewarm
Desired: 1
Ready: 1
Available: 1
Node: lenscloud-eu-worker-1
Release runtime image: already present on machine
Generic runner image: already present on machine
```

## Operator Capability

The live Frappe Operator already supports app installation during initial Site
creation:

```text
FrappeSite.spec.apps
FrappeSite.status.installedApps
FrappeSite.status.appInstallationStatus
FrappeSite.status.conditions[type=Ready]
```

The CRD describes `spec.apps` as apps to install on the site during initial
site creation. Live `iron-monkey-0721081416` was created without `spec.apps`;
its status reported:

```text
appInstallationStatus: No apps specified - only frappe framework installed
```

That explains why Platform later needed a separate
`site_bootstrap.install_apps` Job. For default site-creation apps such as
`erpnext`, Platform should pass the allowlisted install-at-site-creation apps
in `FrappeSite.spec.apps`, then treat `status.installedApps` plus
`appInstallationStatus` as the operator completion signal. Keep separate
app-aware Jobs only for post-creation capability installs.

## Live Timing Probe

Probe script:

```text
scripts/66-verify-customer-provisioning-job-latency.sh
```

Standard probe:

```text
TEST_PREFIX=run-20260721-0144-latency
BENCH=run-20260716-e2e-update-132858-bench
SITE=run-20260716-e2e-update-132858-site.cloud.lmnaslens.com
PREWARM=0
```

OAuth configure probe:

```text
TEST_PREFIX=run-20260721-0157-latency
BENCH=run-20260702-free-prod-bench
SITE=tharahub.cloud.lmnaslens.com
PREWARM=0
RUN_STANDARD_PROBES=0
RUN_OAUTH_CONFIGURE=1
```

Temporary OAuth provider `lenscloud_latency_probe` was removed after the probe.

## Per-Command After Timings

| Command | Create API | Job to Pod | Scheduled to Start | Container Runtime | Finish to Job Complete | Job Complete to Watch Observed | Observed Wait |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `site_bootstrap.install_apps` idempotent | 0.287s | 0.000s | 1.000s | 7.000s | 3.000s | 0.216s | 10.236s |
| `site_setup.complete` idempotent | 0.299s | 1.000s | 1.000s | 6.000s | 3.000s | 0.407s | 10.479s |
| `site_setup.status` | 0.309s | 0.000s | 1.000s | 6.000s | 3.000s | 0.635s | 10.265s |
| `oauth.status` | 0.318s | 0.000s | 1.000s | 6.000s | 3.000s | 0.861s | 10.558s |
| `oauth.configure` | 0.301s | 1.000s | 1.000s | 9.000s | 2.000s | 1.443s | 14.078s |

All probe Pods reported image cache hits:

```text
Container image "...lens-pure@sha256:92196..." already present on machine
Container image "...lenscloud-bench-command-runner@sha256:3b719..." already present on machine
```

## Analysis

Cluster admission, pod creation, scheduling, image startup, and Job terminal
delivery are not the source of the measured 492.885s customer run after image
prewarm:

- Job create API was about 0.3s.
- Pod scheduling was 0-1s.
- Image pull was a cache hit for both images.
- Terminal Job completion was observable by a watch-style wait within 1.443s.
- Read-only generic status commands completed in about 10.3-10.6s observed.
- OAuth configure completed in 14.078s observed on a valid ready site.

The 201.197s bootstrap interval is consistent with real post-creation app
installation work. The operator can move this work into initial
`FrappeSite.spec.apps` creation and emit completion through `status.installedApps`
and `status.appInstallationStatus`, avoiding a separate customer-visible
post-ready bootstrap Job for default apps.

The 134.733s final OAuth verification interval is not reproduced by direct
generic runner proof. With warmed image and valid target, `oauth.status` was
10.558s observed. Platform should split command wait, observation wait, route
check, socket delivery, and cleanup in the next customer retest.

## Completion Delivery

The Platform service account can watch the relevant resources:

```text
watch jobs.batch: yes
watch pods: yes
watch events: yes
```

There is no separate Frappe Operator callback for Platform-created Bench
Command Jobs. The reliable completion delivery path is Kubernetes Job/Pod watch
with list-then-watch reconnect behavior. If Platform keeps two-second polling,
the measured penalty should be at most about two seconds; the live watch-style
wait observed terminal completion within 1.443s.

## Cleanup

Probe cleanup:

```text
kubectl -n lenscloud-runtime-eu get job,pod,cm,secret -o name \
  | grep -E 'run-20260721-0144-latency|run-20260721-0157-latency'

Result: no output
```

The canonical prewarm DaemonSet remains intentionally installed:

```text
lenscloud-command-image-prewarm
```
