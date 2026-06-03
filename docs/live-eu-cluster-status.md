# Live EU Cluster Status

## Cluster

- Cluster: `lenscloud-eu-dev`
- Location: `nbg1`
- Manager: `lenscloud-eu-manager-1`
- Manager public IP: `116.203.22.81`
- Manager private IP: `10.20.1.1`
- Worker: `lenscloud-eu-worker-1`
- Worker public IP: `116.203.42.9`
- Worker private IP: `10.20.1.2`
- Manager taint: `lenscloud.io/manager-only=true:NoSchedule`
- Hcloud private network: `10.20.0.0/16`
- K3s pod network: default `10.42.0.0/16`
- K3s service network: default `10.43.0.0/16`

## Access

- Kubernetes CLI runs on the manager VM.
- Headlamp URL: `http://headlamp.eu.lmnaslens.com`
- DNS currently points `headlamp.eu.lmnaslens.com` to `116.203.22.81`.
- Generate a Headlamp token on the manager:

```bash
kubectl -n headlamp create token headlamp-frappe-operator
```

## Runtime

- Ingress: `ingress-nginx`
- MariaDB Operator: running
- Frappe Operator: running
- Headlamp: running
- Smoke MariaDB: `frappe-mariadb`
- Smoke bench: `dev-bench`
- Smoke site: `dev-site`

## Smoke Result

The smoke test completed successfully:

- `FrappeBench/dev-bench`: `Ready`
- `FrappeSite/dev-site`: `Ready`
- MariaDB PVC: bound with `local-path`
- Bench PVC: bound with `local-path`
- Smoke app/database pods: running on `lenscloud-eu-worker-1`
- Login page: HTTP 200 through manager-local port-forward

The Frappe Operator pairing that worked is:

- CRD API: `vyogo.tech/v1`
- Operator image: `ghcr.io/vyogotech/frappe-operator:4.0.0`
