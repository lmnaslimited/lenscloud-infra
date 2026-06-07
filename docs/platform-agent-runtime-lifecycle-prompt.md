# Platform Agent Prompt: Runtime Lifecycle and Privacy Acceptance

Use this prompt in the LensCloud Platform devcontainer after the Infra
lifecycle revision reported in the handoff has been fetched.

```text
Work inside:

/workspace/frappe-bench/apps/lenscloud

Start from LensCloud Platform version-16 revision 818c262 or a compatible newer
revision. Treat the adjacent lenscloud-infra checkout as read-only runtime
truth. Confirm it contains:

- docs/platform-runtime-lifecycle-handoff.md
- docs/platform-restricted-access-contract.md
- docs/platform-live-orchestration-readiness.md
- scripts/54-verify-platform-access.sh
- scripts/55-verify-platform-lifecycle.sh

Read:

1. AGENTS.md
2. requirements.md
3. docs/agent-handoff.md
4. docs/platform-workitems.md
5. docs/platform-runtime-lifecycle.md
6. docs/live-orchestration-evidence-20260607.md
7. docs/workflows.md
8. docs/state-model.md
9. docs/database-server-model.md
10. .agents/skills/frappe-ui-product/SKILL.md
11. the five Infra files above

First inspect the current implementation, reconcile the canonical workitems
with actual code, and return a decision-complete plan. Then update workitems to
In Progress and implement without another planning loop unless a genuine
external blocker is found.

Goal:

Complete routine Platform lifecycle ownership and then finish sequential
Private Shared and Private live acceptance. Do not rebuild the existing
orchestration implementation.

Required implementation:

- Add these labels to every generated MariaDB, FrappeBench, and FrappeSite:
  - lenscloud.io/managed-by=platform
  - lenscloud.io/resource-kind
  - lenscloud.io/resource-id
  - lenscloud.io/customer when applicable
- Implement secret-safe runtime inventory for CR conditions, workloads, Jobs,
  PVCs, Services, Ingresses, warning Events, and finalizers.
- Implement server-side Site deletion with exact identity, ownership,
  protected-resource, role, confirmation, and audit checks.
- Implement Bench deletion only after dependent Sites are absent.
- Implement platform-managed Database Server deletion only after attached
  Benches are absent.
- Never mutate or delete MariaDB/default/frappe-mariadb.
- Use asynchronous states: Deletion Requested, Quiescing, Deleting, Deleted,
  and Deletion Failed.
- Prefer owner-CR deletion and normal operator finalizers. Never remove
  finalizers manually as a normal action.
- Add safe retries and Orchestration Action Log entries without credentials or
  Secret values.
- Add compact Frappe UI inspect/delete/progress/retry flows using the repo-local
  Frappe UI skill.
- Customers see product-level Site progress only; runtime internals remain
  platform-only.

Preflight:

- verify the restricted kubeconfig is readable;
- run Infra scripts/54-verify-platform-access.sh;
- confirm Platform backend permission checks match the revised contract:
  default MariaDB is read-only, runtime managed deletes are allowed;
- run migrations, backend tests, frontend build, and authenticated Playwright.

Acceptance:

1. Create a labelled temporary Database Server, Bench, and Site.
2. Inspect related runtime state through Platform.
3. Delete Site through Platform and observe normal finalizer completion.
4. Delete Bench, then the platform-managed Database Server.
5. Prove unlabelled, protected, cross-namespace, and cluster-scoped operations
   are rejected.
6. Run Private Shared live with one customer-owned MariaDB, Quality and
   Production Benches, two HTTPS Sites, and cross-customer rejection.
7. Clean it through Platform.
8. Run Private live with one exclusive MariaDB/Bench/Site and reject every
   second Bench.
9. Clean it through Platform.

Use the approved image:
ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.1
digest sha256:86dd9bec4ef7ef255bff6596b15480e88b3fb27751e1c88b22167ff69fb4a2a2

Do not call DNS provider APIs or create per-Site DNS/certificate resources.
Standard Sites use {subdomain}.cloud.lmnaslens.com and inherited wildcard TLS.

Return:

- code, migration, tests, build, and Playwright results;
- positive/negative lifecycle evidence;
- finalizer and dependent cleanup evidence;
- Private Shared and Private policy/HTTPS evidence;
- action-log references;
- exact cleanup results;
- updated workitems and dated evidence;
- remaining production gaps.
```
