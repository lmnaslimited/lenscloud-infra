# Platform Runtime Namespace SOP

## Purpose

LensCloud Platform can manage more than one runtime namespace in a cluster.
Infra owns namespace approval and RBAC. Platform discovers and imports only the
Cluster default runtime namespace and namespaces explicitly approved by Infra.

This SOP is for enterprise or customer-dedicated runtime namespaces such as:

- `lenscloud-runtime-eu`
- `lenscloud-enterprise-acme`
- `lenscloud-customer-acme`

Do not grant Platform access to every namespace in the cluster.

## Discovery Labels

Every Platform-approved runtime namespace must have:

```text
lenscloud.io/runtime-namespace=true
lenscloud.io/managed-by=platform
```

Infra also applies the legacy selector label used by the delete admission guard:

```text
lenscloud.io/managed-runtime=true
```

Optional metadata labels:

```text
lenscloud.io/customer=<customer-id>
lenscloud.io/runtime-purpose=<public|private-shared|private|enterprise>
lenscloud.io/region=<region>
lenscloud.io/cluster=<cluster-name>
```

Platform should use these labels to filter namespace choices by customer,
purpose, privacy, Region, and Cluster.

## RBAC Scope

For each approved runtime namespace, Infra grants the existing Platform service
account:

```text
lenscloud-platform-system/lenscloud-platform
```

Allowed in the approved namespace:

- MariaDB CR get/list/watch/create/update/patch/delete
- FrappeBench and FrappeSite get/list/watch/create/update/patch/delete
- Pods, Services, PVCs, Jobs, Ingresses, and Events read access
- terminal Platform-labelled Bench Command Pod delete access
- labelled owned Job and PVC delete access
- runtime Secret get/create/update/patch/delete

Denied:

- namespace create/patch/delete
- CRD mutation
- node mutation
- operator namespace mutation
- default `frappe-mariadb` mutation
- unapproved namespace access
- unrestricted Secret listing
- pod log access

Bench Command Pod deletes are allowed by RBAC in approved runtime namespaces
but constrained by admission. Platform can delete only terminal Pods labelled:

```text
lenscloud.io/managed-by=platform
lenscloud.io/resource-kind=bench-command
```

Platform cannot delete running/non-terminal Pods, unlabelled Pods, or Pods in
`default` and other unapproved namespaces.

Platform has read-only namespace discovery:

```text
get/list/watch namespaces
```

This is intentional so Platform can sync approved Runtime Namespace records by
label. Platform must not show unapproved or system namespaces in user-facing
selection controls.

## Register A Namespace

On an existing cluster, first ensure the current baseline Platform RBAC has
been applied so namespace discovery is read-only allowed:

```bash
./scripts/51-install-platform-access.sh
```

Run from the manager or another Infra admin shell with cluster-admin access:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --customer acme \
  --purpose enterprise \
  --region eu-test \
  --cluster lenscloud-eu-test
```

Customer-dedicated example:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-customer-acme \
  --customer acme \
  --purpose private \
  --region eu-test \
  --cluster lenscloud-eu-test
```

Default runtime namespace refresh:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-runtime-eu \
  --purpose public \
  --region eu-test \
  --cluster lenscloud-eu-test
```

Dry-run:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --customer acme \
  --purpose enterprise \
  --region eu-test \
  --cluster lenscloud-eu-test \
  --dry-run
```

The script creates the namespace if absent or updates labels/RBAC if present.
It does not delete namespaces, workloads, Secrets, PVCs, or
`default/frappe-mariadb`.

## Verify Access

Run the namespace-specific verification with the restricted Platform kubeconfig:

```bash
export PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu-test.kubeconfig

./scripts/57-verify-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --platform-kubeconfig "$PLATFORM_KUBECONFIG"
```

Expected non-secret result:

```text
Platform runtime namespace verification passed.
Namespace: lenscloud-enterprise-acme
Required labels: present
Namespace list: allowed for label discovery
Namespace mutation: denied
Protected MariaDB mutation: denied
Unapproved namespace access checked against: kube-system
```

The baseline verifier can also target the namespace:

```bash
RUNTIME_NAMESPACE=lenscloud-enterprise-acme \
PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu-test.kubeconfig \
./scripts/54-verify-platform-access.sh
```

Bench Command terminal pod cleanup can be verified against the namespace:

```bash
RUNTIME_NAMESPACE=lenscloud-enterprise-acme \
PLATFORM_KUBECONFIG=.artifacts/lenscloud-eu-test.kubeconfig \
./scripts/63-verify-bench-command-pod-cleanup-rbac.sh
```

## Platform Sync Contract

Platform should sync Runtime Namespace records by listing namespaces and
importing only:

1. the Cluster default runtime namespace; or
2. namespaces labelled:

```text
lenscloud.io/runtime-namespace=true
lenscloud.io/managed-by=platform
```

Platform should store:

- namespace name
- Cluster
- Region
- customer label, if present
- runtime-purpose label, if present
- readiness/verification status

Platform should not store or display Kubernetes token data, Secret values, or
raw Secret lists.

## Remove Platform Approval Safely

Removing Platform approval is not the same as deleting the namespace.

To stop new Platform placement while preserving workloads:

```bash
kubectl label namespace lenscloud-enterprise-acme \
  lenscloud.io/runtime-namespace- \
  lenscloud.io/managed-by- \
  --overwrite
```

To revoke Platform Kubernetes access after Platform has quiesced or migrated
workloads:

```bash
kubectl -n lenscloud-enterprise-acme delete rolebinding lenscloud-platform-runtime
kubectl -n lenscloud-enterprise-acme delete role lenscloud-platform-runtime
```

Do not delete the namespace as part of approval rollback. Namespace deletion is
a separate customer/workload retirement activity and must have its own signed
runbook.

## Handoff Evidence

For every new runtime namespace, attach non-secret evidence:

- namespace name;
- labels;
- RoleBinding name;
- verification command and result;
- namespace list allowed/namespace mutation denied result;
- protected `default/frappe-mariadb` mutation denied result;
- customer/purpose/Region/Cluster metadata;
- any capacity warnings.
