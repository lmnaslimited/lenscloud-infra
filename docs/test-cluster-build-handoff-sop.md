# Test Cluster Build And Platform Handoff SOP

## Purpose

This SOP lets the Infra team create a fresh two-node LensCloud K3s cluster in a
new Hetzner Cloud project, validate every layer, and hand the cluster to the
LensCloud Platform team.

Reference test namespace:

```text
testcloud.lmnaslens.com
*.testcloud.lmnaslens.com
```

The procedure deliberately separates:

- Hetzner project and human access;
- SSH recovery access;
- cluster bootstrap;
- operators and storage;
- wildcard DNS/TLS and Traefik;
- Frappe Bench/Site acceptance;
- restricted Platform API access;
- formal handoff and evidence.

Do not place API tokens, kubeconfigs, SSH private keys, DNS credentials,
passwords, or TLS private keys in Git, tickets, screenshots, chat, or handoff
documents.

## Target Topology

| Item | Test value |
| --- | --- |
| Hetzner project | `LensCloud Test` |
| Cluster | `lenscloud-eu-test` |
| Manager | `lenscloud-eu-test-manager-1`, `cx23` |
| Worker | `lenscloud-eu-test-worker-1`, `cx33` |
| Location | `nbg1` |
| Private network | `10.30.0.0/16` |
| Node subnet | `10.30.1.0/24` |
| Runtime namespace | `lenscloud-runtime-eu` |
| StorageClass | `local-path` |
| Ingress | Traefik |
| Root test domain | `testcloud.lmnaslens.com` |
| Wildcard | `*.testcloud.lmnaslens.com` |
| Headlamp | `headlamp.testcloud.lmnaslens.com` |
| Handoff smoke Site | `handoff.testcloud.lmnaslens.com` |

The manager is the administrative host. Application and database workloads
must run on the worker.

Repo delivery rule: do not copy reusable Infra repository content from the
operator laptop to the manager with `scp`. The manager and worker must use a
Git checkout and `git fetch` / `git checkout` / `git pull --ff-only` so the
handoff record can name the exact revision. Use `scp` only for explicitly
secret, non-Git artifacts such as a restricted kubeconfig handoff.

## Roles

Before work starts, assign:

| Role | Responsibility |
| --- | --- |
| Project Owner | Creates the project, billing ownership, final authority |
| Infra Operator | Runs this SOP and records evidence |
| Team Lead | Admin/break-glass project access and independent SSH key |
| DNS Owner | Creates wildcard records and production DNS API credentials |
| Platform Owner | Receives restricted kubeconfig and registers the Cluster |

The Project Owner and Team Lead should have `Admin` access. Infra builders need
at least `Member` access to create resources; an Owner/Admin must manage project
members and API tokens. Every human must enable 2FA.

## Stage 0: Approval And Capacity

The Project Owner creates a new project in Hetzner Console and confirms:

- project name and owner;
- billing is active;
- at least two servers can be created;
- at least six vCPUs and 12 GB RAM are within project limits;
- IPv4 allocation is available;
- the selected location offers `cx23` and `cx33`;
- Infra Operator and Team Lead invitations are accepted;
- the Team Lead can open the project independently.

**Gate 0 tests**

- Both Infra Operator and Team Lead can see the project.
- The Team Lead role is `Admin`.
- The project Limits page has sufficient capacity.
- No resources from another LensCloud environment are visible in this project.

Stop if any test fails.

## Stage 1: Local Workstation Prerequisites

Required commands on the Infra Operator workstation:

```text
hcloud git ssh ssh-keygen scp curl jq dig openssl
```

Docker is required only when rebuilding the Certbot image. The published pinned
image may be reused for this test.

On macOS, the official Homebrew installation is:

```bash
brew install hcloud jq
```

Alternatively, run the official `hetznercloud/cli` container instead of
installing `hcloud` on the host.

Verify:

```bash
hcloud version
git --version
ssh -V
jq --version
dig -v
openssl version
```

Clone the Infra repository:

```bash
git clone https://github.com/lmnaslimited/lenscloud-infra.git
cd lenscloud-infra
git status --short --branch
git log -1 --oneline
```

Record the exact Git revision in the build evidence.

**Gate 1 tests**

```bash
for command in hcloud git ssh ssh-keygen scp curl jq dig openssl; do
  command -v "$command" >/dev/null || {
    echo "Missing prerequisite: $command" >&2
    exit 1
  }
done

test -z "$(git status --porcelain)"
```

## Stage 2: Project API Context

In the new project, an Owner/Admin creates a read/write API token:

```text
Hetzner Console -> Project -> Security -> API Tokens
```

Name it for the activity, for example:

```text
lenscloud-test-bootstrap-202606
```

Store it in the approved password manager. Do not send it by email or chat.

