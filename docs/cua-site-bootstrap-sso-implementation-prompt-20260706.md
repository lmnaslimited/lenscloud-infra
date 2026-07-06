# CUA Site Bootstrap And SSO Implementation Prompt - 2026-07-06

Status: completed for `INF-021`.

This prompt is retained as implementation evidence for the completed CUA Site
setup runner gate. Do not use it as the next active prompt. Future CUA work
starts from `docs/infra-workitems.md`.

Current CUA gate status:

- `INF-021` setup runner: Complete.
- `INF-022` OAuth runner: source/local verification complete; image published
  and repo-pinned; admission apply and live verification remain.
- `INF-023` user/access runner: Blocked until `INF-022` live verification is
  complete.

```text
Work inside:

/Users/arunkumar.ganesan/lensk8s/lenscloud-infra

Goal:
Historical goal:
Complete the first CUA Infra runner gate for Site setup only. This is now
complete. Do not implement OAuth, user/access, or full CUA E2E from this
historical prompt.

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
- INF-021 is now Complete with live evidence.
- INF-022 is Ready for Verification.
- INF-023 is Blocked until INF-022 live verification is complete.
- INF-024 remains Blocked until INF-022 and INF-023 are complete.
- Do not create standalone trackers outside docs/infra-workitems.md.

Protected baseline:

- Do not mutate or delete MariaDB/default/frappe-mariadb.
- Do not mutate operator namespaces, CRDs, Traefik, wildcard TLS, Certbot, or infrastructure Secrets.
- Do not expose kubeconfig contents, tokens, Secret values, Administrator passwords, OAuth client secrets, DB passwords, private keys, pod logs, raw setup data, raw site_config.json, or full env dumps.

INF-020 status:

Complete. Frappe v16 already provides the required native setup wizard APIs:

- frappe.is_setup_complete
- frappe.client_cache.get_doc("Installed Applications")
- frappe.desk.page.setup_wizard.setup_wizard.setup_complete

Do not wait for a LensCloud branding/bootstrap app for setup wizard completion.

INF-021 implemented source:

1. The CUA setup command family is present in the Bench Command runner allowlist:
   - site_setup.status
   - site_setup.complete
2. Typed args validation for setup commands is implemented.
3. The runner uses bench-executed native Frappe setup methods; do not use target Site HTTP
   API Administrator login.
4. Unsupported CUA commands must continue to return:
   - phase: Unsupported
   - code: COMMAND_UNSUPPORTED
5. site_setup.status calls:
   - frappe.is_setup_complete()
   - frappe.client_cache.get_doc("Installed Applications")
6. site_setup.complete calls:
   - frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
7. If setup_complete(args) returns {"status": "registered"}, the runner polls
   site_setup.status until complete or timeout.

INF-021 completed tasks:

1. Build and publish a new runner image from the current approved runner base.
   A special LensPure branding/bootstrap image is not required for setup.
2. Pin the new runner digest in admission/RBAC manifests.
3. Apply the updated RBAC/admission manifest.
4. Live-verify on one real Platform-managed Bench/Site:
    - setup status before completion;
    - setup completion;
    - setup status after completion;
    - idempotent second completion;
    - background setup behavior if enabled;
    - unsafe request rejection;
    - cleanup of request ConfigMap, Job, and terminal Pod.
5. Update evidence:
   - docs/evidence/cua/site-setup-runner-evidence-20260706.md
6. Update docs/platform-bench-command-handoff.md with the final runner digest
   and live status.
7. Update the Platform handoff:
   - docs/handoffs/platform/cua-site-setup-runner-handoff-20260706.md
   - lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/platform/cua-site-setup-runner-20260706.md
8. Mark INF-021 Complete only after implementation, live proof, cleanup, and Platform handoff are complete.

Do not start INF-022, INF-023, or INF-024 in this session unless INF-021 is already complete with evidence.

Future gated work:

- INF-022 oauth.status/oauth.configure uses standard Frappe Social Login Key
  APIs. Platform owns the Platform-side OAuth Client; Infra runner owns the
  target Site Social Login Key.
- INF-023 user.ensure/user.disable/user.roles.set/site_access.status should use
  standard Frappe APIs first.
- Add a branding app for user/access only if standard Frappe APIs prove
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
