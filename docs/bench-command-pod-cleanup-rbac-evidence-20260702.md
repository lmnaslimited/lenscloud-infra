# Bench Command Pod Cleanup RBAC Evidence - 2026-07-02

## Scope

Infra workitem:

```text
INF-019 Bench Command terminal pod cleanup RBAC
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/e2e-bench-command-pod-cleanup-rbac-20260702.md
```

Related Platform references:

```text
apps/lenscloud/docs/incidents/e2e-incident-tracker.md -> LC-E2E-20260702-003
apps/lenscloud/docs/evidence/customer-launch/e2e-acceptance-20260702.md
apps/lenscloud/docs/handoffs/platform/agent-handoff.md
```

This evidence is non-secret. It does not include kubeconfig contents, tokens,
passwords, database credentials, private keys, Kubernetes Secret values, pod
logs, raw `site_config.json`, backup file contents, or full environment dumps.

## Requirement

Platform needs to complete reset-clean validation without Infra manually
deleting terminal Bench Command pods. The restricted Platform identity must be
able to delete only terminal Platform-labelled Bench Command pods in approved
runtime namespaces.

The fix must not grant:

- pod log access;
- individual pod `get` access;
- Secret list/read outside existing controlled bootstrap access;
- default namespace pod cleanup;
- namespace or cluster infrastructure mutation;
- any access to mutate `default/frappe-mariadb`.

## Implementation

Updated files:

```text
manifests/access/lenscloud-platform-rbac.yaml
scripts/54-verify-platform-access.sh
scripts/56-register-platform-runtime-namespace.sh
scripts/57-verify-platform-runtime-namespace.sh
scripts/63-verify-bench-command-pod-cleanup-rbac.sh
docs/platform-restricted-access-contract.md
docs/platform-restricted-access-sop.md
docs/platform-runtime-namespace-sop.md
docs/platform-bench-command-handoff.md
```

RBAC change:

```text
Role/lenscloud-runtime-eu/lenscloud-platform-runtime:
  pods: list, watch, delete
```

Admission guard:

```text
ValidatingAdmissionPolicy/lenscloud-platform-bench-command-pod-delete
```

The policy allows Platform pod deletion only when all are true:

```text
namespace is selected by lenscloud.io/managed-runtime=true
oldObject.metadata.labels["lenscloud.io/managed-by"] == "platform"
oldObject.metadata.labels["lenscloud.io/resource-kind"] == "bench-command"
oldObject.status.phase in ["Succeeded", "Failed"]
```

## Live Apply

Applied on EU runtime cluster:

```text
namespace/lenscloud-platform-system unchanged
namespace/lenscloud-runtime-eu unchanged
role.rbac.authorization.k8s.io/lenscloud-platform-runtime configured
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-pod-delete created
validatingadmissionpolicybinding.admissionregistration.k8s.io/lenscloud-platform-bench-command-pod-delete created
validatingadmissionpolicy.admissionregistration.k8s.io/lenscloud-platform-bench-command-job-create unchanged
```

## Verification

Standard restricted access verifier:

```text
scripts/54-verify-platform-access.sh
```

Result:

```text
Restricted LensCloud Platform RBAC verification passed for lenscloud-runtime-eu.
```

Bench Command pod cleanup verifier:

```text
scripts/63-verify-bench-command-pod-cleanup-rbac.sh
```

Result:

```text
Bench Command terminal pod cleanup RBAC/admission verification passed.
Runtime namespace: lenscloud-runtime-eu
Positive delete: terminal Platform-labelled Bench Command pod
Negative delete: unlabelled terminal pod denied
Negative delete: non-terminal Platform-labelled pod denied
Negative access: pod logs, get pods, list secrets, and default pod delete denied
Temporary resource prefix: run-20260702-1033-pod-cleanup
```

The verifier uses temporary `run-YYYYMMDD-HHMM-pod-cleanup-*` pods and includes
a cleanup trap for all temporary pods it creates.

## Existing E2E Pods

Platform reported these existing terminal Bench Command pods:

```text
bcmd-2026-00137-job-5pnxl
bcmd-2026-00156-job-9kv4d
bcmd-2026-00201-job-pdw5r
bcmd-2026-00202-job-s2tpd
bcmd-2026-00203-job-5kfxd
```

Infra did not manually delete those pods as part of INF-019. They remain the
Platform validation target for the newly authorized cleanup path.

## Protected Baseline

The implementation did not mutate:

```text
MariaDB/default/frappe-mariadb
PVC/default/storage-frappe-mariadb-0
operator namespaces and CRDs
Traefik, wildcard TLS, Certbot, and edge infrastructure
Kubernetes Secrets or kubeconfig material
```

The live verifier explicitly confirmed that pod logs, individual pod get,
runtime Secret listing, and default namespace pod deletion remain denied.

## Platform Handoff

Platform may now retry cleanup through the restricted Kubernetes API:

1. Capture sanitized command result.
2. Delete command Job and request ConfigMap.
3. Delete terminal Platform-labelled Bench Command pods for the command.
4. Verify no command Job, request ConfigMap, or terminal command pod remains.
5. Continue Bench/Site/PVC reset-clean validation.

Platform must not remove PVC finalizers manually.

## Remaining Gaps

- Consider adding `ttlSecondsAfterFinished` for Platform-created Bench Command
  Jobs once Platform has completed result-capture ordering.
- Consider a periodic Infra audit for orphaned terminal `bcmd-*` pods in
  approved runtime namespaces.
