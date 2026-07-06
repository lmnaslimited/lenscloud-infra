# CUA Site Bootstrap And SSO Implementation Prompt - 2026-07-06

Use this prompt for the next Infra implementation session. This prompt is
intentionally implementation-ready so the next agent can start without another
planning cycle.

```text
Work inside:

/Users/arunkumar.ganesan/lensk8s/lenscloud-infra

Goal:
Implement the first CUA Infra runner gate for Site setup only. Do not implement
OAuth, user/access, or full CUA E2E until the setup wizard proof is complete.

Start by reading, in order:

1. AGENTS.md
2. README.md
3. requirements.md
4. docs/documentation-governance-agent.md
5. docs/infra-workitems.md
6. docs/platform-bench-command-handoff.md
7. docs/cua-site-bootstrap-sso-runner-contract.md
8. lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-site-bootstrap-sso-runner-20260703.md

Documentation discipline:

- Update docs/infra-workitems.md first.
- Keep INF-020 as In Progress while proving image readiness.
- Keep INF-021 Blocked until INF-020 is complete.
- Keep INF-022, INF-023, and INF-024 Blocked until INF-021 has live evidence.
- Do not create standalone trackers outside docs/infra-workitems.md.

Protected baseline:

- Do not mutate or delete MariaDB/default/frappe-mariadb.
- Do not mutate operator namespaces, CRDs, Traefik, wildcard TLS, Certbot, or infrastructure Secrets.
- Do not expose kubeconfig contents, tokens, Secret values, Administrator passwords, OAuth client secrets, DB passwords, private keys, pod logs, raw setup data, raw site_config.json, or full env dumps.

INF-020 tasks:

1. Confirm the new LensPure image tag and digest that includes the branding/bootstrap app.
2. Record the image repository, tag, digest, Frappe version, ERPNext version if present, and branding app version.
3. Run a non-secret bench execution check proving these methods exist:
   - lenscloud_branding.bootstrap.status
   - lenscloud_branding.bootstrap.complete_setup
4. If method names differ, update docs/cua-site-bootstrap-sso-runner-contract.md before implementation.
5. Create a dated evidence file:
   - docs/cua-image-readiness-evidence-YYYYMMDD.md
6. Mark INF-020 Complete only after evidence is captured.

INF-021 tasks:

Only start these after INF-020 is Complete.

1. Add the CUA setup command family to the Bench Command runner allowlist:
   - site_setup.status
   - site_setup.complete
2. Implement typed args validation for setup commands.
3. Use bench-executed branding app methods; do not use target Site HTTP API Administrator login.
4. Ensure unsupported CUA commands return:
   - phase: Unsupported
   - code: COMMAND_UNSUPPORTED
5. Build and publish a new runner image from the verified LensPure base.
6. Pin the new runner digest in admission/RBAC manifests.
7. Live-verify on one real Platform-managed Bench/Site:
   - setup status before completion;
   - setup completion;
   - setup status after completion;
   - idempotent second completion;
   - unsafe request rejection;
   - cleanup of request ConfigMap, Job, and terminal Pod.
8. Create a dated evidence file:
   - docs/cua-site-setup-runner-evidence-YYYYMMDD.md
9. Update docs/platform-bench-command-handoff.md with the final site_setup request/response examples and runner digest.
10. Add or update the Platform handoff prompt for Platform to consume site_setup commands.
11. Mark INF-021 Complete only after implementation, live proof, cleanup, and Platform handoff are complete.

Do not start INF-022, INF-023, or INF-024 in this session unless INF-021 is already complete with evidence.

Future gated work:

- INF-022 oauth.status/oauth.configure should use standard Frappe APIs first.
- INF-023 user.ensure/user.disable/user.roles.set/site_access.status should use standard Frappe APIs first.
- Expand the branding app for OAuth/user only if standard Frappe APIs prove insufficient and the gap is documented.

Final response must include:

- Infra revision;
- INF-020/INF-021 status;
- image tag and digest;
- runner image tag and digest if changed;
- files changed;
- verification summary;
- cleanup proof;
- remaining gaps;
- Platform handoff path and next prompt.
```
