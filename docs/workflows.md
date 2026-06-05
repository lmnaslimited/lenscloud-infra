# LensCloud Infra Workflows

## Allowed Now

- create cluster
- bootstrap Kubernetes
- install prerequisites
- register the cluster with LensCloud Platform
- create/register and verify MariaDB runtime capacity
- hand Database Server runtime metadata to LensCloud Platform
- configure and verify one wildcard DNS record
- issue and renew wildcard TLS through DNS-01
- hand wildcard edge readiness to LensCloud Platform

## Later

- region expansion
- environment separation refinement
- declarative upgrades
- cluster replacement and migration workflows

## Operational Rules

- Keep bootstrap idempotent where possible.
- Prefer explicit handoff artifacts.
- Do not put customer product logic in this repo.
- Do not encode Public, Private Shared, or Private commercial policy in bootstrap scripts; Platform owns that policy.
- Keep MariaDB data off NFS by default.
- Prove that multiple Benches can reference one MariaDB CR before designing HA.
- Do not create per-Site DNS records or certificates for standard customer Sites.
- Do not remove shared wildcard DNS, issuer, or TLS resources during Site deletion.
