# Platform Handoff - CUA OAuth Runner - 2026-07-06

## Infra Workitem

`INF-022` CUA OAuth runner gate.

## Status

Ready for Infra live verification, not yet Platform-enabled.

Infra has implemented and locally verified the target Site Social Login Key
runner path:

- `oauth.status`
- `oauth.configure`

Platform must not enable these commands in customer workflows until Infra
applies the admission update and records live verification evidence with:

```text
lenscloud-infra/scripts/65-verify-cua-oauth-runner.sh
```

Published runner image:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner:v0.1.9
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:31973edd01e9c6ea75f2a3b4ef323d5ff643fcec97b2d49b6da9d9d10b7f7580
```

## Ownership Boundary

Platform owns the Platform-side `OAuth Client`.

Infra runner owns the target Site `Social Login Key` only.

Platform should create/maintain the OAuth Client and pass the non-secret target
Social Login Key fields to the runner. Infra runner creates or updates the
target Site `Social Login Key` inside the target Frappe Site.

## Platform Prerequisites

Before calling `oauth.configure`, Platform must have:

- a Platform-owned `OAuth Client`;
- client ID for the target Site Social Login Key;
- client secret stored as a short-lived Kubernetes Secret in the approved
  Runtime Namespace;
- target redirect URL shaped as:

```text
https://<target-site>/api/method/frappe.integrations.oauth2_logins.custom/<provider>
```

The client secret must not be stored in request ConfigMaps, action logs,
browser responses, evidence files, or termination messages.

## Request: `oauth.status`

`oauth.status` does not require a Secret mount.

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260706-OAUTH-STATUS",
  "command": "oauth.status",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "args": {
    "provider": "nectar"
  },
  "timeoutSeconds": 300,
  "requestedBy": "LensCloud Platform"
}
```

## Request: `oauth.configure`

`oauth.configure` requires the OAuth client secret mounted as:

```text
/lenscloud/secrets/client_secret
```

The request ConfigMap must contain only non-secret fields:

```json
{
  "apiVersion": "lenscloud.io/v1",
  "kind": "BenchCommand",
  "commandId": "BCMD-20260706-OAUTH-CONFIGURE",
  "command": "oauth.configure",
  "target": {
    "cluster": "lenscloud-eu-dev",
    "namespace": "lenscloud-runtime-eu",
    "bench": "customer-prod-bench",
    "site": "customer.cloud.lmnaslens.com"
  },
  "args": {
    "provider": "nectar",
    "provider_name": "Nectar",
    "social_login_provider": "Custom",
    "enable_social_login": true,
    "client_id": "platform-oauth-client-id",
    "client_secret_source": "mounted_file",
    "base_url": "https://nectar.lmnas.com",
    "authorize_url": "/api/method/frappe.integrations.oauth2.authorize",
    "access_token_url": "/api/method/frappe.integrations.oauth2.get_token",
    "redirect_url": "https://customer.cloud.lmnaslens.com/api/method/frappe.integrations.oauth2_logins.custom/nectar",
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

If Platform includes `client_secret` in args, the runner rejects the request
with:

```text
phase: Failed
code: INVALID_ARGUMENTS
summary: oauth.configure args must not contain secret values
```

## Job Shape Delta For OAuth

All standard Bench Command Job rules still apply.

Only OAuth configure Jobs may mount the client-secret Secret:

```yaml
volumes:
  - name: oauth-client-secret
    secret:
      secretName: <short-lived-secret-name>
      items:
        - key: client_secret
          path: client_secret
containers:
  - name: bench-command
    env:
      - name: LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH
        value: /lenscloud/secrets/client_secret
    volumeMounts:
      - name: oauth-client-secret
        mountPath: /lenscloud/secrets
        readOnly: true
```

Non-OAuth Secret-volume Jobs are denied by admission.

## Response Shape

Successful status/configure responses are sanitized:

```json
{
  "phase": "Succeeded",
  "command": "oauth.status",
  "summary": "Social login is enabled",
  "changed": false,
  "details": {
    "provider": "nectar",
    "configured": true,
    "enabled": true,
    "provider_name": "Nectar",
    "social_login_provider": "Custom",
    "client_id": "platform-oauth-client-id",
    "base_url": "https://nectar.lmnas.com",
    "authorize_url": "/api/method/frappe.integrations.oauth2.authorize",
    "access_token_url": "/api/method/frappe.integrations.oauth2.get_token",
    "redirect_url": "https://customer.cloud.lmnaslens.com/api/method/frappe.integrations.oauth2_logins.custom/nectar",
    "api_endpoint": "/api/method/frappe.integrations.oauth2.openid_profile",
    "custom_base_url": true,
    "sign_ups": "",
    "secret_configured": true
  },
  "display": {
    "label": "Social login",
    "value": "Enabled",
    "kind": "oauth-status",
    "safe": true
  },
  "redacted": true
}
```

Platform may render `display.value` only when `display.safe=true`.

## Evidence

Infra source evidence:

```text
lenscloud-infra/docs/evidence/cua/oauth-runner-evidence-20260706.md
```

Local proof completed:

- runner syntax validation;
- verifier script syntax validation;
- local `oauth.status`;
- local `oauth.configure`;
- direct `client_secret` arg rejection;
- fake secret value not present in termination summaries.

Live proof remains pending until admission is applied to the cluster and
`scripts/65-verify-cua-oauth-runner.sh` passes.

## Platform Next Step

Do not integrate OAuth as an enabled customer workflow yet.

Prepare Platform code behind a feature gate if useful, but keep runtime OAuth
commands disabled until Infra returns the completed `INF-022` live evidence.

When Infra marks `INF-022` Complete, Platform should:

1. create the Platform OAuth Client;
2. create a short-lived Kubernetes Secret for the target Social Login Key
   client secret;
3. create the `oauth.configure` request ConfigMap and Job through the existing
   Bench Command path;
4. parse only sanitized termination summaries;
5. delete the Job, request ConfigMap, terminal Pod, and short-lived Secret after
   evidence capture;
6. record status, result, and cleanup in Orchestration Action Log.

## Remaining Gaps

- live admission apply;
- live verifier run;
- `INF-023` user/access runner gate;
- `INF-024` full CUA E2E handoff.
