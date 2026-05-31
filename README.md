# LensCloud Infra

LensCloud Infra contains the bootstrap and provisioning layer for the platform.

This repository is responsible for:
- creating Hcloud infrastructure
- bootstrapping Kubernetes clusters
- applying baseline cluster configuration
- installing platform prerequisites
- handing the cluster off to LensCloud Platform

## Responsibilities

- Region bootstrap for US and EU clusters
- Hetzner Hcloud provisioning
- K3s or equivalent cluster bootstrap
- firewall and network setup
- kubeconfig handoff
- baseline storage and ingress setup
- operator installation and cluster registration

## Non-Goals

- Customer onboarding
- Bench and site workflows
- Backup and restore UI
- Frappe business logic
- Platform-team workflow screens

## Initial Requirements

See [requirements.md](./requirements.md).

## Devcontainer

Open this repo in the local devcontainer defined under [`.devcontainer/`](./.devcontainer).

## Agent Handoff

Repo-local agent guidance lives in [AGENTS.md](./AGENTS.md) and [docs/agent-handoff.md](./docs/agent-handoff.md).
The broader operating model is documented in:
- [docs/agent-matrix.md](./docs/agent-matrix.md)
- [docs/skills.md](./docs/skills.md)
- [docs/mcps.md](./docs/mcps.md)
- [docs/state-model.md](./docs/state-model.md)
- [docs/workflows.md](./docs/workflows.md)

## Suggested Stack

- Hcloud CLI or API driven provisioning
- Terraform or shell-based bootstrap depending on maturity
- GitOps or manifest-based cluster registration
- Small bootstrap scripts for day-one installs

## Early Milestones

1. Provision one cluster per region.
2. Bootstrap Kubernetes and base storage.
3. Install Frappe Operator and prerequisites.
4. Register the cluster into LensCloud Platform.
5. Standardize the cluster handoff contract.
