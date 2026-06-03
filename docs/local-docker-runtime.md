# Local Docker Runtime

## Purpose

The platform team needs a standalone local environment for development and testing that is as convenient as the old Docker Swarm setup. The local runtime should let a developer run the LensCloud Kubernetes stack on their own machine with Docker Desktop only, without installing Kubernetes tooling on the host.

This is a planned workstream. It is not implemented yet.

## Core Requirement

Host prerequisites:

- Docker Desktop only.

Host non-requirements:

- no host `kubectl`
- no host `helm`
- no host `k3d`
- no host `kind`
- no host `hcloud`
- no package installation on the Mac or developer machine

All Kubernetes and cluster bootstrap commands should run inside a repo-provided tools container.

## Proposed Architecture

Use a Docker Compose driven local tools profile:

- `lenscloud-local-tools`
  - contains Docker CLI, k3d, kubectl, helm, and basic troubleshooting tools
  - mounts the Docker socket
  - mounts the `lenscloud-infra` repo
  - runs all bootstrap commands from inside the container

- k3d cluster
  - runs K3s in Docker containers
  - starts with one server container and one worker container
  - mirrors the manager/worker shape of the EU Hcloud cluster closely enough for local testing

- Headlamp
  - installed in the local cluster
  - exposed on a localhost port
  - becomes the browser UI for local cluster operations

- Operators
  - MariaDB Operator
  - Frappe Operator
  - same smoke manifests used by the EU runtime where possible

## UI Model

The old Swarm workflow used Portainer and Traefik because they made local operations approachable for the platform team.

For the LensCloud Kubernetes runtime:

- Headlamp is the preferred Kubernetes UI.
- Portainer may be optional for Docker container visibility, but it should not become the Kubernetes source of truth.
- ingress-nginx should remain the default local ingress for parity with the EU runtime.
- A Traefik local profile can be added later if the platform team specifically wants to preserve the previous mental model.

## Planned Files

Proposed additions:

- `local/docker-compose.yml`
- `local/Dockerfile.tools`
- `local/env.example`
- `scripts/local/10-create-k3d-cluster.sh`
- `scripts/local/20-install-ingress.sh`
- `scripts/local/30-install-operators.sh`
- `scripts/local/40-install-headlamp.sh`
- `scripts/local/50-run-smoke.sh`
- `scripts/local/90-destroy-k3d-cluster.sh`
- `docs/local-docker-runtime-sop.md`

## Target Commands

The final SOP should reduce local setup to commands similar to:

```bash
cp local/env.example local/.env
docker compose --project-directory local run --rm tools scripts/local/10-create-k3d-cluster.sh
docker compose --project-directory local run --rm tools scripts/local/20-install-ingress.sh
docker compose --project-directory local run --rm tools scripts/local/30-install-operators.sh
docker compose --project-directory local run --rm tools scripts/local/40-install-headlamp.sh
docker compose --project-directory local run --rm tools scripts/local/50-run-smoke.sh
```

Destroy should be equally explicit:

```bash
docker compose --project-directory local run --rm tools scripts/local/90-destroy-k3d-cluster.sh
```

## Acceptance Criteria

- A developer with Docker Desktop can create the local cluster without installing host packages.
- `kubectl` is available only inside the tools container.
- `helm` is available only inside the tools container.
- k3d runs K3s containers through Docker Desktop.
- Headlamp opens locally in a browser.
- MariaDB Operator is healthy.
- Frappe Operator is healthy.
- The smoke MariaDB, `FrappeBench`, and `FrappeSite` resources can be applied locally.
- The local setup can be destroyed and recreated from the SOP.
- No kubeconfig, token, or generated secret is committed.

## Differences From Hcloud Runtime

The local Docker runtime is for development and platform-team testing. It is not a production topology.

Expected differences:

- no Hcloud network
- no public DNS requirement
- no cloud firewall
- no cloud load balancer
- no production storage guarantee
- no database HA

Expected parity:

- K3s-based Kubernetes
- manager/worker shape where practical
- same operator install path
- same Headlamp operating model
- same Bench/Site smoke resources where possible
- same LensCloud Platform handoff concepts

## Workitems

| Work Item | Owner / Agent | Expected Outcome | Priority | Status |
|---|---|---|---|---|
| Define local runtime design and constraints | Infra Bootstrap Agent + SOP/Docs Agent | Docker-only design is documented and agreed | P0 | Next |
| Add tools container | Infra Bootstrap Agent | Docker CLI, k3d, kubectl, and helm run from a container | P0 | Pending |
| Add k3d local cluster scripts | Infra Bootstrap Agent | One-command local cluster creation and destroy | P0 | Pending |
| Install ingress and Headlamp locally | Infra Bootstrap Agent | Local browser UI is available for Kubernetes operations | P0 | Pending |
| Install MariaDB Operator and Frappe Operator locally | Operator Integration Agent | Operator stack matches EU runtime as closely as possible | P0 | Pending |
| Run local Bench/Site smoke tests | Operator Integration Agent | Local cluster proves core operator workflows | P0 | Pending |
| Document local runtime SOP | Release/SOP Agent | Dev teams can recreate the standalone runtime | P0 | Pending |
