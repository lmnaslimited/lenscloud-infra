# LensCloud Infra Requirements

## Product Goal

Provision and bootstrap the Kubernetes substrate that LensCloud Platform will manage.

## Functional Requirements

### Cluster Provisioning
- Create new clusters in Hetzner Cloud.
- Support at least US and EU regions.
- Provide repeatable cluster bootstrap flows.
- Expose a predictable kubeconfig handoff.
- Start with a two-node EU cluster with one manager and one worker.
- Keep routine `kubectl` access on the manager VM, not developer laptops.

### Bootstrap
- Install the base Kubernetes distribution.
- Configure baseline networking and firewall rules.
- Install required storage and ingress primitives.
- Install the Frappe Operator and database operator stack.
- Register the cluster for LensCloud management after bootstrap.
- Expose Headlamp through a dedicated `lmnaslens` subdomain.
- Prepare Headlamp as the first multi-cluster operations UI.
- Keep `lmnaslens.com` authoritative in GoDaddy.
- Configure `cloud.lmnaslens.com` and `*.cloud.lmnaslens.com` in GoDaddy.
- Use Certbot DNS-01 with infrastructure-only GoDaddy production API credentials for the EU wildcard certificate.
- Issue and renew a wildcard certificate for `*.cloud.lmnaslens.com`.
- Prefer Traefik as the target customer-site ingress layer.

### Environment Separation
- Support separate clusters or isolated runtime pools for Quality and Production.
- Support multiple approved runtime namespaces inside a Cluster for
  enterprise/customer-dedicated workloads.
- Support separate runtime and database placement where needed.
- Support region-specific cluster templates.
- Support EU first and US later using the same cluster contract.
- Support first-class MariaDB runtime handoff to LensCloud Platform.
- Support shared MariaDB capacity used by multiple Benches when platform privacy policy permits it.
- Keep operator-managed Database Server and Bench in the same Region and Cluster for the first implementation.

### Operations
- Support idempotent re-runs.
- Support safe upgrades.
- Support teardown with explicit confirmation.
- Produce clear logs and artifacts for handoff.
- Provide non-secret MariaDB CR handoff values and verification commands.
- Provide wildcard DNS, TLS, ingress, and route-readiness handoff values.
- Keep GoDaddy credentials infrastructure-only and out of LensCloud Platform.
- Hand routine runtime lifecycle authority to the dedicated Platform service
  account after cluster registration.
- Permit namespace-scoped create, inspect, reconcile, and delete for
  Platform-owned MariaDB, FrappeBench, and FrappeSite resources.
- Protect `MariaDB/default/frappe-mariadb`, unlabelled resources, cluster
  infrastructure, operators, edge resources, and infrastructure Secrets.
- Enforce the Platform ownership label at admission for direct runtime deletes;
  require LensCloud to enforce document identity, customer/privacy, dependency,
  role, and confirmation policy.
- Allow LensCloud Platform to discover approved Runtime Namespaces by label
  without granting namespace mutation. Platform-approved namespaces must carry
  `lenscloud.io/runtime-namespace=true` and
  `lenscloud.io/managed-by=platform`.
- Provide a secret-safe Bench Command Job/API contract for Platform-approved
  Site Control runtime enforcement. The contract must stay namespace-scoped,
  use an allowlist, validate typed arguments and target Bench/Site identity,
  sanitize status/results, and avoid invented FrappeSite CRD fields.
- Permit Platform to clean up only terminal Platform-labelled Bench Command Pods
  in approved runtime namespaces after sanitized result capture, while denying
  pod logs, unlabelled/running Pod deletion, default namespace cleanup, and
  infrastructure access.

## Requirement Tracking Process

`docs/infra-workitems.md` is the single backlog and status tracker for Infra.
Every SOP, contract, evidence file, and Platform handoff prompt must be linked
from a workitem there. New requirements should not be added as standalone docs
without updating that backlog first.

## Non-Functional Requirements

- No manual host setup once bootstrap is defined.
- Repeatable from source control.
- Prefer declarative configuration over one-off shell.
- Keep the bootstrap surface narrow and auditable.

## Open Decisions

- Terraform vs shell-first bootstrap after the first SOP-backed implementation
- Single-cluster-per-region vs multiple clusters per environment
- Whether cluster registration is pull-based or push-based
- Database HA architecture; do not use NFS as primary database storage by default
- Production NetworkPolicy, TLS, backup, capacity, and isolation profiles for Public, Private Shared, and Private database services
- Multi-region wildcard origin routing before EU and US simultaneously serve the same customer domain
