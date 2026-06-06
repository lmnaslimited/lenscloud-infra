# LensCloud Platform Restricted Cluster Access Contract

## Purpose

LensCloud Platform requires server-side Kubernetes access to reconcile and
observe MariaDB, FrappeBench, FrappeSite, and routing resources. The browser
must never receive Kubernetes credentials.

This document defines the prerequisite that Infra must deliver before the
Platform agent enables real Kubernetes apply.

## Required Infra Artifact

Infra must create a dedicated service account for LensCloud Platform with the
minimum permissions required to:

- read Cluster discovery and health information needed by the client
- get, list, watch, create, patch, and update MariaDB resources
- get, list, watch, create, patch, and update FrappeBench and FrappeSite
- get, list, and watch related Pods, Services, PVCs, Events, Jobs, and Ingresses
- create or update only the runtime Secrets that the approved provisioning
  workflow owns
- read status subresources required for synchronization

It must not grant:

- cluster-admin
- node mutation
- CRD mutation
- operator installation or namespace administration
- unrestricted Secret listing across the cluster
- access to infrastructure-only GoDaddy, Certbot, or wildcard TLS private-key
  Secrets

## Credential Delivery

- Generate a dedicated kubeconfig from the service account.
- Keep the kubeconfig outside Git.
- Deliver it to the Frappe backend as a mounted file or equivalent server-side
  secret.
- Recommended platform reference:
  `file:/run/secrets/lenscloud-eu.kubeconfig`
- Store only that reference in the LensCloud Cluster record.
- Do not store kubeconfig content in a DocType field, action log, manifest
  preview, API response, frontend state, or browser storage.
- Use `lenscloud-runtime-eu` as the controlled Phase 1 runtime namespace.
- The existing shared MariaDB remains in `default`; the credential may reconcile
  that MariaDB but receives no Secret access in `default`.
- Refresh the Hcloud port 6443 source rule with
  `scripts/52-authorize-platform-api.sh` whenever the platform host public IP
  changes. Do not expose the Kubernetes API to `0.0.0.0/0`.
- For mobile development hosts that switch networks, run
  `scripts/52-authorize-platform-api.sh --watch` during the orchestration
  session. It keeps the named rule synchronized to exactly one current `/32`
  without installing host software.

## Handoff Verification

Before Platform enables apply, Infra must publish non-secret evidence that:

1. the service account can read and reconcile the approved runtime resources;
2. it cannot mutate Nodes, CRDs, operator deployments, or unrelated Secrets;
3. the kubeconfig path is readable by the Frappe backend process only;
4. credential rotation and revocation steps are documented;
5. the Cluster handoff identifies the credential reference but not its value.

## Current EU Delivery Status

Delivered and verified on June 6, 2026:

- service account: `lenscloud-platform-system/lenscloud-platform`
- controlled runtime namespace: `lenscloud-runtime-eu`
- credential reference: `file:/run/secrets/lenscloud-eu.kubeconfig`
- kubeconfig stored outside Git and mounted read-only in the Platform
  devcontainer
- required positive permissions passed
- prohibited Node, CRD, namespace, operator, and unrelated Secret permissions
  were denied
- LensCloud's own `KubernetesClient` completed the required MariaDB,
  FrappeBench, and FrappeSite permission checks

The Infra prerequisite is complete. LensCloud reconciliation remains dry-run
until the Platform agent explicitly enables apply for the controlled live
acceptance sequence.

The repeatable commands are in
[platform-restricted-access-sop.md](./platform-restricted-access-sop.md).
