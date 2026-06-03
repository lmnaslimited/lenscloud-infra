# LensCloud Platform Handoff Contract

LensCloud Platform should treat the EU cluster as a registered runtime target.

## Cluster Record

Required fields:

- cluster name: `lenscloud-eu-dev`
- provider: `hcloud`
- region: `eu`
- manager node: `lenscloud-eu-manager-1`
- Headlamp URL: `http://headlamp.eu.lmnaslens.com`
- operator namespace: `frappe-operator-system`
- default runtime namespace: `default` for smoke, later `lenscloud-runtime-eu`
- default storage class: `local-path`
- Kubernetes credential reference: stored server-side only

## Bench Creation Mapping

Platform data maps to `FrappeBench`:

- `Bench.operator_resource_name` -> `metadata.name`
- `Bench.kubernetes_namespace` -> `metadata.namespace`
- `Release Group.registry_url` + `Release Group.image_repository` -> `spec.imageConfig.repository`
- `Release.image_tag` -> `spec.imageConfig.tag`
- `Release.apps` -> `spec.apps`
- `Bench.status` <- `status.phase`
- `Bench.current_release` <- release that produced the active CR
- `Bench.next_release` <- scheduled upgrade candidate

## Site Creation Mapping

Platform data maps to `FrappeSite`:

- `Site.operator_resource_name` -> `metadata.name`
- `Site.site_name` / subdomain -> `spec.siteName`
- `Site.bench` -> `spec.benchRef.name`
- `Site.status` <- `status.phase`
- `Site.dns_status` <- Route53 automation result

## API Boundary

The Frappe frontend must not talk to Kubernetes directly. LensCloud Platform should expose backend methods that:

- create or patch `FrappeBench`
- create or patch `FrappeSite`
- read status from Kubernetes
- record every action in an audit trail

Use idempotent upsert behavior keyed by operator resource name and namespace.

