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
- Shell-based bootstrap for the first EU cluster
- GitOps or manifest-based cluster registration
- Small bootstrap scripts for day-one installs

## EU Runtime Cluster

The first live runtime target is a two-node EU K3s cluster:

- manager: `lenscloud-eu-manager-1`
- worker: `lenscloud-eu-worker-1`
- current Headlamp: `https://headlamp.cloud.lmnaslens.com`
- ingress: Traefik with wildcard HTTPS

Current live status is captured in [docs/live-eu-cluster-status.md](./docs/live-eu-cluster-status.md).

Recreate it with [docs/eu-cluster-sop.md](./docs/eu-cluster-sop.md).

Supporting SOPs:

- [docs/test-cluster-build-handoff-sop.md](./docs/test-cluster-build-handoff-sop.md)
- [docs/test-cluster-handoff-record-template.md](./docs/test-cluster-handoff-record-template.md)
- [docs/operator-install-sop.md](./docs/operator-install-sop.md)
- [docs/headlamp-sop.md](./docs/headlamp-sop.md)
- [docs/bench-site-smoke-sop.md](./docs/bench-site-smoke-sop.md)
- [docs/platform-handoff-contract.md](./docs/platform-handoff-contract.md)
- [docs/platform-restricted-access-contract.md](./docs/platform-restricted-access-contract.md)
- [docs/platform-restricted-access-sop.md](./docs/platform-restricted-access-sop.md)
- [docs/platform-live-orchestration-readiness.md](./docs/platform-live-orchestration-readiness.md)
- [docs/platform-runtime-lifecycle-handoff.md](./docs/platform-runtime-lifecycle-handoff.md)
- [docs/platform-runtime-namespace-sop.md](./docs/platform-runtime-namespace-sop.md)
- [docs/platform-runtime-namespace-handoff.md](./docs/platform-runtime-namespace-handoff.md)
- [docs/platform-bench-command-handoff.md](./docs/platform-bench-command-handoff.md)
- [docs/cua-site-bootstrap-sso-runner-contract.md](./docs/cua-site-bootstrap-sso-runner-contract.md)
- [docs/cua-native-setup-api-readiness-20260706.md](./docs/cua-native-setup-api-readiness-20260706.md)
- [docs/cua-site-bootstrap-sso-implementation-prompt-20260706.md](./docs/cua-site-bootstrap-sso-implementation-prompt-20260706.md)
- [docs/evidence/cua/site-setup-runner-evidence-20260706.md](./docs/evidence/cua/site-setup-runner-evidence-20260706.md)
- [docs/handoffs/platform/cua-site-setup-runner-handoff-20260706.md](./docs/handoffs/platform/cua-site-setup-runner-handoff-20260706.md)
- [docs/evidence/cua/oauth-runner-evidence-20260706.md](./docs/evidence/cua/oauth-runner-evidence-20260706.md)
- [docs/handoffs/platform/cua-oauth-runner-handoff-20260706.md](./docs/handoffs/platform/cua-oauth-runner-handoff-20260706.md)
- [docs/bench-command-job-evidence-20260625.md](./docs/bench-command-job-evidence-20260625.md)
- [docs/bench-command-production-runner-evidence-20260627.md](./docs/bench-command-production-runner-evidence-20260627.md)
- [docs/bench-command-pod-cleanup-rbac-evidence-20260702.md](./docs/bench-command-pod-cleanup-rbac-evidence-20260702.md)
- [docs/platform-bench-command-pod-cleanup-rbac-handoff-20260702.md](./docs/platform-bench-command-pod-cleanup-rbac-handoff-20260702.md)
- [docs/documentation-governance-agent.md](./docs/documentation-governance-agent.md)
- [docs/platform-runtime-lifecycle-evidence-20260608.md](./docs/platform-runtime-lifecycle-evidence-20260608.md)
- [docs/platform-agent-runtime-lifecycle-prompt.md](./docs/platform-agent-runtime-lifecycle-prompt.md)
- [docs/infra-workitems.md](./docs/infra-workitems.md)
- [docs/incidents/2026-06-06-public-site-assets.md](./docs/incidents/2026-06-06-public-site-assets.md)
- [docs/database-server-runtime-contract.md](./docs/database-server-runtime-contract.md)
- [docs/wildcard-edge-contract.md](./docs/wildcard-edge-contract.md)
- [docs/traefik-wildcard-tls-sop.md](./docs/traefik-wildcard-tls-sop.md)

Local Docker-only runtime planning is tracked in [docs/local-docker-runtime.md](./docs/local-docker-runtime.md). This workstream is for standalone developer setups that use Docker Desktop only, with Kubernetes tooling running inside repo-provided containers rather than on the host machine.

## Early Milestones

1. Provision one cluster per region.
2. Bootstrap Kubernetes and base storage.
3. Install Frappe Operator and prerequisites.
4. Register the cluster into LensCloud Platform.
5. Standardize the cluster handoff contract.
