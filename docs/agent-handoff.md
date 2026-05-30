# LensCloud Infra Agent Handoff

## Purpose

This repository is the bootstrap and substrate layer for LensCloud. It should remain small, auditable, and focused on cluster creation and handoff.

## Agent Roles

- Infra Bootstrap Agent: owns Hcloud and Kubernetes bootstrap.
- Operator Install Agent: owns operator installation and verification.
- SOP/Docs Agent: keeps bootstrap steps handoff-ready and repeatable.

## Skills To Associate

- `lenscloud-infra-sop`
- `hcloud-cluster-bootstrap`
- `operator-installation`

## MCPs To Use

- Hcloud access layer for cluster provisioning
- Kubernetes MCP for cluster validation
- GitHub tooling for repo handoff and PRs

## Repo Boundary

- This repo owns cluster bootstrap and handoff only.
- Product behavior belongs in `lenscloud-platform`.

