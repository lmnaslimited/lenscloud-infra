# Customer Site Creation App Install Latency Evidence - 2026-07-21

## Source Request

Platform handoff:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/customer-site-creation-app-install-latency-20260721.md
```

Platform measured fresh Site `iron-monkey-0721113731.cloud.lmnaslens.com`:

| Metric | Value |
| --- | ---: |
| FrappeSite created | 2026-07-21T11:37:35Z |
| FrappeSite Ready | 2026-07-21T11:43:04Z |
| Operator creation-to-Ready | 329s |
| Requested apps | `erpnext`, `brandkit` |
| Separate bootstrap Job | none |

## Retained Site State

Live `FrappeSite/lenscloud-runtime-eu/iron-monkey-0721113731` still exists and
must remain retained for Platform cleanup.

```text
metadata.creationTimestamp: 2026-07-21T11:37:35Z
spec.apps: erpnext, brandkit
status.installedApps: erpnext, brandkit
status.appInstallationStatus: Completed app installation for 2 requested app(s) - check logs for any skipped apps
status.conditions[BenchReady].lastTransitionTime: 2026-07-21T11:37:35Z
status.conditions[DatabaseReady].lastTransitionTime: 2026-07-21T11:37:36Z
status.conditions[Ready].lastTransitionTime: 2026-07-21T11:43:04Z
status.phase: Ready
```

This brackets database readiness at about one second after CR creation and
leaves about 328 seconds in the single operator init Job plus final
reconciliation.

## Missing Retained Init Job

The requested phase split cannot be reconstructed from the retained Site alone.
The expected init Job is already absent:

```text
kubectl -n lenscloud-runtime-eu get job iron-monkey-0721113731-init
Result: NotFound
```

The runtime namespace also has no matching retained init Pod. Only unrelated
older Jobs and Pods remain. The operator CR status does not store new-site,
per-app install, migrate, or cleanup timestamps.

## Operator Capability Review

The current operator path installs requested apps inside the Site init Job:

```text
FrappeSite.spec.apps -> site_init.sh -> bench new-site --install-app=<app>
```

The script performs these phases inside one container:

1. Build/validate `--install-app` arguments from `spec.apps`.
2. Run `bench new-site` with requested apps.
3. Create/update common site config.
4. Copy prebuilt assets from `/home/frappe/assets_cache` if present.
5. Finalize `site_config.json`.
6. Mark `.init_complete`.

The current CR status exposes only broad completion:

```text
status.installedApps
status.appInstallationStatus
status.conditions[type=Ready]
```

There is no operator-side callback or status field for individual app phases.

## Original Live Operator State

Original live operator image:

```text
ghcr.io/vyogotech/frappe-operator:4.1.1
```

Live manager deployment resources:

```text
manager requests: cpu=10m memory=64Mi
manager limits: cpu=500m memory=128Mi
```

The live ConfigMap is named:

```text
frappe-operator-frappe-operator-config
```

It contains `maxConcurrentSiteReconciles: "10"` and no site-init resource
override keys.

## Fork Patch Published

The operator fix was pushed to the LensCloud fork:

```text
repo:   https://github.com/lmnaslimited/frappe-operator.git
branch: lenscloud-beta
commit: 1333c73a Add configurable site init job resources
```

Published image:

```text
ghcr.io/lmnaslimited/frappe-operator:lenscloud-beta-1333c73a
digest: sha256:e22c78676cbfd87d9e8738763414be8f78eb2126d3cbb87c8f1b182a4ea9a4bf
```

Infra manifest pin updated:

```text
manifests/operators/frappe-operator-release-install.yaml
image: ghcr.io/lmnaslimited/frappe-operator@sha256:e22c78676cbfd87d9e8738763414be8f78eb2126d3cbb87c8f1b182a4ea9a4bf
```

Live deployment admitted the digest after the GHCR package was made public:

```text
namespace:  frappe-operator-system
deployment: frappe-operator-controller-manager
pod:        frappe-operator-controller-manager-784dff44c7-rcdpl
image:      ghcr.io/lmnaslimited/frappe-operator@sha256:e22c78676cbfd87d9e8738763414be8f78eb2126d3cbb87c8f1b182a4ea9a4bf
state:      Running 2/2
```

## Bottleneck Found

The operator source hard-codes FrappeSite init Job resources:

```text
requests: cpu=100m memory=1Gi
limits:   cpu=500m memory=1Gi
```

That cap applies to the single Job running `bench new-site` plus ERPNext and
Brandkit installation. The Platform result is therefore consistent with real
app installation work running under a half-core CPU limit. Image prewarm helps
command startup, but it does not remove this compute cap from the operator init
Job.

## Upstream Version Check

Checked upstream before carrying the local patch:

```text
git ls-remote --tags https://github.com/vyogotech/frappe-operator.git
Latest tag: refs/tags/v4.1.1