Create a dedicated local context:

```bash
hcloud context create lenscloud-test
hcloud context use lenscloud-test
hcloud context active
hcloud datacenter list
hcloud server list
```

The context name should match the project. Do not reuse the production
context.

**Gate 2 tests**

- `hcloud context active` reports `lenscloud-test`.
- `hcloud datacenter list` succeeds.
- `hcloud server list` shows only the new project.
- An operator confirms the project name in Hetzner Console before provisioning.

## Stage 3: Two-Person SSH Recovery Access

Never share an SSH private key. The Infra Operator and Team Lead each generate
their own Ed25519 key.

Infra Operator:

```bash
ssh-keygen -t ed25519 -a 100 \
  -f ~/.ssh/lenscloud-test-infra \
  -C "lenscloud-test-infra"
```

Team Lead, on their own workstation:

```bash
ssh-keygen -t ed25519 -a 100 \
  -f ~/.ssh/lenscloud-test-team-lead \
  -C "lenscloud-test-team-lead"
```

Import only the public keys into the new Hetzner project:

```bash
hcloud ssh-key create \
  --name lenscloud-test-infra \
  --public-key-from-file ~/.ssh/lenscloud-test-infra.pub

hcloud ssh-key create \
  --name lenscloud-test-team-lead \
  --public-key-from-file /secure/path/to/team-lead-public-key.pub

hcloud ssh-key list
```

The Team Lead may instead import their key personally after selecting the new
`lenscloud-test` context. In either case, verify the fingerprint with the key
owner before server creation.

**Gate 3 tests**

```bash
ssh-keygen -lf ~/.ssh/lenscloud-test-infra.pub
hcloud ssh-key describe lenscloud-test-infra
hcloud ssh-key describe lenscloud-test-team-lead
```

- Two distinct public-key fingerprints exist.
- The private keys exist only on their owners' workstations.
- Both keys are attached at initial server creation. Hetzner cannot add a
  project SSH key to an existing server automatically afterward.

## Stage 4: Build Variables

Keep the values in the operator shell or an ignored file under `.artifacts/`.

```bash
mkdir -p .artifacts
chmod 700 .artifacts

export HCLOUD_CONTEXT=lenscloud-test
export REGION=eu-test
export CLUSTER_NAME=lenscloud-eu-test
export LOCATION=nbg1
export NETWORK_ZONE=eu-central
export NETWORK_NAME=lenscloud-eu-test-net
export NETWORK_CIDR=10.30.0.0/16
export SUBNET_CIDR=10.30.1.0/24
export FIREWALL_NAME=lenscloud-eu-test-firewall
export MANAGER_NAME=lenscloud-eu-test-manager-1
export WORKER_NAME=lenscloud-eu-test-worker-1
export MANAGER_TYPE=cx23
export WORKER_TYPE=cx33
export SSH_KEY_NAMES=lenscloud-test-infra,lenscloud-test-team-lead
export ROOT_DOMAIN=testcloud.lmnaslens.com
export HEADLAMP_HOST=headlamp.testcloud.lmnaslens.com
export HANDOFF_SITE_HOST=handoff.testcloud.lmnaslens.com
export TRAEFIK_SMOKE_HOST=traefik-smoke.testcloud.lmnaslens.com
export WILDCARD_SMOKE_HOST=wildcard-smoke.testcloud.lmnaslens.com
```

Check for CIDR overlap with office/VPN, Docker, existing Hcloud networks, K3s
pod CIDR `10.42.0.0/16`, and K3s service CIDR `10.43.0.0/16`.

**Gate 4 tests**

```bash
test "$(hcloud context active)" = "$HCLOUD_CONTEXT"
hcloud server-type describe "$MANAGER_TYPE"
hcloud server-type describe "$WORKER_TYPE"
hcloud location describe "$LOCATION"
hcloud network list
```

Peer-review the variables before running any create command.

## Stage 5: Create Hetzner Resources

```bash
./scripts/10-create-hcloud-eu-nodes.sh
```

Capture addresses:

```bash
export MANAGER_PUBLIC_IP="$(
  hcloud server describe "$MANAGER_NAME" -o json |
    jq -r '.public_net.ipv4.ip'
)"
export WORKER_PUBLIC_IP="$(
  hcloud server describe "$WORKER_NAME" -o json |
    jq -r '.public_net.ipv4.ip'
)"
export MANAGER_PRIVATE_IP="$(
  hcloud server describe "$MANAGER_NAME" -o json |
    jq -r --arg network "$NETWORK_NAME" \
      '.private_net[] | select(.network.name == $network) | .ip'
)"
export WORKER_PRIVATE_IP="$(
  hcloud server describe "$WORKER_NAME" -o json |
    jq -r --arg network "$NETWORK_NAME" \
      '.private_net[] | select(.network.name == $network) | .ip'
)"
```

