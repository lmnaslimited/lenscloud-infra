# CUA Native Setup API Readiness Evidence - 2026-07-06

## Workitem

`INF-020` CUA native setup API readiness gate.

## Source Reviewed

Local Platform checkout:

```text
lenscloud-platform/frappe-bench/apps/frappe/frappe/desk/page/setup_wizard/setup_wizard.py
lenscloud-platform/frappe-bench/apps/frappe/frappe/__init__.py
lenscloud-platform/frappe-bench/apps/frappe/frappe/core/doctype/installed_applications/installed_applications.py
```

## Finding

Frappe v16 already provides the setup wizard API required for the first CUA
setup runner gate. A separate LensCloud branding/bootstrap app is not required
for setup wizard status or completion.

## Native API Coverage

### Setup Completion

Native method:

```text
frappe.desk.page.setup_wizard.setup_wizard.setup_complete(args)
```

Observed behavior from source:

- returns `{"status": "ok"}` when setup is already complete;
- sanitizes and parses input args;
- runs Frappe global setup tasks;
- runs installed-app `setup_wizard_stages` hooks;
- runs installed-app `setup_wizard_complete` hooks;
- marks installed applications setup-complete;
- runs post setup cleanup;
- supports background execution through `trigger_site_setup_in_background`.

This covers the core `site_setup.complete` requirement.

### Setup Status

Native methods:

```text
frappe.is_setup_complete()
frappe.core.doctype.installed_applications.installed_applications.get_setup_wizard_pending_apps()
```

Observed behavior from source:

- setup completion is derived from `Installed Application.is_setup_complete`;
- Frappe/ERPNext completion is considered through first-class installed app
  setup state;
- pending setup applications can be inspected without a custom app wrapper.

This covers the core `site_setup.status` requirement.

## Runner Implications

`INF-021` should implement the runner by executing native Frappe methods inside
the target Bench/Site context:

- `site_setup.status` should call `frappe.is_setup_complete()` and
  `get_setup_wizard_pending_apps()`.
- `site_setup.complete` should call `setup_complete(args)`.
- If `setup_complete(args)` returns `{"status": "registered"}`, the runner
  should poll `site_setup.status` until complete or timeout.
- The runner must sanitize failures and must not return raw tracebacks, setup
  input dumps, pod logs, `site_config.json`, passwords, tokens, OAuth secrets,
  DB passwords, private keys, or full environment dumps.

## Remaining Validation For INF-021

The local checkout did not include ERPNext, so ERPNext-specific setup args were
not validated from local source. This does not require a branding app, because
Frappe's native setup flow discovers and executes installed-app setup hooks.

The next implementation pass must live-verify on the actual target image/Site:

- required setup args for the installed apps in that image;
- `site_setup.status` before completion;
- `site_setup.complete`;
- `site_setup.status` after completion;
- idempotent second completion;
- background setup behavior if enabled;
- unsafe request rejection;
- cleanup of request ConfigMap, Job, and terminal Pod.

## Decision

Remove the blocking dependency on a new LensPure image containing a
branding/bootstrap app for setup wizard completion.

Keep OAuth and user/access runner work blocked until `INF-021` completes live
setup proof.