git ls-remote https://github.com/vyogotech/frappe-operator.git HEAD refs/heads/main
main: 72f5312797c854f3dd33d712d7337ab99f235053
```

There is no tagged operator release newer than the live cluster image
`ghcr.io/vyogotech/frappe-operator:4.1.1`.

Fetched upstream `main` for inspection. Its `getSiteInitResources` still
hard-codes init Job resources and does not expose Site init CPU/memory overrides
or phase telemetry:

```text
requests: cpu=100m memory=128Mi
limits:   cpu=500m memory=256Mi
```

The post-`v4.1.1` upstream commits visible in `v4.1.1..FETCH_HEAD` were:

```text
72f53127 chore: publish Helm chart v3.0.0
2019e5b3 feat: externalize image configuration and set default image to ghcr.io/vyogotech/erpnext-for-operator:version-16
d850f659 chore: publish Helm chart v3.0.0
```

None of these includes configurable FrappeSite init Job resources, init phase
timestamps, or retained per-app install status.

## Optimization Implemented

Patched `frappe-operator` branch `lenscloud-beta`:

- `controllers/site_lifecycle.go`
  - reads optional ConfigMap keys for Site init Job resources:
    - `siteInitCPURequest`
    - `siteInitMemoryRequest`
    - `siteInitCPULimit`
    - `siteInitMemoryLimit`
  - preserves existing defaults when keys are absent or invalid.
- `controllers/utils.go`
  - accepts both ConfigMap names:
    - `frappe-operator-config`
    - `frappe-operator-frappe-operator-config`
- `helm/frappe-operator/templates/configmap.yaml`
  - emits the new keys.
- `helm/frappe-operator/values.yaml`
  - adds empty default values to preserve existing behavior.
- `controllers/frappebench_resources_test.go`
  - verifies override parsing and the live installed ConfigMap name.

No new production default is selected by this patch. The operator keeps its
current defaults unless Infra sets the ConfigMap/Helm values during a deployment.

For the live measurement, Infra used ConfigMap overrides rather than hard-coded
operator defaults.

First attempted measurement profile:

```yaml
operatorConfig:
  siteInitResources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "3Gi"
```

This correctly rendered onto the init Job, but it could not schedule on current
cluster capacity:

```text
FrappeSite: infra-latency-07211345
Job:        infra-latency-07211345-init
requests:   cpu=1 memory=2Gi
limits:     cpu=2 memory=3Gi
event:      0/2 nodes are available: 1 Insufficient cpu, 1 node(s) had untolerated taint(s)
worker:     lenscloud-eu-worker-1 allocated cpu requests 3100m/4000m
```

The failed disposable Site was deleted. The retained Platform Site
`iron-monkey-0721113731` was not deleted.

Successful measurement profile:

```yaml
operatorConfig:
  siteInitResources:
    requests:
      cpu: "250m"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "3Gi"
```

Those values remain live in
`frappe-operator-system/frappe-operator-frappe-operator-config` as the current
measurement profile. They are not hard-coded into the operator and should not be
treated as the final production profile without a capacity decision.

## Verification

```text
GOCACHE=/private/tmp/lenscloud-go-build GOMODCACHE=/private/tmp/lenscloud-go-mod go test ./controllers
ok github.com/vyogotech/frappe-operator/controllers 1.312s
```

## Fresh Proof

Fresh proof Site:

```text
FrappeSite: infra-latency-07211351
host:       infra-latency-07211351.cloud.lmnaslens.com
namespace:  lenscloud-runtime-eu
bench:      run-20260702-free-prod-bench
apps:       erpnext, brandkit
```

Timing:

```text
FrappeSite created: 2026-07-21T13:46:33Z
Init Job created:   2026-07-21T13:46:34Z
Init Job started:   2026-07-21T13:46:34Z
Pod scheduled:      2026-07-21T13:46:34Z
Container started:  2026-07-21T13:46:35Z
Container finished: 2026-07-21T13:50:30Z
Init Job complete:  2026-07-21T13:50:34Z
FrappeSite Ready:   2026-07-21T13:50:34Z
```

Measured durations:

| Metric | Duration |
| --- | ---: |
| FrappeSite creation-to-Ready | 241s |
| Init Job start-to-complete | 240s |
| Init container runtime | 235s |
| Reduction vs Platform retained Site | 88s |

Init Job resources:

```text
requests: cpu=250m memory=2Gi
limits:   cpu=2 memory=3Gi
```

Container image was already present on the node:

```text
imageID: ghcr.io/lmnaslimited/lensdocker/lens-pure@sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0
event:   Container image already present on machine
```

Final Site status:

```text
status.phase: Ready
status.installedApps: erpnext, brandkit
status.appInstallationStatus: Completed app installation for 2 requested app(s) - check logs for any skipped apps
```

Log tail confirmed both requested apps completed:

```text
Installing ERPNext...
ERPNext installation completed
Installing Brandkit...
Brandkit installation completed
Site initialization complete
```

The operator emitted one transient warning for the Infra-created disposable
manifest because the Platform encryption-key Secret was not precreated:

```text
SiteInitializationFailed: failed to create init secret: Secret "infra-latency-07211351-encryption-key" not found
```

The operator recovered without manual intervention, the init Job completed, and
the Site reached Ready. The disposable proof Site is retained for short-term
inspection.

## Target Assessment

The patched operator reduced operator creation-to-Ready from 329 seconds to 241
seconds for the same requested app set, a reduction of 88 seconds. This validates
that the hard-coded init Job resources were a real latency contributor.

The current live proof still does not leave enough budget for the full
`erpnext + brandkit + setup + OAuth` customer target if Platform setup/OAuth
remain near the previously measured 180+ seconds. A practical budget requires:

- operator creation-to-Ready at or below 180 seconds;
- setup and OAuth combined at or below 120 seconds;
- command cleanup moved outside the customer-critical path by Platform.

If the raised init resources still cannot bring operator creation-to-Ready below
180 seconds, the remaining viable path is a prepared Site/database template or
snapshot flow using `spec.skipInit: true` against a database that already
contains a valid Frappe schema and required default apps.