**Gate 5 tests**

```bash
hcloud server list
hcloud network describe "$NETWORK_NAME"
hcloud firewall describe "$FIREWALL_NAME"

ssh -i ~/.ssh/lenscloud-test-infra \
  -o StrictHostKeyChecking=accept-new \
  "root@$MANAGER_PUBLIC_IP" hostname

ssh -i ~/.ssh/lenscloud-test-infra \
  -o StrictHostKeyChecking=accept-new \
  "root@$WORKER_PUBLIC_IP" hostname
```

The Team Lead independently runs equivalent SSH tests with their private key.
Do not proceed until both people can access both nodes.

Verify firewall intent:

- TCP 22: key-only SSH;
- TCP 80/443: public edge;
- all TCP/UDP/ICMP: private network only;
- TCP 6443: not public yet.

## Stage 6: Bootstrap K3s

Set the Infra repository source and revision. Use a branch for normal rebuilds
or a commit SHA for evidence-grade reproduction.

```bash
export INFRA_REPO_URL=https://github.com/lmnaslimited/lenscloud-infra.git
export INFRA_REF=main
```

Prepare the manager checkout:

```bash
ssh -i ~/.ssh/lenscloud-test-infra "root@$MANAGER_PUBLIC_IP" \
  "apt-get update && apt-get install -y git ca-certificates"

ssh -i ~/.ssh/lenscloud-test-infra "root@$MANAGER_PUBLIC_IP" \
  "if [ -d /root/lenscloud-infra ] && [ ! -d /root/lenscloud-infra/.git ]; then \
     mv /root/lenscloud-infra /root/lenscloud-infra.copy.\$(date -u +%Y%m%d%H%M%S); \
   fi; \
   if [ ! -d /root/lenscloud-infra/.git ]; then \
     git clone '$INFRA_REPO_URL' /root/lenscloud-infra; \
   fi; \
   cd /root/lenscloud-infra && \
   git fetch --all --tags --prune && \
   git checkout '$INFRA_REF' && \
   git pull --ff-only || true && \
   git rev-parse --short HEAD"
```

Bootstrap the manager from the checked-out repository:

```bash
ssh -i ~/.ssh/lenscloud-test-infra "root@$MANAGER_PUBLIC_IP" \
  "bash /root/lenscloud-infra/scripts/20-bootstrap-k3s-manager.sh \
    '$MANAGER_PUBLIC_IP' '$MANAGER_PRIVATE_IP'"
```

Join worker without printing or storing the node token in Git:

```bash
K3S_NODE_TOKEN="$(
  ssh -i ~/.ssh/lenscloud-test-infra "root@$MANAGER_PUBLIC_IP" \
    'cat /var/lib/rancher/k3s/server/node-token'
)"

ssh -i ~/.ssh/lenscloud-test-infra "root@$WORKER_PUBLIC_IP" \
  "apt-get update && apt-get install -y git ca-certificates"

ssh -i ~/.ssh/lenscloud-test-infra "root@$WORKER_PUBLIC_IP" \
  "if [ -d /root/lenscloud-infra ] && [ ! -d /root/lenscloud-infra/.git ]; then \
     mv /root/lenscloud-infra /root/lenscloud-infra.copy.\$(date -u +%Y%m%d%H%M%S); \
   fi; \
   if [ ! -d /root/lenscloud-infra/.git ]; then \
     git clone '$INFRA_REPO_URL' /root/lenscloud-infra; \
   fi; \
   cd /root/lenscloud-infra && \
   git fetch --all --tags --prune && \
   git checkout '$INFRA_REF' && \
   git pull --ff-only || true && \
   git rev-parse --short HEAD"

ssh -i ~/.ssh/lenscloud-test-infra "root@$WORKER_PUBLIC_IP" \
  "bash /root/lenscloud-infra/scripts/21-bootstrap-k3s-worker.sh \
    '$MANAGER_PRIVATE_IP' '$K3S_NODE_TOKEN' '$WORKER_PRIVATE_IP'"

unset K3S_NODE_TOKEN
```

From now on, Kubernetes commands run on the manager:

```bash
ssh -i ~/.ssh/lenscloud-test-infra "root@$MANAGER_PUBLIC_IP"
cd /root/lenscloud-infra
git fetch --all --tags --prune
git checkout "$INFRA_REF"
git pull --ff-only || true
git rev-parse --short HEAD
export KUBECONFIG=/root/.kube/config
export MANAGER_NAME=lenscloud-eu-test-manager-1
export WORKER_NAME=lenscloud-eu-test-worker-1
export MANAGER_PUBLIC_IP=REPLACE_WITH_CAPTURED_MANAGER_PUBLIC_IP
export MANAGER_PRIVATE_IP=REPLACE_WITH_CAPTURED_MANAGER_PRIVATE_IP
export WORKER_PRIVATE_IP=REPLACE_WITH_CAPTURED_WORKER_PRIVATE_IP
./scripts/30-label-nodes.sh
```

