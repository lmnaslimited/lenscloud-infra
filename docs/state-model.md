# LensCloud Infra State Model

## Core Entities

- Region
- Cluster
- Node Pool
- Firewall Rule
- Network
- Storage Class
- Database Runtime
- Ingress
- Wildcard Edge
- Kubeconfig
- Registration / Handoff Record
- Runtime Lifecycle Authority

## Notes

- Infra owns the cluster substrate only.
- Product lifecycle state belongs in `lenscloud-platform`.
- Handoff should be explicit and repeatable.
- Database Runtime handoff includes MariaDB CR identity, Region, Cluster, namespace, image, storage, replicas, service port, secret reference name, and health status, but never secret values.
- LensCloud Platform owns Database Server privacy, sharing, owner, capacity, Bench attachment, and UI lifecycle.
- Wildcard Edge handoff includes root domain, wildcard DNS target/status, ingress controller, issuer, TLS Secret reference/status, and regional routing mode, never API tokens or private keys.
- Runtime Lifecycle Authority includes service-account identity, controlled
  namespace, allowed resource kinds/verbs, ownership-label admission policy,
  protected resources, verification evidence, and credential reference.
- Deletion workflow state remains a LensCloud Platform concern; Infra grants
  and verifies the bounded Kubernetes authority required to execute it.
