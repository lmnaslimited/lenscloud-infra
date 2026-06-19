# Platform Runtime Namespace Handoff

## Status

Infra now supports onboarding additional Platform runtime namespaces without
changing the restricted kubeconfig context default namespace.

The kubeconfig context may remain:

```text
lenscloud-runtime-eu
```

Access to additional namespaces is granted through namespace-scoped RBAC.

## Scripts

Apply the current baseline Platform RBAC once on existing clusters:

```bash
./scripts/51-install-platform-access.sh
```

Register or update an approved runtime namespace:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --customer acme \
  --purpose enterprise \
  --region eu-test \
  --cluster lenscloud-eu-test
```

Verify with the restricted Platform kubeconfig:

```bash
./scripts/57-verify-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --platform-kubeconfig .artifacts/lenscloud-eu-test.kubeconfig
```

The baseline verifier also accepts:

```bash
RUNTIME_NAMESPACE=lenscloud-enterprise-acme \
./scripts/54-verify-platform-access.sh
```

## Labels

Required for Platform sync:

```text
lenscloud.io/runtime-namespace=true
lenscloud.io/managed-by=platform
```

Infra also keeps:

```text
lenscloud.io/managed-runtime=true
```

Optional metadata:

```text
lenscloud.io/customer=<customer-id>
lenscloud.io/runtime-purpose=<public|private-shared|private|enterprise>
lenscloud.io/region=<region>
lenscloud.io/cluster=<cluster-name>
```

## RBAC Summary

Platform can discover namespaces by label:

```text
get/list/watch namespaces
```

Platform can reconcile runtime CRs and related objects only in approved
runtime namespaces where Infra has installed the RoleBinding.

Platform cannot:

- create, patch, or delete namespaces;
- mutate CRDs, Nodes, StorageClasses, operator deployments, or edge resources;
- mutate `default/frappe-mariadb`;
- access unapproved/system namespaces;
- list Secrets.

Runtime Secret `get/create/update/patch/delete` is allowed only inside approved
runtime namespaces because the operator workflows require controlled Secret
references. Secret values must never be returned to the browser, logs, action
records, or handoff evidence.

## Platform Discovery Recommendation

Platform should prefer namespace-list label discovery using the restricted
kubeconfig. If a future production policy denies namespace listing, Platform
can fall back to explicit Cluster Runtime Namespace registration, but that is
not the current contract.

## Expected Platform UI Behavior

- Runtime Namespace sync imports approved namespaces only.
- The Cluster default runtime namespace is always eligible.
- Namespace choices are filtered by Cluster, Region, customer, purpose, and
  privacy metadata when present.
- Customer users do not see namespace internals.
- Platform operators do not see unapproved/system namespaces in placement
  controls.
- Failed namespace verification blocks live apply into that namespace.

## Platform Agent Prompt

```text
Work inside the LensCloud Platform repo. Treat lenscloud-infra as read-only and
pull the latest Infra commit first.

Read:
- lenscloud-infra/docs/platform-runtime-namespace-sop.md
- lenscloud-infra/docs/platform-runtime-namespace-handoff.md
- lenscloud-infra/docs/platform-restricted-access-contract.md

Implement or verify Runtime Namespace sync from Kubernetes:

1. Use the restricted Cluster kubeconfig server-side only.
2. List namespaces and import only the Cluster default runtime namespace or
   namespaces labelled:
   - lenscloud.io/runtime-namespace=true
   - lenscloud.io/managed-by=platform
3. Store namespace name, Cluster, Region, customer, purpose/privacy metadata,
   and verification status.
4. Do not show unapproved/system namespaces.
5. Do not expose kubeconfig contents, tokens, Secret values, or raw Secret
   lists.
6. Add validation gates so live apply is blocked when the selected Runtime
   Namespace is not approved or RBAC verification fails.
7. Filter Platform namespace choices by customer, purpose/privacy, Region, and
   Cluster metadata.
8. Customer self-service should never expose namespace internals.

Expected Infra scripts:
- scripts/56-register-platform-runtime-namespace.sh
- scripts/57-verify-platform-runtime-namespace.sh
- scripts/54-verify-platform-access.sh with RUNTIME_NAMESPACE override

Return Platform evidence showing:
- approved namespaces imported;
- unapproved/system namespaces hidden;
- namespace-list discovery works;
- namespace mutation remains unavailable;
- placement uses the selected Runtime Namespace safely.
```

## Revision

Record the Git commit containing this file in the Platform handoff ticket after
the Infra change is committed.
