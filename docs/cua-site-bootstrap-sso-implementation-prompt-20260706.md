# CUA Site Bootstrap And SSO Implementation Prompt - 2026-07-06

Use this prompt for the next Infra implementation session. This prompt is
intentionally implementation-ready so the next agent can start without another
planning cycle.

```text
Work inside:

/Users/arunkumar.ganesan/lensk8s/lenscloud-infra

Goal:
Implement the first CUA Infra runner gate for Site setup only by using native
Frappe setup wizard APIs. Do not implement OAuth, user/access, or full CUA E2E
until the setup wizard proof is complete.

Start by reading, in order:

1. AGENTS.md
2. README.md
3. requirements.md
4. docs/documentation-governance-agent.md
5. docs/infra-workitems.md
6. docs/platform-bench-command-handoff.md
7. docs/cua-site-bootstrap-sso-runner-contract.md
8. docs/cua-native-setup-api-readiness-20260706.md
9. lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/cua-site-bootstrap-sso-runner-20260703.md

Documentation discipline:

- Update docs/infra-workitems.md first.
- Confirm INF-020 remains Complete and points to native Frappe setup API
  readiness evidence.
- Move INF-021 to In Progress when implementation starts.
- Keep INF-022, INF-023, and INF-024 Blocked until INF-021 has live evidence.
- Do not create standalone trackers outside docs/infra-workitems.md.

Protected baseline:

- Do not mutate or delete MariaDB/default/frappe-mariadb.
- Do not mutate operator namespaces, CRDs, Traefik, wildcard TLS, Certbot, or infrastructure Secrets.
- Do not expose kubeconfig contents, tokens, Secret values, Administrator passwords, OAuth client secrets, DB passwords, private keys, pod logs, raw setup data, raw site_config.json, or full env dumps.

INF-020 status:

Complete. Frappe v16 already provides the required native setup wizard APIs:

- frappe.is_setup_complete
- frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps
- frappe.desk.page.setup_wizard.setup_wizard.setup_complete

Do not wait for a LensCloud branding/bootstrap app for setup wizard completion.

INF-021 tasks:

1. Add the CUA setup command family to the Bench Command runner allowlist:
   - site_setup.status
   - site_setup.complete
2. Implement typed args validation for setup commands.
3. Use bench-executed native Frappe setup methods; do not use target Site HTTP
   API Administrator login.
4. Ensure unsupported CUA commands return:
   - phase: Unsupported
   - code: COMMAND_UNSUPPORTED
5. For site_setup.status, call:
   - frappe.is_setup_complete()
   - get_setup_wizard_pending_apps()
6. For site_setup.complete, call:
   - frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
7. If setup_complete(args) returns {"status": "registered"}, poll
   site_setup.status until complete or timeout.
8. Build and publish a new runner image from the current approved runner base.
   A special LensPure branding/bootstrap image is not required for setup.
9. Pin the new runner digest in admission/RBAC manifests.
10. Live-verify on one real Platform-managed Bench/Site:
    - setup status before completion;
    - setup completion;
    - setup status after completion;
    - idempotent second completion;
    - background setup behavior if enabled;
    - unsafe request rejection;
    - cleanup of request ConfigMap, Job, and terminal Pod.
11. Create a dated evidence file:
    - docs/cua-site-setup-runner-evidence-YYYYMMDD.md
12. Update docs/platform-bench-command-handoff.md with the final site_setup request/response examples and runner digest.
13. Add or update the Platform handoff prompt for Platform to consume site_setup commands.
14. Mark INF-021 Complete only after implementation, live proof, cleanup, and Platform handoff are complete.

Do not start INF-022, INF-023, or INF-024 in this session unless INF-021 is already complete with evidence.

Future gated work:

- INF-022 oauth.status/oauth.configure should use standard Frappe APIs first.
- INF-023 user.ensure/user.disable/user.roles.set/site_access.status should use standard Frappe APIs first.
- Add a branding app for OAuth/user only if standard Frappe APIs prove
  insufficient and the gap is documented.

Final response must include:

- Infra revision;
- INF-020/INF-021 status;
- runner image tag and digest if changed;
- files changed;
- verification summary;
- cleanup proof;
- remaining gaps;
- Platform handoff path and next prompt.
```
