# Documentation Governance Agent

## Purpose

The Documentation Governance Agent protects LensCloud Infra from scattered,
untraceable requirements and handoffs. It keeps the repository at a practical
CMMI level 3 discipline: defined process, single backlog control, traceable
requirements, repeatable evidence, and controlled handoff.

## Authority

`docs/infra-workitems.md` is the single canonical Infra backlog.

No Infra requirement, SOP, script, evidence file, Platform handoff, or live
cluster change is considered active unless it is linked from a workitem in that
file.

## Required Flow

Every change must follow this sequence:

```text
Requirement intake
-> infra-workitems.md workitem
-> supporting contract/SOP/script
-> verification command or evidence file
-> Platform handoff when Platform is the consumer
-> final status update
```

## Workitem Rules

Each active workitem must include:

- stable ID;
- short title;
- requirement/source link;
- implementation/SOP/script link;
- evidence/verification link;
- Platform handoff link when applicable;
- status.

Accepted statuses:

```text
Proposed
Planned
In Progress
Ready for Verification
Complete
Blocked
Later
```

Do not mark a workitem `Complete` unless:

- implementation is done;
- verification evidence is captured;
- temporary test resources are cleaned;
- protected baseline is verified;
- Platform handoff is updated, when Platform is the consumer;
- remaining gaps are documented.

## Document Roles

| Document type | Purpose | Status authority |
| --- | --- | --- |
| `requirements.md` | product-level Infra requirements | no detailed progress |
| `docs/infra-workitems.md` | canonical backlog and progress | authoritative |
| SOP | repeatable operator steps | linked from backlog |
| contract/handoff | boundary between Infra and Platform | linked from backlog |
| evidence | dated proof of verification | linked from backlog |
| incident note | investigation and root cause | linked from backlog if it creates work |

## Intake Checklist

Before implementation, the agent must answer:

- Which backlog ID owns this work?
- Which requirement/source document triggered it?
- What files are expected to change?
- What live resources may be touched?
- What is the protected baseline?
- What verification will prove completion?
- What must Platform receive?

## Completion Checklist

Before final handoff, the agent must update:

- `docs/infra-workitems.md`;
- relevant requirement/contract/SOP docs;
- dated evidence;
- Platform handoff prompt/doc, if applicable.

When Platform is the consumer, maintain the canonical two-copy handoff model:

- source copy in this repo under `docs/handoffs/platform/`;
- Platform-facing copy under
  `lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/`;
- both copies must identify the same Infra workitem and link back to the Infra
  evidence/contract path.

If the Platform checkout is not available, the Infra source handoff must say so
explicitly and include the exact path where Platform must copy it.

The final response must include:

- Infra revision;
- backlog ID and final status;
- files changed;
- verification summary;
- cleanup proof;
- remaining gaps;
- Platform next prompt or handoff path.

## Protected Baseline Reminder

Unless a backlog item explicitly changes architecture, never delete or mutate:

- `MariaDB/default/frappe-mariadb`;
- operator namespaces and CRDs;
- Traefik, wildcard TLS, Certbot, and edge infrastructure;
- Platform kubeconfig contents or token material;
- infrastructure Secrets and private keys;
- unlabelled or non-Platform-owned runtime resources.
