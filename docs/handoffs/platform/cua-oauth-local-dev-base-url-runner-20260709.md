# Platform Handoff - CUA OAuth Local Dev Base URL Runner - 2026-07-09

## Infra Workitem

`INF-026` CUA OAuth local-dev base URL runner contract.

## Status

Complete.

Infra implemented and locally verified the runner contract requested by
Platform commit range `cdb54d5..b4b8359`. Infra verified the published GHCR
digest, applied the live admission pin on the manager VM, and passed live
verification with the current Platform Settings values.

Published runner image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.11
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef
```

## Contract

The OAuth provider identity and issuer remain sourced from LensCloud Platform
Settings:

```text
oauth_provider_key=<platform-setting-value>
oauth_provider_name=<platform-setting-value>
oauth_base_url=http://dev.localhost:8000
allow_local_oauth_http=true
```

Platform must pass those settings to `oauth.configure` as:

```json
{
  "provider": "<oauth_provider_key>",
  "provider_name": "<oauth_provider_name>",
  "base_url": "http://dev.localhost:8000",
  "allow_local_oauth_http": true
}
```

The target redirect URL remains:

```text
<site.access_url>/api/method/frappe.integrations.oauth2_logins.custom/<oauth_provider_key>
```

Infra must not hard-code the provider key, provider name, or issuer URL. The
runner validates and applies the values Platform sends from Platform Settings.

HTTPS `base_url` remains accepted without the local-dev flag. Plain HTTP is
accepted only when:

- `allow_local_oauth_http` is JSON boolean `true`; and
- `base_url` is localhost/local-dev, such as `http://localhost:<port>`,
  `http://*.localhost:<port>`, `http://dev.localhost:<port>`, or a loopback IP.

If the flag is missing or false, local HTTP is rejected. Non-local plain HTTP
is rejected even when the flag is true. Production/non-local issuers remain
HTTPS-only.

## Request Shape

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-LOCAL-DEV-OAUTH-CONFIGURE",
  "command": "oauth.configure",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "<target-bench>",
    "site": "run-20260707-cua-oauth.cloud.lmnaslens.com"
  },
  "args": {
    "provider": "<oauth_provider_key>",
    "provider_name": "<oauth_provider_name>",
    "social_login_provider": "Custom",
    "enable_social_login": true,
    "client_id": "<platform-oauth-client-id>",
    "client_secret_source": "mounted_file",
    "base_url": "http://dev.localhost:8000",
    "allow_local_oauth_http": true,
    "authorize_url": "/api/method/frappe.integrations.oauth2.authorize",
    "access_token_url": "/api/method/frappe.integrations.oauth2.get_token",
    "redirect_url": "https://run-20260707-cua-oauth.cloud.lmnaslens.com/api/method/frappe.integrations.oauth2_logins.custom/<oauth_provider_key>",
    "api_endpoint": "/api/method/frappe.integrations.oauth2.openid_profile",
    "custom_base_url": true,
    "auth_url_data": {
      "response_type": "code",
      "scope": "openid"
    },
    "sign_ups": ""
  },
  "timeoutSeconds": 300,
  "requestedBy": "LensCloud Platform"
}
```

The OAuth client secret must still be mounted only at:

```text
/lenscloud/secrets/client_secret
```

Do not put `client_secret` in request args, action logs, browser responses,
evidence, or termination messages.

## Evidence

Infra evidence:

```text
lenscloud-infra/docs/evidence/cua/oauth-local-dev-base-url-runner-evidence-20260709.md
```

Local proof completed:

- `oauth.configure` accepts `http://dev.localhost:8000` with
  `allow_local_oauth_http=true`;
- local fake target state reports the Platform-provided provider key and
  `base_url=http://dev.localhost:8000`;
- local HTTP is rejected when the flag is absent;
- local HTTP is rejected when the flag is false;
- non-local HTTP is rejected when the flag is true;
- direct `client_secret` args are rejected;
- runner and verifier scripts pass syntax checks;
- no secret-like values appeared in local termination summaries.

Live proof passed on 2026-07-10:

```text
oauth_provider_key=lenscloud
oauth_provider_name=LensCloud
oauth_base_url=http://dev.localhost:8000
allow_local_oauth_http=true
Site: run-20260707-cua-oauth.cloud.lmnaslens.com
Verifier Site: tara-communo-hub.cloud.lmnaslens.com
Bench: run-20260702-free-prod-bench
Sites PVC: run-20260702-free-prod-bench-sites
OAuth client ID: 08riiahaab
Temporary resource prefix: run-20260710-cua-oauth-local-http
```

```text
CUA OAuth runner verification passed.
Positive commands: oauth.status, oauth.configure with base_url=http://dev.localhost:8000 and allow_local_oauth_http=true
Negative checks: local HTTP without allow_local_oauth_http rejected; local HTTP with allow_local_oauth_http=false rejected; non-local HTTP with allow_local_oauth_http rejected; direct client_secret arg rejected; non-oauth Secret volume denied
```

Cleanup proof: no Jobs, ConfigMaps, Pods, or exact short-lived Secret remain
for `run-20260710-cua-oauth-local-http`.

## Platform Resume Point

Platform should rerun:

1. `oauth.status` for the Platform Settings `oauth_provider_key`.
2. `configure_site_oauth` on
   `run-20260707-cua-oauth.cloud.lmnaslens.com`.
3. Final `oauth.status` for the Platform Settings `oauth_provider_key`.
4. Customer browser check: open the Site URL, click `Login with LensCloud`, and
   confirm the customer reaches the Site without entering a Site-local
   password.

Do not delete the fresh Site; keep it for `INF-023` user/access validation.

## Remaining Gaps

- `INF-023` user/access runner gate.
