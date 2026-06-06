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
```

The service account can:

- reconcile the existing MariaDB in `default`;
- reconcile MariaDB, FrappeBench, and FrappeSite in
  `lenscloud-runtime-eu`;
- read runtime Pods, Services, PVCs, Events, Jobs, and Ingresses;
- get and create Site/admin or database bootstrap Secrets only in
  `lenscloud-runtime-eu`.

It cannot mutate Nodes, namespaces, CRDs, operators, system deployments, or
infrastructure Secrets.

## Authorize The Platform Host

Run locally whenever the platform host public IP changes:

```bash
cd /Users/arunkumar.ganesan/lensk8s/lenscloud-infra
./scripts/52-authorize-platform-api.sh
```

The script replaces the previous `lenscloud-platform-api` firewall source with
the current IPv4 `/32`. It does not expose port 6443 globally.

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
```

Remove the `lenscloud-platform-api` firewall rule if the integration is no
longer used.
