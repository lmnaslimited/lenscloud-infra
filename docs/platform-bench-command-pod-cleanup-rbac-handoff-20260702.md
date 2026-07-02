# Platform Handoff: Bench Command Pod Cleanup RBAC - 2026-07-02

## Source

```text
Infra workitem: INF-019
Infra evidence: docs/bench-command-pod-cleanup-rbac-evidence-20260702.md
Platform source handoff: handoffs/infra/e2e-bench-command-pod-cleanup-rbac-20260702.md
Platform incident: LC-E2E-20260702-003
```

## Resolution

Infra added and live-verified narrow Platform cleanup permission for terminal
Bench Command pods in approved runtime namespaces.

Platform can now delete a Pod only when all of these are true:

```text
namespace has lenscloud.io/managed-runtime=true
pod label lenscloud.io/managed-by=platform
pod label lenscloud.io/resource-kind=bench-command
pod phase is Succeeded or Failed
```

Denied cases verified:

```text
unlabelled terminal pod deletion: denied
non-terminal Platform-labelled pod deletion: denied
pod logs: denied
individual pod get: denied
runtime Secret list: denied
default namespace pod delete: denied
```

## Platform Next Step

Platform may rerun the Bench Command cleanup pass for the final E2E resources.

Expected cleanup order:

1. Capture sanitized command termination summary.
2. Delete the Bench Command Job.
3. Delete the request ConfigMap.
4. Delete terminal Platform-labelled Bench Command Pods.
5. Verify no command Job, ConfigMap, or terminal command Pod remains.
6. Continue reset-clean validation for Bench/Site/PVC lifecycle.

Platform should not ask operators to remove PVC finalizers manually.

## Abridged Platform Agent Prompt

```text
Work inside lenscloud-platform.

Pull latest lenscloud-infra at the commit containing INF-019.

Read:
- lenscloud-infra/docs/infra-workitems.md
- lenscloud-infra/docs/platform-bench-command-pod-cleanup-rbac-handoff-20260702.md
- lenscloud-infra/docs/bench-command-pod-cleanup-rbac-evidence-20260702.md
- apps/lenscloud/docs/handoffs/infra/e2e-bench-command-pod-cleanup-rbac-20260702.md
- apps/lenscloud/docs/incidents/e2e-incident-tracker.md
- apps/lenscloud/docs/evidence/customer-launch/e2e-acceptance-20260702.md

Infra resolved LC-E2E-20260702-003 by adding narrow pod cleanup RBAC/admission.

Update/retry Platform cleanup so it removes terminal Platform-labelled Bench
Command pods after sanitized result capture:
- allowed only for Pods labelled lenscloud.io/managed-by=platform;
- allowed only for Pods labelled lenscloud.io/resource-kind=bench-command;
- allowed only when Pod phase is Succeeded or Failed;
- do not read pod logs;
- do not read/list Secrets;
- do not touch default namespace resources or default/frappe-mariadb;
- do not remove PVC finalizers manually.

Rerun bench_test.status against the Free Plan Site and verify:
1. sanitized result capture;
2. Job absence;
3. ConfigMap absence;
4. terminal command Pod absence;
5. no stuck Bench sites PVC protection during cleanup.

Return:
- final E2E result;
- Orchestration Action Log evidence;
- terminal pod cleanup proof;
- reset-clean inventory;
- any remaining launch blocker.
```

## Remaining Infra Gaps

- Optional TTL policy for completed command Jobs after Platform result capture
  ordering is fully settled.
- Optional periodic orphaned terminal command pod audit.