In a second local terminal, verify the worker bootstrap directly:

```bash
ssh -i ~/.ssh/lenscloud-test-infra "root@$WORKER_PUBLIC_IP" \
  'systemctl is-active k3s-agent; swapon --show'
```

**Gate 6 tests**

```bash
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl describe node "$MANAGER_NAME" | grep -A3 Taints
swapon --show
systemctl is-active k3s
```

Expected:

- two Ready nodes;
- private node IPs;
- manager label and `NoSchedule` taint;
- worker label;
- K3s server active;
- 4 GB swap on both nodes.

## Stage 7: Install Baseline Ingress, Operators, And Headlamp

On the manager:

```bash
export HEADLAMP_HOST=headlamp.testcloud.lmnaslens.com

./scripts/35-install-ingress.sh
./scripts/40-install-operators.sh
./scripts/50-install-headlamp.sh
```

**Gate 7 tests**

```bash
kubectl get nodes
kubectl get pods -A
kubectl get crd | grep -E \
  'frappebenches|frappesites|sitebackups|siterestores|mariadbs'
kubectl -n frappe-operator-system get deploy,pod
kubectl -n mariadb-operator-system get deploy,pod
kubectl -n headlamp get deploy,service,ingress
```

All operator and Headlamp Deployments must be Available. Record image tags and
CRD API versions.

## Stage 8: Create Wildcard DNS

The DNS Owner creates these records in the authoritative `lmnaslens.com` zone:

| Type | Name | Value | Initial TTL |
| --- | --- | --- | --- |
| A | `testcloud` | manager public IPv4 | 600 |
| A | `*.testcloud` | manager public IPv4 | 600 |

No per-customer records are required. The wildcard covers Headlamp and smoke
Sites.

**Gate 8 tests**

From two networks or public resolvers:

```bash
dig +short A testcloud.lmnaslens.com @1.1.1.1
dig +short A headlamp.testcloud.lmnaslens.com @1.1.1.1
dig +short A arbitrary.testcloud.lmnaslens.com @8.8.8.8
```

Every result must equal `$MANAGER_PUBLIC_IP`. Stop if wildcard resolution is
empty or points to another environment.

## Stage 9: Stage Traefik

On the manager:

```bash
export SMOKE_HOST=traefik-smoke.testcloud.lmnaslens.com

./scripts/36-install-traefik-side-by-side.sh
./scripts/37-validate-traefik-side-by-side.sh
```

At this stage ingress-nginx owns public ports 80/443; Traefik is tested on
NodePorts.

**Gate 9 tests**

```bash
kubectl -n traefik get deploy,pod,service,ingressclass
kubectl -n default get deploy,service,ingress traefik-smoke
```

The side-by-side script must report
`Traefik side-by-side validation passed`.

## Stage 10: Issue Wildcard TLS

Use the pinned, already-published image:

```bash
export CERTBOT_IMAGE='ghcr.io/lmnaslimited/lenscloud-certbot-godaddy@sha256:d237a693c908b14ec9a49158d973a0c81c43efaf0e4c27552f1c94d9b5489814'
export CERTBOT_EMAIL=operations@lmnas.com
export CERTBOT_DOMAIN=testcloud.lmnaslens.com
```

The DNS Owner creates a production GoDaddy API key with permission to update
the `lmnaslens.com` zone. In a private manager shell:

```bash
export GODADDY_API_KEY='REDACTED'
export GODADDY_API_SECRET='REDACTED'
export GODADDY_DOMAIN=lmnaslens.com
export GODADDY_PREFLIGHT_NAME=_lenscloud-preflight.testcloud

./scripts/43-preflight-godaddy-api.sh
./scripts/43-create-godaddy-secret.sh
unset GODADDY_API_KEY GODADDY_API_SECRET
```

Render, issue, and test:

```bash
CERTBOT_IMAGE="$CERTBOT_IMAGE" \
CERTBOT_EMAIL="$CERTBOT_EMAIL" \
CERTBOT_DOMAIN="$CERTBOT_DOMAIN" \
  ./scripts/44-render-certbot-manifests.sh

./scripts/45-install-certbot-wildcard.sh
./scripts/46-test-certbot-renewal.sh
```

**Gate 10 tests**

