# Platform Handoff: Bench Upgrade Asset Recovery And Runner Sync Follow-Up

Date: 2026-07-19
Source Platform handoff:
`docs/handoffs/infra/bench-upgrade-assets-runner-sync-followup-20260719.md`

## Status

Infra fixed both live blockers from the Platform follow-up:

- Platform service account can now read the cluster runner contract ConfigMap.
- The existing upgraded Bench assets now recover and current CSS/JS URLs return
  HTTP 200.

No new Bench Command runner image digest was required.

## Runner Contract Sync Fix

Infra live-applied:

```text
lenscloud-infra/manifests/access/lenscloud-platform-rbac.yaml
```

The live apply created the previously missing objects:

```text
configmap/lenscloud-platform-cluster-contract
role.rbac.authorization.k8s.io/lenscloud-platform-cluster-contract-read
rolebinding.rbac.authorization.k8s.io/lenscloud-platform-cluster-contract-read
```

Exact RBAC contract:

```text
namespace: lenscloud-platform-system
ServiceAccount: lenscloud-platform
Role: lenscloud-platform-cluster-contract-read
RoleBinding: lenscloud-platform-cluster-contract-read
resource: configmaps
resourceName: lenscloud-platform-cluster-contract
verb: get
```

Live permission evidence:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml auth can-i get \
  configmap/lenscloud-platform-cluster-contract \
  --as system:serviceaccount:lenscloud-platform-system:lenscloud-platform \
  -n lenscloud-platform-system
```

Result:

```text
yes
```

ConfigMap list remains denied:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml auth can-i list configmaps \
  --as system:serviceaccount:lenscloud-platform-system:lenscloud-platform \
  -n lenscloud-platform-system
```

Result:

```text
no
```

Restricted Platform kubeconfig can now read the synced value:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

Platform should now run:

```bash
bench --site dev.localhost execute \
  lenscloud.api.bench_command.sync_cluster_bench_command_runner_contract \
  --args '["lenscloud-eu-dev"]'
```

Expected Cluster fields:

```text
bench_command_runner_contract_status = Synced
bench_command_runner_image = ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
bench_command_runner_contract_error = NULL
```

## Admission Verification

Infra ran the updated live verifier:

```bash
PLATFORM_KUBECONFIG=/root/lenscloud-infra/.artifacts/lenscloud-eu.kubeconfig \
MANAGER_KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
RUNTIME_NAMESPACE=lenscloud-runtime-eu \
/tmp/58-verify-platform-bench-command.sh
```

Result:

```text
Bench Command Job/API RBAC verification passed.
Cluster contract named get via auth can-i: yes
Cluster contract ConfigMap list via auth can-i: no
Accepted Bench Command runner image: ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
Accepted Bench Command runner image for site_setup.status: admitted
Stale Bench Command runner image for site_setup.status: denied
Digest-pinned Release Group runtime image for app-aware bench commands: admitted
Old runner image for app-aware bench commands: denied
Mutable Release Group runtime tag for app-aware bench commands: denied
```

## Existing Bench Asset Recovery

Target:

```text
FrappeBench: run-20260702-free-prod-bench
Namespace: lenscloud-runtime-eu
Expected runtime image: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
```

Before recovery, the Bench already reported:

```text
status.initializedImage = ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
```

However, the Bench had been upgraded before `v4.1.1` asset recovery was
available, so the operator would not automatically rerun init.

Infra triggered one-time operator re-init by patching only the status marker:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n lenscloud-runtime-eu patch frappebench run-20260702-free-prod-bench \
  --subresource=status \
  --type=merge \
  -p '{"status":{"initializedImage":"ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.2"}}'
```

The operator recreated and completed the normal Bench init Job:

```text
Job: run-20260702-free-prod-bench-init
Pod: run-20260702-free-prod-bench-init-9nx9g
Succeeded: 1
Pod exit code: 0
```

Final Bench status:

```text
NAME                           PHASE   TAG        INITIALIZED
run-20260702-free-prod-bench   Ready   v16.14.3   ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
```

Infra then deleted the stale shared Frappe asset resolver cache for the affected
Sites:

```bash
bench --site tharahub.cloud.lmnaslens.com execute \
  frappe.client_cache.delete_value \
  --args '["assets_json"]' \
  --kwargs '{"shared": True}'

bench --site brandkite2e0717.cloud.lmnaslens.com execute \
  frappe.client_cache.delete_value \
  --args '["assets_json"]' \
  --kwargs '{"shared": True}'
```

Then Infra ran:

```bash
bench --site all clear-website-cache
bench --site all clear-cache
kubectl rollout restart deployment/run-20260702-free-prod-bench-gunicorn \
  deployment/run-20260702-free-prod-bench-nginx \
  deployment/run-20260702-free-prod-bench-socketio
```

All three Deployments rolled out successfully.

## Asset Verification

Final live checks from fresh HTML:

```text
tharahub_root=200
tharahub_css=/assets/frappe/dist/css/website.bundle.JTHFRTK2.css 200
tharahub_js=/assets/erpnext/dist/js/bank-reconciliation-tool.bundle.3OD5XE4B.js 200

brandkite2e0717_root=200
brandkite2e0717_css=/assets/frappe/dist/css/website.bundle.JTHFRTK2.css 200
brandkite2e0717_js=/assets/erpnext/dist/js/bank-reconciliation-tool.bundle.3OD5XE4B.js 200
```

Frappe resolver output also returns the new CSS path for both Sites:

```text
/assets/frappe/dist/css/website.bundle.JTHFRTK2.css
/assets/frappe/dist/css/website.bundle.JTHFRTK2.css
```

The previous `D4ZWF75O` CSS hash should now be treated as stale. Platform must
parse fresh HTML and verify the current generated asset URLs.

## Platform Retest

Platform can now proceed with:

1. Run `sync_cluster_bench_command_runner_contract` for `lenscloud-eu-dev`.
2. Confirm Cluster fields show `Synced` and the runner digest above.
3. Retry/continue customer provisioning for
   `brandkite2e0717.cloud.lmnaslens.com`.
4. Confirm generic command families use the synced runner digest:
   `site_setup.status`, `oauth.status`, `oauth.configure`.
5. Confirm app-aware command families continue using Release runtime digests:
   `site_bootstrap.install_apps`, `site_app.install`, `bench.update`,
   `site_setup.complete`.
6. Verify fresh HTML-generated CSS and JS URLs return HTTP 200.

## SOP Update

Infra updated:

```text
lenscloud-infra/docs/test-cluster-build-handoff-sop.md
```

The SOP now includes:

- exact post-digest-pinning apply and admission steps;
- the named ConfigMap `auth can-i get configmap/<name>` check;
- proof that ConfigMap listing remains denied;
- the Platform sync API step after infra admits the digest;
- the one-time asset recovery sequence for Benches upgraded before `v4.1.1`;
- the required `assets_json` cache deletion and web rollout before asset
  readiness verification.
