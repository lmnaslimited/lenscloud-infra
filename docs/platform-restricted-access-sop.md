# LensCloud Platform Restricted Access SOP

## Purpose

Create and deliver the least-privilege EU Kubernetes credential consumed by the
LensCloud Frappe backend. Kubernetes commands run on the EU manager. The
kubeconfig is copied to the platform host outside Git and mounted read-only into
the devcontainer.

## Variables

```bash
export MANAGER_HOST=root@116.203.22.81
export HCLOUD_FIREWALL=lenscloud-eu-firewall
export PLATFORM_PUBLIC_IP="$(curl -4 -fsS https://api.ipify.org)"
export PLATFORM_SECRET_DIR=/Users/arunkumar.ganesan/lensk8s/lenscloud-platform/.secrets
```

## Install RBAC

From the manager checkout:

```bash
cd /root/lenscloud-infra
./scripts/51-install-platform-access.sh
./scripts/53-generate-platform-kubeconfig.sh
./scripts/54-verify-platform-access.sh
./scripts/55-verify-platform-lifecycle.sh
./scripts/63-verify-bench-command-pod-cleanup-rbac.sh
```

The service account can:

- read the existing MariaDB in `default`;
- reconcile MariaDB, FrappeBench, and FrappeSite in
  `lenscloud-runtime-eu`;
- delete labelled Platform-owned MariaDB, FrappeBench, and FrappeSite
  resources in `lenscloud-runtime-eu`;
- read runtime Pods, Services, PVCs, Events, Jobs, and Ingresses;
- delete only terminal Platform-labelled Bench Command Pods in approved runtime
  namespaces after sanitized result capture;
- get, create, update, and delete owned Site/admin or database bootstrap
  Secrets only in
  `lenscloud-runtime-eu`;
- discover approved Runtime Namespace records with read-only namespace
  `get/list/watch`.

It cannot mutate `default/frappe-mariadb`, Nodes, namespaces, CRDs, operators,
system deployments, read pod logs, or access infrastructure Secrets. Direct
runtime deletes are rejected unless the resource has
`lenscloud.io/managed-by=platform`. Bench Command Pod deletes have an
additional admission guard: the Pod must be terminal and labelled
`lenscloud.io/resource-kind=bench-command`.

Additional customer or enterprise runtime namespaces are registered after the
baseline access install:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --customer acme \
  --purpose enterprise \
  --region eu-test \
  --cluster lenscloud-eu-test

./scripts/57-verify-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --platform-kubeconfig .artifacts/lenscloud-eu-test.kubeconfig
```

The kubeconfig context default namespace may remain `lenscloud-runtime-eu`;
access to additional runtime namespaces is granted by RoleBinding.

## Authorize The Platform Host

Run locally whenever the platform host public IP changes:

```bash
cd /Users/arunkumar.ganesan/lensk8s/lenscloud-infra
./scripts/52-authorize-platform-api.sh
```

The script replaces the previous `lenscloud-platform-api` firewall source with
the current IPv4 `/32`. It does not expose port 6443 globally.

For a laptop that moves between office Wi-Fi and a personal hotspot, keep the
watch mode running in a host terminal during the live orchestration session:

```bash
cd /Users/arunkumar.ganesan/lensk8s/lenscloud-infra
./scripts/52-authorize-platform-api.sh --watch
```

Watch mode polls the public IPv4 every 30 seconds and changes the firewall only
when the address changes. It uses the already installed `hcloud`, `jq`, and
`curl` commands, installs no host package, and never broadens the rule beyond
one `/32`. Override the interval only when needed:

```bash
PLATFORM_API_WATCH_INTERVAL=15 \
  ./scripts/52-authorize-platform-api.sh --watch
```

## Deliver The Kubeconfig

```bash
mkdir -p "$PLATFORM_SECRET_DIR"
chmod 700 "$PLATFORM_SECRET_DIR"

scp \
  "$MANAGER_HOST:/root/lenscloud-infra/.artifacts/lenscloud-eu.kubeconfig" \
  "$PLATFORM_SECRET_DIR/lenscloud-eu.kubeconfig"

chmod 600 "$PLATFORM_SECRET_DIR/lenscloud-eu.kubeconfig"
```

Verify from the platform host:

```bash
cd /Users/arunkumar.ganesan/lensk8s/lenscloud-infra
PLATFORM_KUBECONFIG="$PLATFORM_SECRET_DIR/lenscloud-eu.kubeconfig" \
  ./scripts/54-verify-platform-access.sh
```

## Devcontainer Handoff

The platform compose file mounts:

```text
.secrets -> /run/secrets:ro
```

The Cluster record stores only:

```text
file:/run/secrets/lenscloud-eu.kubeconfig
```

Rebuild or reopen the devcontainer after first delivery. Verify inside it:

```bash
test -r /run/secrets/lenscloud-eu.kubeconfig
test ! -w /run/secrets/lenscloud-eu.kubeconfig
```

Then run the Platform backend permission preflight:

```bash
bench --site dev.localhost execute \
  lenscloud.api.orchestration.check_cluster_permissions \
  --kwargs '{"cluster":"lenscloud-eu-dev"}'
```

Do not enable `Platform Settings.kubernetes_apply_enabled` until the host and
container checks both pass and `all_required_allowed` is `true`.

## Rotation And Revocation

Rotate:

```bash
kubectl -n lenscloud-platform-system delete secret lenscloud-platform-token
kubectl apply -f manifests/access/lenscloud-platform-rbac.yaml
./scripts/53-generate-platform-kubeconfig.sh
```

Then copy the replacement kubeconfig to the platform host and rebuild/restart
the devcontainer.

Revoke immediately:

```bash
kubectl -n lenscloud-platform-system delete serviceaccount lenscloud-platform
kubectl delete clusterrolebinding lenscloud-platform-access-reviewer
kubectl delete rolebinding lenscloud-platform-existing-database -n default
kubectl delete rolebinding lenscloud-platform-runtime -n lenscloud-runtime-eu
for namespace in lenscloud-enterprise-acme lenscloud-customer-acme; do
  kubectl delete rolebinding lenscloud-platform-runtime -n "$namespace" \
    --ignore-not-found
  kubectl delete role lenscloud-platform-runtime -n "$namespace" \
    --ignore-not-found
done
kubectl delete validatingadmissionpolicybinding \
  lenscloud-platform-owned-delete
kubectl delete validatingadmissionpolicy lenscloud-platform-owned-delete
kubectl delete validatingadmissionpolicybinding \
  lenscloud-platform-bench-command-pod-delete
kubectl delete validatingadmissionpolicy \
  lenscloud-platform-bench-command-pod-delete
```

Remove the `lenscloud-platform-api` firewall rule if the integration is no
longer used.