```bash
kubectl -n lenscloud-edge get job,cronjob,pod,pvc
kubectl -n traefik get secret lenscloud-cloud-wildcard-tls
kubectl -n traefik get secret lenscloud-cloud-wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' |
  base64 -d |
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

The SAN list must include:

```text
testcloud.lmnaslens.com
*.testcloud.lmnaslens.com
```

The renewal dry-run must complete successfully. Never include private-key or
Secret data in evidence.

## Stage 11: Cut Over Traefik And Verify Edge

```bash
export HEADLAMP_HOST=headlamp.testcloud.lmnaslens.com
export WILDCARD_SMOKE_HOST=wildcard-smoke.testcloud.lmnaslens.com
export WILDCARD_TARGET="$MANAGER_PUBLIC_IP"
export CONFIRM_TRAEFIK_CUTOVER=yes

./scripts/38-cutover-traefik.sh
./scripts/47-run-wildcard-route-smoke.sh
./scripts/49-verify-edge-runtime.sh
```

If an older checkout created `FrappeSite/wildcard-smoke` in Stage 11 and it is
Pending, remove it before rerunning this step:

```bash
kubectl delete frappesite wildcard-smoke --ignore-not-found
```

Stage 11 validates wildcard DNS/TLS and Traefik routing only. The Frappe
Operator Bench/Site acceptance happens in Stage 12 after the required Bench and
MariaDB exist.

**Gate 11 tests**

```bash
curl -fsSI "http://$HEADLAMP_HOST/" | head
curl -fsSI "https://$HEADLAMP_HOST/" | head
curl -fsSI "https://$WILDCARD_SMOKE_HOST/" | head
kubectl get ingress -A
kubectl -n traefik get service,pod,tlsstore
```

Expected:

- HTTP redirects to HTTPS;
- Headlamp HTTPS responds;
- arbitrary wildcard route responds;
- wildcard certificate is presented;
- no per-Site Certificate or DNS object exists.

Rehearse rollback before retiring ingress-nginx:

```bash
export CONFIRM_INGRESS_ROLLBACK=yes
./scripts/39-rollback-ingress-nginx.sh

# Validate, then cut over again.
export CONFIRM_TRAEFIK_CUTOVER=yes
./scripts/38-cutover-traefik.sh
```

After final validation:

```bash
export CONFIRM_RETIRE_INGRESS_NGINX=yes
./scripts/50-retire-ingress-nginx.sh
```

## Stage 12: Frappe v16 Handoff Smoke

Create the baseline MariaDB Secret without printing its value:

```bash
./scripts/41-create-smoke-secrets.sh
kubectl get secret handoff-site-admin-password
kubectl apply -f manifests/database/eu-shared-mariadb-template.yaml
kubectl wait --for=condition=Ready mariadb/frappe-mariadb --timeout=15m
```

Render and apply the approved Frappe v16 Bench first:

```bash
export HANDOFF_SITE_HOST=handoff.testcloud.lmnaslens.com
export HANDOFF_BENCH_MANIFEST=/tmp/lenscloud-handoff-bench.yaml
export HANDOFF_SITE_MANIFEST=/tmp/lenscloud-handoff-site.yaml

cp manifests/smoke/handoff-bench.template.yaml "$HANDOFF_BENCH_MANIFEST"
kubectl apply -f "$HANDOFF_BENCH_MANIFEST"
kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  frappebench/handoff-bench --timeout=20m

envsubst < manifests/smoke/handoff-site.template.yaml \
  > "$HANDOFF_SITE_MANIFEST"
kubectl apply -f "$HANDOFF_SITE_MANIFEST"
kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  frappesite/handoff-site --timeout=20m
```

If `handoff-site` already exists and reports
`SiteInitializationFailed: Secret "handoff-site-admin-password" not found`,
create the missing secret and force a fresh reconciliation:

```bash
./scripts/41-create-smoke-secrets.sh
kubectl get secret handoff-site-admin-password

kubectl annotate frappesite handoff-site \
  lenscloud.io/retry-at="$(date +%s)" \
  --overwrite

kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  frappesite/handoff-site --timeout=20m
```

If the Site remains Pending after the annotation, delete and recreate only the
Site. Keep the Bench and MariaDB:

```bash
kubectl delete frappesite handoff-site --wait=false
kubectl wait --for=delete frappesite/handoff-site --timeout=10m
kubectl apply -f "$HANDOFF_SITE_MANIFEST"
kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  frappesite/handoff-site --timeout=20m
```

**Gate 12 tests**

```bash
kubectl get mariadb,frappebench,frappesite,pod,pvc,ingress -o wide

kubectl get pod -o wide |
  grep -E 'frappe-mariadb|handoff-bench|handoff-site'

curl -fsSI "https://$HANDOFF_SITE_HOST/" | head
asset_path="$(
  curl -fsS "https://$HANDOFF_SITE_HOST/" |
    grep -Eo '/assets/[^\" ]+\\.css' |
    head -1
)"
test -n "$asset_path"
curl -fsSI "https://${HANDOFF_SITE_HOST}${asset_path}" | head
```

Admin login:

```bash
kubectl get secret handoff-site-admin-password \
  -o jsonpath='{.data.password}' |
  base64 -d
