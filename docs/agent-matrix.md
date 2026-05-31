# LensCloud Infra Agent Matrix

## Purpose

This repo owns the bootstrap and substrate layer for LensCloud. The agent split keeps infrastructure work separate from product behavior.

## Agent Roles

### Infra Bootstrap Agent
- Hcloud provisioning
- cluster bootstrap
- region bring-up
- firewall and network setup
- kubeconfig handoff

### Operator Install Agent
- install the Frappe Operator and required prerequisites
- verify the cluster is ready for product handoff

### SOP/Docs Agent
- bootstrap runbooks
- repeatable install steps
- handoff documentation
- cleanup and recovery notes

