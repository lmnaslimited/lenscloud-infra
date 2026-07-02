# E2E Cleanup PVC Blocker Evidence - 2026-07-02

## Scope

Infra workitem:

```text
INF-018 Pre-launch E2E cleanup PVC blocker
```

Platform handoff source:

```text
lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/e2e-cleanup-pvc-blocker-20260702.md
```

This evidence is non-secret. It does not include kubeconfig contents, tokens,
passwords, database credentials, private keys, Kubernetes Secret values, pod
logs, raw `site_config.json`, backup file contents, or full environment dumps.

## Problem

Platform deleted the old public Free Plan Site and Bench through Platform
lifecycle APIs, but the Bench sites PVC remained in `Terminating`:

```text
namespace: lenscloud-runtime-eu
pvc: run-20260629-free-prod-bench-sites
pv: pvc-4cf8d4f5-47c7-458a-b82e-30da6c809b3f
storageClass: local-path
finalizer: kubernetes.io/pvc-protection
```

The owner CRs were already absent:

```text
FrappeBench/lenscloud-runtime-eu/run-20260629-free-prod-bench: NotFound
FrappeSite/lenscloud-runtime-eu/run-20260629-free-prod-site: NotFound
```

## Root Cause

The PVC was protected because orphaned terminal Bench Command pods still
referenced the sites PVC.

`kubectl describe pvc` reported these `Used By` pods:

```text
bcmd-2026-00157-job-v4bhf
bcmd-2026-00159-job-8ct57
bcmd-2026-00160-job-rdbmf
bcmd-2026-00161-job-qfgd5
bcmd-2026-00162-job-m6kqz
bcmd-2026-00163-job-zfmdf
bcmd-2026-00164-job-cbb88
bcmd-2026-00165-job-nn7xk
bcmd-2026-00166-job-j8bmt
bcmd-2026-00168-job-gn7db
bcmd-2026-00169-job-wz2jq
bcmd-2026-00170-job-pxcf6
bcmd-2026-00172-job-g77wf
```

Each pod was terminal (`Succeeded` or `Failed`), had no owner reference, and its
Job was already absent. No running application workload was using the PVC.

## Action Taken

Infra deleted only the exact orphaned terminal pods listed above.

No PVC/PV finalizer was removed manually. No FrappeBench or FrappeSite finalizer
was changed. No protected database or cluster infrastructure resource was
mutated.

Cleanup command shape:

```text
kubectl -n lenscloud-runtime-eu delete pod <exact orphaned bcmd pods> --wait=true
```

## Result

After the orphaned pods were removed, Kubernetes completed normal PVC/PV
cleanup:

```text
PersistentVolumeClaim/lenscloud-runtime-eu/run-20260629-free-prod-bench-sites: NotFound
PersistentVolume/pvc-4cf8d4f5-47c7-458a-b82e-30da6c809b3f: NotFound
```

The old owner CRs remained absent:

```text
FrappeBench/lenscloud-runtime-eu/run-20260629-free-prod-bench: NotFound
FrappeSite/lenscloud-runtime-eu/run-20260629-free-prod-site: NotFound
```

Protected baseline remained healthy:

```text
MariaDB/default/frappe-mariadb: Ready=True, Status=Running
PVC/default/storage-frappe-mariadb-0: Bound
```

Restricted Platform access still passed:

```text
scripts/54-verify-platform-access.sh: passed for lenscloud-runtime-eu
```

## Remaining Runtime Inventory

Unrelated remaining resources in `lenscloud-runtime-eu` after blocker cleanup:

```text
pod/bcmd-2026-00137-job-5pnxl: Completed, no PVC mount
pod/bcmd-2026-00156-job-9kv4d: Completed, no PVC mount
PVC/storage-run-iron-monkey-life-db-0: Bound, Used By <none>
```

These resources did not block the deleted Bench sites PVC. They were not
deleted in this incident because the Platform handoff requested investigation
and cleanup of the specific old Free Plan sites PVC blocker.

## Prevention Recommendation

Platform Bench Command cleanup should ensure terminal command pods are removed
after evidence capture, not only Jobs/ConfigMaps. Otherwise completed pods that
mount a Bench sites PVC can keep `kubernetes.io/pvc-protection` active after a
Bench delete.

Recommended Platform behavior:

1. Capture the sanitized termination summary.
2. Delete the command Job and request ConfigMap.
3. Confirm no `job-name=<command-job>` pods remain.
4. For Bench delete/reset flows, confirm no `bcmd-*` pods still reference the
   Bench sites PVC before waiting on PVC deletion.

Recommended Infra follow-up:

- Consider requiring `ttlSecondsAfterFinished` on Platform Bench Command Jobs,
  or add a dedicated cleanup verifier for orphaned terminal command pods.

## Platform Handoff

Platform may proceed with the final E2E reset/launch test against a fresh
baseline for the old public Free Plan Bench/Site, because the specific
terminating sites PVC and PV are gone.

Platform should still decide whether the unrelated old completed command pods
and the old `storage-run-iron-monkey-life-db-0` PVC are part of its broader
reset-clean definition. Infra did not mutate those resources in this incident.
