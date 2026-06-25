# LensCloud Infra Agent Guide

This repository owns the Hcloud and Kubernetes bootstrap layer for LensCloud.

## Own This Repo

- Hetzner Hcloud provisioning
- Cluster bootstrap
- Region bring-up
- Firewall and network setup
- Operator installation
- kubeconfig handoff

## Do Not Put Here

- Customer lifecycle
- Subscription management
- Bench/site UI
- DNS orchestration for customer subdomains
- Product workflow screens

## Read First

- [README.md](./README.md)
- [requirements.md](./requirements.md)
- [docs/agent-handoff.md](./docs/agent-handoff.md)
- [docs/infra-workitems.md](./docs/infra-workitems.md)
- [docs/platform-runtime-lifecycle-handoff.md](./docs/platform-runtime-lifecycle-handoff.md)
- [docs/platform-runtime-namespace-sop.md](./docs/platform-runtime-namespace-sop.md)
- [docs/platform-bench-command-handoff.md](./docs/platform-bench-command-handoff.md)

## Backlog Discipline

`docs/infra-workitems.md` is the single Infra backlog. Before adding a new SOP,
contract, evidence file, script, or Platform handoff prompt, add or update the
matching workitem there and link the supporting artifact. Do not let detailed
docs become separate trackers.
