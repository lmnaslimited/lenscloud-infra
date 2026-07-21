# Infra Return - Customer Site Creation App Installation Latency

Date: 2026-07-21
From: Infra
To: Platform
Status: Patched operator published, admitted, and live-tested

## Summary

Infra confirmed that Platform used the correct operator path:
`FrappeSite.spec.apps` contained `erpnext` and `brandkit`, and the Site reached
Ready with both apps in `status.installedApps`.

The retained init Job is no longer present, so the requested per-phase timing
split cannot be reconstructed from Kubernetes for the retained Site. Infra
published and admitted a patched operator image with configurable Site init Job
resources, then ran a fresh disposable proof.

## Evidence

Detailed evidence:

```text
lenscloud-infra/docs/customer-site-creation-app-install-latency-evidence-20260721.md
```

Retained Site timings:

```text
created:       2026-07-21T11:37:35Z
BenchReady:    2026-07-21T11:37:35Z
DatabaseReady: 2026-07-21T11:37:36Z
Ready:         2026-07-21T11:43:04Z
```

## Fix Published

Published in the LensCloud operator fork:

```text
repo:   https://github.com/lmnaslimited/frappe-operator.git
branch: lenscloud-beta
commit: 1333c73a Add configurable site init job resources
image:  ghcr.io/lmnaslimited/frappe-operator@sha256:e22c78676cbfd87d9e8738763414be8f78eb2126d3cbb87c8f1b182a4ea9a4bf
```

Implemented changes:

- ConfigMap-driven resource overrides for FrappeSite init Jobs.
- Backward-compatible support for the live ConfigMap name
  `frappe-operator-frappe-operator-config`.
- Helm values/configmap wiring.
- Focused controller tests.

Infra checked upstream first:

```text
latest upstream tag: v4.1.1
upstream main getSiteInitResources: still hard-coded, no resource override
```

So there is no newer tagged operator version to adopt for this fix.

No new production default is selected by this patch. The operator keeps its
current defaults unless Infra sets the ConfigMap/Helm values during a deployment.

Live operator deployment:

```text
namespace:  frappe-operator-system
deployment: frappe-operator-controller-manager
pod:        frappe-operator-controller-manager-784dff44c7-rcdpl
state:      Running 2/2
```

Infra first tested a `1000m/2Gi` request with `2/3Gi` limits. The patch worked,
but the disposable init Pod could not schedule because the worker already had
`3100m/4000m` CPU requested. The failed disposable Site was deleted.

The successful live measurement profile is:

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

Those values are not hard-coded into the operator and should not be treated as
the final production profile without a capacity decision.

## Verification

```text
GOCACHE=/private/tmp/lenscloud-go-build GOMODCACHE=/private/tmp/lenscloud-go-mod go test ./controllers
ok github.com/vyogotech/frappe-operator/controllers 1.312s
```

## Fresh Proof

Disposable Site:

```text
FrappeSite: infra-latency-07211351
host:       infra-latency-07211351.cloud.lmnaslens.com
apps:       erpnext, brandkit
```

Timing result:

| Metric | Value |
| --- | ---: |
| FrappeSite creation-to-Ready | 241s |
| Init Job start-to-complete | 240s |
| Init container runtime | 235s |
| Platform retained Site baseline | 329s |
| Reduction | 88s |

Final status:

```text
status.phase: Ready
status.installedApps: erpnext, brandkit
status.appInstallationStatus: Completed app installation for 2 requested app(s) - check logs for any skipped apps
```

The proof Site is retained for short-term inspection. Infra did not delete
Platform's retained Site `iron-monkey-0721113731`.

## Platform Guidance

The operator patch is live and proves a material reduction, but the current
241-second operator stage is still too high for the full five-minute customer
target if setup/OAuth remain on the critical path at the previously observed
latencies.

Next Platform pass should rerun the full under-five-minute harness against the
patched operator and continue moving command cleanup out of the customer-critical
response path. If the full gate still fails, the next Infra/Platform design path
is a prepared Site/database template or snapshot flow using `spec.skipInit: true`
with a valid prebuilt schema and default apps.