echo
```

Open:

```text
https://handoff.testcloud.lmnaslens.com
```

Use:

```text
Username: Administrator
Password: value from handoff-site-admin-password
```

Bench shell for diagnostics:

```bash
gunicorn_pod="$(
  kubectl get pod -o name |
    sed -n 's#pod/\\(handoff-bench-gunicorn[^ ]*\\)#\\1#p' |
    head -1
)"
test -n "$gunicorn_pod"

kubectl exec -it "$gunicorn_pod" -- bash
cd /home/frappe/frappe-bench
bench --site handoff.testcloud.lmnaslens.com list-apps
```

Expected output includes at least:

```text
frappe
erpnext
```

Do not use `bench drop-site` as the normal cleanup path while the
`FrappeSite/handoff-site` custom resource exists. Dropping the site manually
can make the operator deletion job fail with `IncorrectSitePath`, leaving the
custom resource stuck on its finalizer. Use the `kubectl delete frappesite`
cleanup in Stage 14.

Expected:

- MariaDB Running/Ready;
- Bench and Site Ready;
- application and database pods on the worker;
- HTTPS login page responds;
- a generated CSS asset is referenced and returns HTTP 200;
- image is `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.1`.

Do not use `lenscx:v15.91.2`.

## Stage 13: Install Restricted Platform Access

On the manager:

```bash
cd /root/lenscloud-infra
./scripts/51-install-platform-access.sh
```

From an authorized workstation, add only the Platform backend public IPv4 to
port 6443:

```bash
export HCLOUD_FIREWALL=lenscloud-eu-test-firewall
export PLATFORM_PUBLIC_IP=REPLACE_WITH_PLATFORM_BACKEND_PUBLIC_IPV4
./scripts/52-authorize-platform-api.sh --once
```

Generate the restricted kubeconfig on the manager:

```bash
export PLATFORM_API_SERVER="https://${MANAGER_PUBLIC_IP}:6443"
export PLATFORM_CLUSTER_NAME=lenscloud-eu-test
export PLATFORM_CONTEXT_NAME=lenscloud-platform@lenscloud-eu-test
export PLATFORM_RUNTIME_NAMESPACE=lenscloud-runtime-eu
export OUTPUT_PATH=.artifacts/lenscloud-eu-test.kubeconfig

./scripts/53-generate-platform-kubeconfig.sh

PLATFORM_KUBECONFIG="$OUTPUT_PATH" \
  ./scripts/54-verify-platform-access.sh

PLATFORM_KUBECONFIG="$OUTPUT_PATH" \
  ./scripts/55-verify-platform-lifecycle.sh
```

Optional enterprise/customer runtime namespace registration:

```bash
./scripts/56-register-platform-runtime-namespace.sh \
  --namespace lenscloud-enterprise-acme \
  --customer acme \
  --purpose enterprise \
  --region eu-test \
  --cluster lenscloud-eu-test

PLATFORM_KUBECONFIG="$OUTPUT_PATH" \
  ./scripts/57-verify-platform-runtime-namespace.sh \
    --namespace lenscloud-enterprise-acme
```

Do not edit the generated kubeconfig context to switch namespaces. The context
may remain `lenscloud-runtime-eu`; additional namespace access is granted
through RoleBindings.

**Gate 13 tests**

- Positive restricted checks pass.
- Protected and cross-namespace checks are denied.
- `default/frappe-mariadb` is readable but cannot be patched or deleted.
- Nodes, namespaces, CRDs, StorageClasses, operators, Traefik, and
  infrastructure Secrets remain protected.
- Namespace list is allowed only for approved Runtime Namespace discovery;
  namespace create/patch/delete remain denied.
- Optional enterprise/customer runtime namespace verification passes when
  registered.
- Unlabelled runtime deletion is denied.
- Managed lifecycle test resources are cleaned.
- Port 6443 has exactly the approved Platform `/32`, never `0.0.0.0/0`.

LensCloud Platform itself uses the Kubernetes API through its Python client. It
does not require `kubectl`; these scripts are Infra-side contract verification.

## Stage 13A: Verify CUA OAuth Local-Dev Issuer Contract

Use this stage when handing a test cluster to Platform for CUA/OAuth local-dev
acceptance. The provider identity and issuer source of truth is LensCloud
Platform Settings, not an example host:

```text
oauth_provider_key=<platform-setting-value>
oauth_provider_name=<platform-setting-value>
oauth_base_url=http://dev.localhost:8000
allow_local_oauth_http=true
```

The target redirect URL is derived from the target Site access URL:

```text
https://<target-site>/api/method/frappe.integrations.oauth2_logins.custom/<oauth_provider_key>
```

Publish and admission-pin a runner image that includes `INF-026`, then run the
OAuth verifier against a real Platform-managed Bench/Site:

```bash
export RUNNER_IMAGE='ghcr.io/lmnaslimited/lenscloud-bench-command-runner@sha256:3e7867ff7cb0285395aafd380232496f854c6d014c237b8790cbcbfd1bd577ef'
export REAL_BENCH=<platform-managed-bench>
export REAL_SITE=<target-site-hostname>
export REAL_SITES_PVC=<platform-managed-bench-sites-pvc>
export OAUTH_PROVIDER=<oauth_provider_key>
export OAUTH_PROVIDER_NAME=<oauth_provider_name>
export OAUTH_CLIENT_ID=<platform-oauth-client-id>
export OAUTH_BASE_URL=http://dev.localhost:8000
export OAUTH_ALLOW_LOCAL_HTTP=true
export OAUTH_REDIRECT_URL="https://${REAL_SITE}/api/method/frappe.integrations.oauth2_logins.custom/${OAUTH_PROVIDER}"

