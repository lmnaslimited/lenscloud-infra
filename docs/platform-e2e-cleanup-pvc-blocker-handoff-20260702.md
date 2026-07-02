# Platform Handoff: E2E Cleanup PVC Blocker - 2026-07-02

## Source

```text
Infra workitem: INF-018
Infra evidence: docs/e2e-cleanup-pvc-blocker-evidence-20260702.md
Platform source handoff: handoffs/infra/e2e-cleanup-pvc-blocker-20260702.md
```

## Resolution

The terminating PVC blocker is resolved.

Removed by normal Kubernetes cleanup after Infra deleted only exact orphaned
terminal Bench Command pods that still referenced the old sites PVC:

```text
PersistentVolumeClaim/lenscloud-runtime-eu/run-20260629-free-prod-bench-sites
PersistentVolume/pvc-4cf8d4f5-47c7-458a-b82e-30da6c809b3f
```

Infra did not remove finalizers manually.

Protected baseline remains healthy:

```text
MariaDB/default/frappe-mariadb: Running
PVC/default/storage-frappe-mariadb-0: Bound
```

Restricted Platform access verification still passes for
`lenscloud-runtime-eu`.

## Platform Next Step

Platform may proceed with the final Free Plan E2E reset/launch test for a fresh
public Bench/Site baseline.

Before declaring the broader environment fully reset-clean, Platform should
decide whether these unrelated leftover resources are in scope:

```text
pod/lenscloud-runtime-eu/bcmd-2026-00137-job-5pnxl: Completed, no PVC mount
pod/lenscloud-runtime-eu/bcmd-2026-00156-job-9kv4d: Completed, no PVC mount
PVC/lenscloud-runtime-eu/storage-run-iron-monkey-life-db-0: Bound, Used By <none>
```

Infra did not delete those resources during INF-018 because they were not the
PVC blocker named in the handoff.

## Platform Correction Recommended

Update Platform Bench Command cleanup to remove terminal command pods after
capturing evidence. Deleting only Jobs/ConfigMaps is not enough if orphaned pods
remain and continue to reference a Bench sites PVC.

Minimum behavior:

1. Capture sanitized command result.
2. Delete command Job and request ConfigMap.
3. Verify no pods remain for `job-name=<command-job>`.
4. During Bench delete/reset, verify no `bcmd-*` pod still references the Bench
   sites PVC before waiting for PVC deletion.

## Abridged Platform Agent Prompt

```text
Work inside lenscloud-platform.

Read:
- apps/lenscloud/docs/handoffs/infra/e2e-cleanup-pvc-blocker-20260702.md
- lenscloud-infra/docs/e2e-cleanup-pvc-blocker-evidence-20260702.md
- lenscloud-infra/docs/platform-e2e-cleanup-pvc-blocker-handoff-20260702.md

Infra resolved INF-018. The old sites PVC and PV are gone:
- PVC lenscloud-runtime-eu/run-20260629-free-prod-bench-sites: NotFound
- PV pvc-4cf8d4f5-47c7-458a-b82e-30da6c809b3f: NotFound

Proceed with the final Free Plan E2E reset/launch test.

Also update Platform cleanup logic so Bench Command cleanup verifies terminal
pods are removed after result capture. Deleting Jobs/ConfigMaps alone can leave
orphaned pods that keep pvc-protection active on Bench sites PVCs.

Do not ask operators to remove PVC finalizers manually.
Do not mutate default/frappe-mariadb.

Return:
- final E2E result;
- whether Platform cleanup now removes or verifies command pods;
- any remaining reset-clean resources Platform wants Infra to handle separately.
```
