# LensCloud Infra State Model

## Core Entities

- Region
- Cluster
- Node Pool
- Firewall Rule
- Network
- Storage Class
- Ingress
- Kubeconfig
- Registration / Handoff Record

## Notes

- Infra owns the cluster substrate only.
- Product lifecycle state belongs in `lenscloud-platform`.
- Handoff should be explicit and repeatable.