./scripts/65-verify-cua-oauth-runner.sh
```

**Gate 13A tests**

- `oauth.status` succeeds before and after configuration.
- `oauth.configure` succeeds with
  `base_url=http://dev.localhost:8000` and
  `allow_local_oauth_http=true`.
- `oauth.configure` rejects the same local HTTP base URL when
  `allow_local_oauth_http` is absent or false.
- `oauth.configure` rejects non-local plain HTTP even when
  `allow_local_oauth_http=true`.
- The target `Social Login Key` reports the Platform Settings provider key and
  base URL, not any hard-coded/example issuer.
- Direct `client_secret` request args are rejected.
- Non-OAuth Bench Command Jobs cannot mount the OAuth client-secret Secret.
- No OAuth client secret, kubeconfig, token, private key, pod log, raw
  `site_config.json`, or full environment dump appears in evidence.
- Temporary Jobs, ConfigMaps, Pods, and the short-lived Secret are deleted.

## Stage 14: Clean Smoke Resources

Preserve the shared Public baseline:

```text
MariaDB/default/frappe-mariadb
```

Delete the smoke Site and Bench in dependency order:

```bash
kubectl delete frappesite handoff-site --wait=false
kubectl wait --for=delete frappesite/handoff-site --timeout=10m

kubectl delete frappebench handoff-bench --wait=false
kubectl wait --for=delete frappebench/handoff-bench --timeout=10m

kubectl delete secret \
  handoff-site-admin-password \
  handoff-site-db-password \
  handoff-site-encryption-key \
  handoff-site-init-secrets \
  --ignore-not-found
kubectl delete pvc handoff-bench-sites --ignore-not-found
rm -f /tmp/lenscloud-handoff-bench.yaml /tmp/lenscloud-handoff-site.yaml
```

**Gate 14 tests**

```bash
kubectl get frappebench,frappesite,pvc,secret -A |
  grep -E 'handoff-(bench|site)' && exit 1 || true

kubectl -n default get mariadb frappe-mariadb
```

The smoke prefix must be absent and the shared MariaDB must remain Ready.

## Stage 15: Handoff Package

Create the record from
`docs/test-cluster-handoff-record-template.md`.

### Non-secret handoff

Record:

- Hetzner project name and project owner;
- Infra Git revision;
- cluster name, provider, region, and environment;
- manager/worker names, plans, public/private IPs, and location;
- private network and firewall names;
- Kubernetes and K3s versions;
- operator image versions and CRD API versions;
- runtime/operator/edge namespaces;
- default StorageClass;
- root domain, wildcard domain/target, ingress class, Headlamp URL;
- wildcard certificate issuer, SANs, expiry, and renewal status;
- shared MariaDB CR name/namespace and health;
- restricted service-account name and runtime namespace;
- approved Runtime Namespace labels and verification results;
- positive/negative RBAC summary;
- Bench/Site HTTPS and asset test results;
- CUA OAuth local-dev issuer verification result when Stage 13A is in scope;
- capacity snapshot and any warnings;
- cleanup result and retained baseline.

Never include credentials or Secret values.

### Secret handoff

Deliver through the approved secret channel:

```text
lenscloud-eu-test.kubeconfig
```

The Platform backend mounts it read-only and stores only:

```text
file:/run/secrets/lenscloud-eu-test.kubeconfig
```

Use file mode `0600`. Do not deliver the manager kubeconfig.

### Platform Cluster record

Provide these values:

