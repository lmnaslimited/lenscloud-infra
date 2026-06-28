# Infra Workitems

This is the single canonical backlog and progress tracker for LensCloud Infra.
Product work is tracked in `lenscloud-platform`.

All Infra requirement changes must update this file first. Supporting SOPs,
contracts, evidence, and prompts are linked from here; they are not separate
backlogs.

## Documentation Control

When adding or changing Infra scope:

1. Add or update a workitem in this file.
2. Link the requirement/source document.
3. Link the implementation SOP or script.
4. Link the verification/evidence document or command.
5. Link the Platform handoff document or prompt when Platform is the consumer.
6. Update `requirements.md` only when the product-level Infra requirement
   changes.
7. Keep detailed runbooks in focused docs, but do not track status there unless
   this backlog points to it.

Status values:

```text
Proposed -> Planned -> In Progress -> Ready for Verification -> Complete
Blocked -> Later
```

## Active Gate

Infra is completing the Bench Command production runner image and live
verification gate for `INF-011`.

The current Infra-to-Platform Bench Command state is:

- `INF-010` Job/ConfigMap contract: Complete
- `bench_test.status` smoke: available to Platform
- production runner source: implemented
- runner image publish/digest pin: complete
- admission image pin: live-applied
- live positive proof: complete for `maintenance_mode.enable` using the pinned
  runner image
- ownership boundary: runner is an Infra-owned helper capability; Platform
  consumes it only through the Bench Command Job/API contract after Infra live
  verification
- supporting handoff: [platform-bench-command-handoff.md](./platform-bench-command-handoff.md)

## Backlog

| ID | Workitem | Requirement / Source | Implementation / SOP | Evidence / Verification | Platform Handoff | Status |
| --- | --- | --- | --- | --- | --- | --- |
| INF-001 | EU K3s substrate | [requirements.md](../requirements.md) | [eu-cluster-sop.md](./eu-cluster-sop.md) | [live-eu-cluster-status.md](./live-eu-cluster-status.md) | [platform-handoff-contract.md](./platform-handoff-contract.md) | Complete |
| INF-002 | Operators and edge | [requirements.md](../requirements.md) | [operator-install-sop.md](./operator-install-sop.md), [traefik-wildcard-tls-sop.md](./traefik-wildcard-tls-sop.md) | [wildcard-edge-contract.md](./wildcard-edge-contract.md) | [platform-handoff-contract.md](./platform-handoff-contract.md) | Complete |
| INF-003 | Restricted Platform access | [platform-restricted-access-contract.md](./platform-restricted-access-contract.md) | [platform-restricted-access-sop.md](./platform-restricted-access-sop.md), `scripts/51-install-platform-access.sh`, `scripts/53-generate-platform-kubeconfig.sh` | `scripts/54-verify-platform-access.sh` | [platform-restricted-access-contract.md](./platform-restricted-access-contract.md) | Complete |
| INF-004 | Runtime lifecycle authority | [platform-runtime-lifecycle-handoff.md](./platform-runtime-lifecycle-handoff.md) | `manifests/access/lenscloud-platform-rbac.yaml` | [platform-runtime-lifecycle-evidence-20260608.md](./platform-runtime-lifecycle-evidence-20260608.md), `scripts/55-verify-platform-lifecycle.sh` | [platform-agent-runtime-lifecycle-prompt.md](./platform-agent-runtime-lifecycle-prompt.md) | Complete |
| INF-005 | Public acceptance cleanup | [platform-live-orchestration-readiness.md](./platform-live-orchestration-readiness.md) | `scripts/56-cleanup-platform-run.sh` | [platform-live-orchestration-readiness.md](./platform-live-orchestration-readiness.md) | [platform-runtime-lifecycle-handoff.md](./platform-runtime-lifecycle-handoff.md) | Complete |
| INF-006 | Private Shared / Private capacity | [database-server-runtime-contract.md](./database-server-runtime-contract.md) | [test-cluster-build-handoff-sop.md](./test-cluster-build-handoff-sop.md) | capacity section in handoff record | [database-server-runtime-contract.md](./database-server-runtime-contract.md) | Complete |
| INF-007 | Fresh test-cluster SOP | [requirements.md](../requirements.md) | [test-cluster-build-handoff-sop.md](./test-cluster-build-handoff-sop.md) | [test-cluster-handoff-record-template.md](./test-cluster-handoff-record-template.md) | Stage 15 in [test-cluster-build-handoff-sop.md](./test-cluster-build-handoff-sop.md) | Complete |
| INF-008 | Additional Platform runtime namespaces | Platform requirement for enterprise/customer namespaces | [platform-runtime-namespace-sop.md](./platform-runtime-namespace-sop.md), `scripts/56-register-platform-runtime-namespace.sh` | `scripts/57-verify-platform-runtime-namespace.sh`, `scripts/54-verify-platform-access.sh` with `RUNTIME_NAMESPACE` | [platform-runtime-namespace-handoff.md](./platform-runtime-namespace-handoff.md) | Complete |
| INF-009 | Legacy namespace inventory | Platform cleanup follow-up from `cleanup-evidence-20260625.md` | admin kubeconfig read-only inventory of `bench-lenscx-eu-public` | [legacy-namespace-inventory-20260625.md](./legacy-namespace-inventory-20260625.md) | no Platform mutation; proposed cleanup commands only for old `default` smoke resources | Complete |
| INF-010 | Bench Command Job/API for Site Controls | Platform Site Control Profile runtime enforcement requirement | [platform-bench-command-handoff.md](./platform-bench-command-handoff.md), `scripts/58-verify-platform-bench-command.sh` | [bench-command-job-evidence-20260625.md](./bench-command-job-evidence-20260625.md) | Platform may run live `bench_test.status`; other families remain runner-pending | Complete |
| INF-011 | Bench Command production runner/API | Platform handoff `infra-handoff-bench-command-production-runner-20260627.md` | [platform-bench-command-handoff.md](./platform-bench-command-handoff.md), `bench-command-runner/`, `scripts/59-test-bench-command-runner-local.sh`, `scripts/60-verify-bench-command-production-runner.sh` | [bench-command-production-runner-evidence-20260627.md](./bench-command-production-runner-evidence-20260627.md) | runner image published, admission-pinned, and live-verified for `maintenance_mode.enable`; Platform may integrate supported runner commands behind policy and per-command acceptance | Complete |
| INF-012 | Documentation governance agent | Traceable CMMI-style documentation control requirement | [documentation-governance-agent.md](./documentation-governance-agent.md) | backlog/document link audit | applies to all future Infra handoffs | Complete |
| INF-013 | US region | regional expansion requirement | TBD | TBD | TBD | Later |
| INF-014 | Local Docker runtime | [local-docker-runtime.md](./local-docker-runtime.md) | TBD | TBD | TBD | Later |

## Protected Baseline

The following remain protected across all Infra workitems unless a future
workitem explicitly changes the architecture:

- `MariaDB/default/frappe-mariadb`
- operator namespaces and CRDs
- Traefik, wildcard TLS, Certbot, and edge infrastructure
- Platform kubeconfig contents and token material
- infrastructure Secrets and private keys
- unlabelled or non-Platform-owned runtime resources

## Current Platform Handoff Prompt

Use [platform-bench-command-handoff.md](./platform-bench-command-handoff.md)
for the next Platform Codex handoff. Platform may integrate supported runner
commands behind Site Control policy and must keep runner-pending families marked
`Unsupported`.
