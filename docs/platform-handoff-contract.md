# LensCloud Platform Handoff Contract

LensCloud Platform should treat the EU cluster as a registered runtime target.

## Cluster Record

Required fields:

- cluster name: `lenscloud-eu-dev`
- provider: `hcloud`
- region: `eu`
- manager node: `lenscloud-eu-manager-1`
- Headlamp URL: `https://headlamp.cloud.lmnaslens.com`
- operator namespace: `frappe-operator-system`
- default runtime namespace: `default` for smoke, later `lenscloud-runtime-eu`
- default storage class: `local-path`
- target Kubernetes credential reference:
  `file:/run/secrets/lenscloud-eu.kubeconfig`

The restricted service-account kubeconfig is a required external prerequisite,
not a committed repo artifact. Its contract is defined in
[platform-restricted-access-contract.md](./platform-restricted-access-contract.md).
Infra delivered and verified this prerequisite on June 6, 2026. Real Platform
apply should remain disabled until the Platform agent runs its own permission
preflight, confirms capacity, and begins the controlled live acceptance
sequence.

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
- `Bench.database_server` -> selected Database Server runtime
- `Database Server.operator_resource_name` -> `spec.dbConfig.mariadbRef.name`
- `Database Server.kubernetes_namespace` -> `spec.dbConfig.mariadbRef.namespace`

The Bench and operator-managed Database Server must resolve to the same Region and Cluster in the first implementation.

## Database Server Mapping

Platform data maps to MariaDB Operator:

- `Database Server.operator_resource_name` -> `MariaDB.metadata.name`
- `Database Server.kubernetes_namespace` -> `MariaDB.metadata.namespace`
- image/tag -> `MariaDB.spec.image`
- storage size/class -> `MariaDB.spec.storage`
- replica count -> `MariaDB.spec.replicas`
- root credential Secret reference -> `MariaDB.spec.rootPasswordSecretKeyRef`
- status/health <- MariaDB CR status

The live first handoff is documented in [database-server-runtime-contract.md](./database-server-runtime-contract.md).

Multiple Benches may reference one MariaDB CR when LensCloud privacy and capacity policy permits. Raw passwords are never part of this handoff.

## Site Creation Mapping

Platform data maps to `FrappeSite`:

- `Site.operator_resource_name` -> `metadata.name`
- `Site.site_name` / subdomain -> `spec.siteName`
- `Site.bench` -> `spec.benchRef.name`
- `Site.status` <- `status.phase`
- `Site.hostname` -> `{subdomain}.cloud.lmnaslens.com`
- route/access status <- ingress and HTTP/TLS readiness

Standard Site creation does not create DNS records or certificates. It relies on the shared wildcard DNS and wildcard TLS contract in [wildcard-edge-contract.md](./wildcard-edge-contract.md).

## Wildcard Edge Handoff

- root domain: `cloud.lmnaslens.com`
- wildcard DNS: `*.cloud.lmnaslens.com`
- DNS provider: GoDaddy, infrastructure-owned
- wildcard target: `116.203.22.81`
- ingress: Traefik
- ingress class: `traefik`
- entrypoints: `web`, `websecure`
- certificate lifecycle: Certbot DNS-01 with infra-only GoDaddy production API credentials
- certificate names: `cloud.lmnaslens.com`, `*.cloud.lmnaslens.com`
- TLS Secret: `traefik/lenscloud-cloud-wildcard-tls`
- per-Site DNS/certificate creation: disabled

LensCloud Platform creates Site/runtime/routing resources only. Infra owns shared wildcard DNS, issuer, certificate renewal, and ingress readiness.

Current readiness:

- restricted Platform service account and RBAC: Ready
- restricted kubeconfig delivered and mounted read-only: Ready
- host-side positive and negative permission verification: Passed
- LensCloud backend Kubernetes client permission verification: Passed
- shared MariaDB Bench/Site contract: Ready
- Traefik ingress class and dynamic host routing: Ready
- public Traefik cutover: Ready
- wildcard DNS target: Ready
- wildcard TLS Secret: Ready
- wildcard TLS expiry: September 3, 2026 at 14:49 UTC
- Certbot renewal dry-run: Passed
- Headlamp HTTPS: Ready
- ingress-nginx: removed after successful rollback rehearsal

LensCloud may mark the EU Phase 1 edge `Ready`. It should continue to monitor
certificate expiry, renewal Job status, ingress health, and route health.

## API Boundary

The Frappe frontend must not talk to Kubernetes directly. LensCloud Platform should expose backend methods that:

- create or patch `FrappeBench`
- create or patch `FrappeSite`
- create, register, or patch MariaDB resources
- read status from Kubernetes
- record every action in an audit trail
- read shared wildcard DNS/TLS/ingress readiness

Use idempotent upsert behavior keyed by operator resource name and namespace.

## Privacy Acceptance Handoff

The Platform milestone must prove all three LensCloud privacy policies:

- `Public`: existing `default/frappe-mariadb` may serve Benches from unrelated
  customers while Sites retain distinct logical databases and credentials.
- `Private Shared`: one customer-owned MariaDB may serve multiple Benches owned
  by that customer, and must reject another customer.
- `Private`: one MariaDB is exclusive to one Bench and must reject every second
  Bench, including one owned by the same customer.

MariaDB Operator/Frappe Operator `mode: shared` describes database topology. It
does not override these LensCloud ownership and placement rules.