| Field | Value |
| --- | --- |
| Cluster | `lenscloud-eu-test` |
| Provider | `hcloud` |
| Region | EU Test |
| Environment | Test |
| Manager | manager name and public IP |
| Headlamp URL | `https://headlamp.testcloud.lmnaslens.com` |
| Operator namespace | `frappe-operator-system` |
| Runtime namespace | `lenscloud-runtime-eu` |
| Additional runtime namespaces | optional approved namespaces and labels |
| StorageClass | `local-path` |
| Credential reference | `file:/run/secrets/lenscloud-eu-test.kubeconfig` |
| Root domain | `testcloud.lmnaslens.com` |
| Ingress class | `traefik` |
| Shared Public DB | `MariaDB/default/frappe-mariadb` |

### Joint acceptance

Infra and Platform jointly verify:

1. Platform backend permission preflight passes through its Python Kubernetes
   client.
2. Platform creates a labelled Bench and Site in the runtime namespace.
3. The Site reaches real HTTPS 200 and serves assets.
4. Platform inspects runtime state without exposing Secret values.
5. Platform deletes its Site and Bench through normal finalizers.
6. Protected `default/frappe-mariadb` deletion is rejected.
7. Platform disables live apply after acceptance unless the test environment
   is formally released for ongoing use.

Both teams sign the handoff evidence.

### Headlamp operator check

Create a short-lived login token without placing it in the handoff ticket:

```bash
kubectl -n headlamp create token headlamp-frappe-operator --duration=1h
```

Use it to log into:

```text
https://headlamp.testcloud.lmnaslens.com
```

Verify Nodes, namespaces, Pods, MariaDB, FrappeBench, and FrappeSite menus are
visible according to Headlamp RBAC. Close the session after testing; generate a
new short-lived token for future troubleshooting.

## Stage 16: Close Bootstrap Access

After handoff:

- verify Team Lead SSH still works;
- remove temporary operator public keys that are no longer approved from
  `/root/.ssh/authorized_keys`;
- rotate or revoke the bootstrap API token;
- retain named human project memberships;
- retain the restricted Platform credential;
- confirm port 6443 is limited to the Platform backend `/32`;
- store recovery steps and contact ownership in the operations register.

Do not remove the Team Lead key until another tested break-glass path exists.

## Failure And Stop Conditions

Stop and resolve before continuing when:

- either node is not Ready;
- a node reports MemoryPressure, DiskPressure, or PIDPressure;
- the worker has less than 2 GiB available memory or 30 GiB free disk;
- any operator Deployment is unavailable;
- DNS does not resolve consistently;
- wildcard SANs are wrong;
- Certbot renewal dry-run fails;
- HTTP does not redirect to HTTPS;
- Site HTML or generated assets fail;
- workload placement lands on the manager unexpectedly;
- restricted RBAC permits a protected operation;
- any credential appears in logs or evidence.

## Teardown

Only the Project Owner or named Infra Operator may destroy the test cluster.
First archive non-secret evidence and confirm Platform no longer uses the
credential.

From the workstation with the correct Hcloud context:

```bash
test "$(hcloud context active)" = "lenscloud-test"

export NETWORK_NAME=lenscloud-eu-test-net
export FIREWALL_NAME=lenscloud-eu-test-firewall
export MANAGER_NAME=lenscloud-eu-test-manager-1
export WORKER_NAME=lenscloud-eu-test-worker-1
export CONFIRM_DESTROY=yes

./scripts/90-destroy-hcloud-eu-cluster.sh
```

Then:

- remove `testcloud` and `*.testcloud` DNS records;
- revoke the bootstrap and Platform credentials;
- remove obsolete project SSH keys;
- verify the project contains no billable resources;
- record teardown time and operator.

## Evidence Checklist

The handoff ticket must contain:

- [ ] project members/roles verified;
- [ ] two independent SSH keys tested;
- [ ] exact Infra Git revision;
- [ ] Hcloud resource inventory;
- [ ] two Ready nodes and placement labels/taint;
- [ ] operator and CRD health;
- [ ] DNS and wildcard resolution;
- [ ] certificate SAN/expiry and renewal dry-run;
- [ ] Traefik, redirect, Headlamp, and wildcard route tests;
- [ ] Frappe v16 Bench/Site/asset acceptance;
- [ ] restricted positive and negative RBAC results;
- [ ] protected MariaDB health;
- [ ] smoke cleanup result;
- [ ] capacity snapshot;
- [ ] restricted kubeconfig delivered securely;
- [ ] Platform joint acceptance and sign-off.

## Authoritative References

- Hetzner project members and roles:
  <https://docs.hetzner.com/cloud/general/faq/#what-are-projects-and-how-can-i-use-them>
- Official `hcloud` CLI setup and contexts:
  <https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md>
- Hetzner server creation and SSH-key behavior:
  <https://docs.hetzner.com/cloud/servers/getting-started/creating-a-server/>
- Certbot DNS plugins and DNS-01 operation:
  <https://eff-certbot.readthedocs.io/en/stable/using.html#dns-plugins>
