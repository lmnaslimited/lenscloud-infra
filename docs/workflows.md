# LensCloud Infra Workflows

## Allowed Now

- create cluster
- bootstrap Kubernetes
- install prerequisites
- register the cluster with LensCloud Platform

## Later

- region expansion
- environment separation refinement
- declarative upgrades
- cluster replacement and migration workflows

## Operational Rules

- Keep bootstrap idempotent where possible.
- Prefer explicit handoff artifacts.
- Do not put customer product logic in this repo.

