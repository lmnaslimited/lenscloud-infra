# EU Cluster SOP

This SOP recreates the first LensCloud EU runtime cluster with one K3s manager and one K3s worker. Kubernetes administration happens from the manager VM.

The Hcloud private network must not overlap with K3s defaults. This SOP uses `10.20.0.0/16` for Hcloud private networking and lets K3s keep its default pod/service ranges. K3s flannel is forced onto Hcloud's private interface `enp7s0`.

## 1. Local Hcloud Setup

Run these commands from the machine that has `hcloud` access.

```bash
cd /Users/arunkumar.ganesan/lensk8s/lenscloud-infra

export REGION=eu
export CLUSTER_NAME=lenscloud-eu-dev
export LOCATION=nbg1
export NETWORK_ZONE=eu-central
export NETWORK_NAME=lenscloud-eu-net
export NETWORK_CIDR=10.20.0.0/16
export SUBNET_CIDR=10.20.1.0/24
export FIREWALL_NAME=lenscloud-eu-firewall
export MANAGER_NAME=lenscloud-eu-manager-1
export WORKER_NAME=lenscloud-eu-worker-1
export MANAGER_TYPE=cx23
export WORKER_TYPE=cx33
export SSH_KEY_NAME=team-lead-key
export ADMIN_CIDR="$(curl -fsSL https://ifconfig.me)/32"
export HEADLAMP_HOST=headlamp.eu.lmnaslens.com

./scripts/10-create-hcloud-eu-nodes.sh
```

## 2. Capture Node Addresses

```bash
export MANAGER_PUBLIC_IP="$(hcloud server describe "$MANAGER_NAME" -o json | jq -r '.public_net.ipv4.ip')"
export WORKER_PUBLIC_IP="$(hcloud server describe "$WORKER_NAME" -o json | jq -r '.public_net.ipv4.ip')"
export MANAGER_PRIVATE_IP="$(hcloud server describe "$MANAGER_NAME" -o json | jq -r '.private_net[] | select(.network.name == env.NETWORK_NAME) | .ip')"
export WORKER_PRIVATE_IP="$(hcloud server describe "$WORKER_NAME" -o json | jq -r '.private_net[] | select(.network.name == env.NETWORK_NAME) | .ip')"

echo "$MANAGER_PUBLIC_IP $MANAGER_PRIVATE_IP"
echo "$WORKER_PUBLIC_IP $WORKER_PRIVATE_IP"
```

## 3. Bootstrap K3s Manager

```bash
scp scripts/20-bootstrap-k3s-manager.sh "root@$MANAGER_PUBLIC_IP:/root/"
ssh "root@$MANAGER_PUBLIC_IP" "bash /root/20-bootstrap-k3s-manager.sh '$MANAGER_PUBLIC_IP' '$MANAGER_PRIVATE_IP'"
```

## 4. Join K3s Worker

```bash
export K3S_NODE_TOKEN="$(ssh "root@$MANAGER_PUBLIC_IP" "cat /var/lib/rancher/k3s/server/node-token")"

scp scripts/21-bootstrap-k3s-worker.sh "root@$WORKER_PUBLIC_IP:/root/"
ssh "root@$WORKER_PUBLIC_IP" "bash /root/21-bootstrap-k3s-worker.sh '$MANAGER_PRIVATE_IP' '$K3S_NODE_TOKEN' '$WORKER_PRIVATE_IP'"
```

## 5. Copy Infra Repo To Manager

```bash
ssh "root@$MANAGER_PUBLIC_IP" "mkdir -p /root/lenscloud-infra"
scp -r scripts manifests docs "root@$MANAGER_PUBLIC_IP:/root/lenscloud-infra/"
```

From this point, run Kubernetes commands on the manager VM:

```bash
ssh "root@$MANAGER_PUBLIC_IP"
cd /root/lenscloud-infra
export KUBECONFIG=/root/.kube/config
```

## 6. Label Nodes

```bash
export MANAGER_NAME=lenscloud-eu-manager-1
export WORKER_NAME=lenscloud-eu-worker-1
./scripts/30-label-nodes.sh
```

This labels the manager and worker, then taints the manager:

```text
lenscloud.io/manager-only=true:NoSchedule
```

The taint keeps future customer/runtime workloads on the worker node by default.

## 7. Install Operators And UI

```bash
./scripts/35-install-ingress.sh
./scripts/40-install-operators.sh
./scripts/50-install-headlamp.sh
```

## 8. Configure DNS

Create or update this DNS record:

```text
headlamp.eu.lmnaslens.com -> MANAGER_PUBLIC_IP
```

For the first pass this is HTTP. Add TLS after HTTP access is verified.

The live EU dev cluster currently uses:

```text
headlamp.eu.lmnaslens.com -> 116.203.22.81
```

## 9. Run Smoke Test

```bash
./scripts/60-run-smoke.sh
./scripts/70-verify-runtime.sh
```

Watch readiness:

```bash
kubectl get mariadb,frappebench,frappesite,pods,pvc -w
```

Expected result:

```text
FrappeBench/dev-bench: Ready
FrappeSite/dev-site: Ready
MariaDB/frappe-mariadb: Running
```

Verify the login page from the manager:

```bash
(kubectl port-forward svc/dev-bench-nginx 18080:8080 >/tmp/dev-bench-port-forward.log 2>&1 & echo $! >/tmp/dev-bench-port-forward.pid)
sleep 4
curl -I -H 'Host: dev.localhost' http://127.0.0.1:18080
kill "$(cat /tmp/dev-bench-port-forward.pid)"
```

## 10. Headlamp Token

```bash
kubectl -n headlamp create token headlamp-frappe-operator
```

Use the token at:

```text
http://headlamp.eu.lmnaslens.com
```

## 11. Destroy Dev Cluster

Run from the local machine with `hcloud` access:

```bash
export CONFIRM_DESTROY=yes
./scripts/90-destroy-hcloud-eu-cluster.sh
```
