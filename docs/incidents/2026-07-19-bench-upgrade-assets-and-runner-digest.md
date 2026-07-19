# Bench Upgrade Assets And Runner Digest Incidents

Date: 2026-07-19

## INC-20260719-001: Generated Assets Missing After Bench Upgrade

Status: Resolved live for the reported Bench; Platform retest pending.

Platform upgraded `run-20260702-free-prod-bench` to Release
`RELEASE-lens-pure-v16.14.3-1` using runtime image digest
`sha256:92196b4fb5c016e006c0bddc7ecffd6ba4ad8ce23c6ad290e81840fea0f6bca0`.
The root HTML for affected Sites returned HTTP 200, but generated CSS assets
under `/assets/frappe/dist/css/` and `/assets/erpnext/dist/css/` returned HTTP
404.

Infra live-tested upstream Frappe Operator `v4.1.1` on the manager cluster.
The operator recreated the Bench init Job after the Bench runtime image tag was
changed from `v16.14.2` to `v16.14.3`, updated
`FrappeBench.status.initializedImage`, and restored assets from
`/home/frappe/assets_cache` into the shared `sites/assets` PVC.

Evidence:

```text
Bench: run-20260719-v411-072443-bench
Site: run-20260719-v411-072443-site.cloud.lmnaslens.com
Initial image: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.2
Final image: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
Final initializedImage: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
Migration Job exit code: 0
Site root HTTP: 200
CSS asset HTTP: 200
CSS asset: /assets/frappe/dist/css/website.bundle.JTHFRTK2.css
assets.json on PVC: non-empty
```

Follow-up live recovery for the already-upgraded Bench:

```text
Bench: run-20260702-free-prod-bench
Namespace: lenscloud-runtime-eu
Operator init Job: run-20260702-free-prod-bench-init
Init pod: run-20260702-free-prod-bench-init-9nx9g
Init pod exit code: 0
Final initializedImage: ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.3
```

Because this Bench had already reached `initializedImage=v16.14.3` before the
operator rollout, Infra reset only the status marker to trigger v4.1.1 re-init,
then deleted the stale shared Frappe `assets_json` cache key and rolled
gunicorn/nginx/socketio.

Final live asset checks:

```text
tharahub_root=200
tharahub_css=/assets/frappe/dist/css/website.bundle.JTHFRTK2.css 200
tharahub_js=/assets/erpnext/dist/js/bank-reconciliation-tool.bundle.3OD5XE4B.js 200
brandkite2e0717_root=200
brandkite2e0717_css=/assets/frappe/dist/css/website.bundle.JTHFRTK2.css 200
brandkite2e0717_js=/assets/erpnext/dist/js/bank-reconciliation-tool.bundle.3OD5XE4B.js 200
```

## INC-20260719-002: Bench Command Runner Digest Contract Not Discoverable

Status: Resolved live; Platform sync/retest pending.

Platform-generated `site_setup.complete` Jobs use the generic Bench Command
runner image. Admission requires an exact digest-pinned runner image, but
Platform currently has no cluster-readable source of truth for the accepted
digest and cannot distinguish a stale digest from other admission-policy
denials without parsing the raw Kubernetes error.

Infra added the cluster contract ConfigMap readable by the Platform service
account and verifier coverage for admitted and stale runner digests.

Platform must read:

```text
namespace: lenscloud-platform-system
name: lenscloud-platform-cluster-contract
key: bench_command_runner_image
```

Current admitted runner digest:

```text
ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:0ba81c0f4031d452eab71a463a562d5f07ace308ae87967725dd807e00c97570
```

If server-side dry-run is denied with admission text containing
`approved execution image`, Platform must classify the failure as
`BENCH_COMMAND_RUNNER_IMAGE_REJECTED`.

Follow-up live fix:

```text
configmap/lenscloud-platform-cluster-contract created
role.rbac.authorization.k8s.io/lenscloud-platform-cluster-contract-read created
rolebinding.rbac.authorization.k8s.io/lenscloud-platform-cluster-contract-read created
named ConfigMap get as Platform service account: yes
ConfigMap list as Platform service account: no
restricted Platform kubeconfig read: succeeded
scripts/58-verify-platform-bench-command.sh: passed
```
