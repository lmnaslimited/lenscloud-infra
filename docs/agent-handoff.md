# LensCloud Infra Agent Handoff

## Purpose

This repository is the bootstrap and substrate layer for LensCloud. It should remain small, auditable, and focused on cluster creation and handoff.

## Agent Roles

- Infra Bootstrap Agent: owns Hcloud and Kubernetes bootstrap.
- Operator Install Agent: owns operator installation and verification.
- Database Runtime Agent: owns MariaDB Operator runtime templates, verification, and non-secret handoff.
- Edge/TLS Agent: owns wildcard DNS verification, wildcard certificate, ingress, and edge health.
- SOP/Docs Agent: keeps bootstrap steps handoff-ready and repeatable.

## Skills To Associate

- `lenscloud-infra-sop`
- `hcloud-cluster-bootstrap`
- `operator-installation`
- `mariadb-runtime-handoff`
- `wildcard-edge`

## MCPs To Use

- Hcloud access layer for cluster provisioning
- Kubernetes MCP for cluster validation
- GitHub tooling for repo handoff and PRs

## Repo Boundary

- This repo owns cluster bootstrap and handoff only.
- Product behavior belongs in `lenscloud-platform`.
- `docs/infra-workitems.md` is the single backlog and progress tracker. New
  requirements, SOPs, contracts, evidence files, and Platform handoff prompts
  must be linked from that backlog before they are treated as active work.
- Database Server privacy, ownership, capacity policy, and Bench attachment belong in `lenscloud-platform`.
- Read `docs/database-server-runtime-contract.md` before changing MariaDB smoke resources or platform handoff values.
- Read `docs/wildcard-edge-contract.md` before changing ingress, DNS, TLS, or Site routing.
- Read `docs/platform-restricted-access-contract.md` before handing Kubernetes
  credentials to LensCloud Platform.
- Read `docs/platform-runtime-lifecycle-handoff.md` before changing runtime
  CRUD/delete permissions or Platform ownership boundaries.
- Read `docs/platform-runtime-namespace-sop.md` before approving additional
  Platform runtime namespaces or changing namespace discovery labels/RBAC.
- Read `docs/platform-bench-command-handoff.md` before changing Bench Command
  Job/API permissions, admission guardrails, or Site Control runtime handoff.
- Track active Infra milestones in `docs/infra-workitems.md`.
- Use `docs/test-cluster-build-handoff-sop.md` and its handoff record template
  for fresh project/cluster acceptance; do not reconstruct the process from
  incident notes.
- Preserve the DNS ownership boundary: GoDaddy owns DNS and infrastructure-only
  ACME credentials; LensCloud Platform owns neither DNS records nor provider
  credentials for standard Sites.
