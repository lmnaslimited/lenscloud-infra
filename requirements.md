# LensCloud Infra Requirements

## Product Goal

Provision and bootstrap the Kubernetes substrate that LensCloud Platform will manage.

## Functional Requirements

### Cluster Provisioning
- Create new clusters in Hetzner Cloud.
- Support at least US and EU regions.
- Provide repeatable cluster bootstrap flows.
- Expose a predictable kubeconfig handoff.

### Bootstrap
- Install the base Kubernetes distribution.
- Configure baseline networking and firewall rules.
- Install required storage and ingress primitives.
- Install the Frappe Operator and database operator stack.
- Register the cluster for LensCloud management after bootstrap.

### Environment Separation
- Support separate clusters or isolated runtime pools for Quality and Production.
- Support separate runtime and database placement where needed.
- Support region-specific cluster templates.

### Operations
- Support idempotent re-runs.
- Support safe upgrades.
- Support teardown with explicit confirmation.
- Produce clear logs and artifacts for handoff.

## Non-Functional Requirements

- No manual host setup once bootstrap is defined.
- Repeatable from source control.
- Prefer declarative configuration over one-off shell.
- Keep the bootstrap surface narrow and auditable.

## Open Decisions

- Terraform vs shell-first bootstrap
- Single-cluster-per-region vs multiple clusters per environment
- Whether DNS is managed here or by a separate automation layer
- Whether cluster registration is pull-based or push-based

