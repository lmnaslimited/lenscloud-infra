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
- Current Headlamp URL: `https://headlamp.cloud.lmnaslens.com`
- Legacy rollback URL: `http://headlamp.eu.lmnaslens.com`
- Generate a Headlamp token on the manager:

```bash
kubectl -n headlamp create token headlamp-frappe-operator
```

## Runtime

- Ingress: Traefik 3.7.1
- Public HTTP/HTTPS: Traefik owns ports 80/443
- HTTP redirects to HTTPS
- Traefik ServiceLB runs on manager and worker; its manager pod has a narrowly
  scoped toleration for `lenscloud.io/manager-only=true:NoSchedule`
- ingress-nginx: removed after a successful rollback rehearsal
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

## Database Server Handoff

The smoke MariaDB is the first Database Server candidate for LensCloud Platform:

- Region: EU
- Cluster: `lenscloud-eu-dev`
- privacy for first smoke registration: Public
- namespace: `default`
- operator resource name: `frappe-mariadb`
- image: `mariadb:10.11`
- storage: `8Gi` on `local-path`
- replicas: `1`
- root credential reference: Secret `frappe-mariadb-root`, key `password`

This is shared POC capacity, not HA. Secret values are not part of the platform handoff.

## Wildcard Edge Status

Target:

- root domain: `cloud.lmnaslens.com`
- wildcard DNS: `*.cloud.lmnaslens.com`
- customer ingress: Traefik
- DNS authority: GoDaddy
- certificate lifecycle: Certbot DNS-01 using infrastructure-only GoDaddy production API credentials
- shared certificate: `cloud.lmnaslens.com`, `*.cloud.lmnaslens.com`
- target TLS Secret: `traefik/lenscloud-cloud-wildcard-tls`

Current state:

- Traefik 3.7.1 owns public ports 80/443
- HTTP redirects to HTTPS with status 301
- `wildcard-smoke.cloud.lmnaslens.com` is a Ready FrappeSite and returns HTTPS
  200 without a per-Site DNS or Certificate resource
- `headlamp.cloud.lmnaslens.com` returns HTTPS 200
- Certbot namespace, restricted RBAC, service account, and state PVC are active
- GoDaddy production API TXT create/read/restore preflight passed
- Certbot GoDaddy image published at `ghcr.io/lmnaslimited/lenscloud-certbot-godaddy@sha256:d237a693c908b14ec9a49158d973a0c81c43efaf0e4c27552f1c94d9b5489814`
- GoDaddy credentials are stored in the infra-only Secret
  `lenscloud-edge/godaddy-dns-api`
- wildcard certificate issuance completed successfully
- certificate names: `cloud.lmnaslens.com`, `*.cloud.lmnaslens.com`
- certificate issuer: Let's Encrypt
- certificate expiry: September 3, 2026 at 14:49 UTC
- TLS Secret: `traefik/lenscloud-cloud-wildcard-tls`
- `certbot renew --dry-run` completed successfully
- renewal CronJob: `lenscloud-edge/certbot-wildcard-renew`
- renewal schedule: daily at 02:17 UTC
- Traefik default TLSStore is active
- ingress-nginx rollback was exercised successfully before its live deployment
  was removed
- deleting the temporary Traefik smoke route preserved the wildcard TLS Secret,
  Certbot state PVC, renewal CronJob, and Frappe routes

The GoDaddy wildcard record resolves customer hostnames to `116.203.22.81`.

EU customer Site HTTPS is Ready for the Phase 1 wildcard domain contract.

The Frappe Operator pairing that worked is:

- CRD API: `vyogo.tech/v1`
- Operator image: `ghcr.io/vyogotech/frappe-operator:4.0.0`

## Shared Database Smoke

Completed on June 5, 2026:

- `shared-db-bench-a`: Ready
- `shared-db-bench-b`: Ready
- `shared-db-site-a`: Ready
- `shared-db-site-b`: Ready
- both Benches reference `MariaDB/default/frappe-mariadb`
- each Site received a distinct logical database and database user
- all MariaDB, Bench, and Site initialization pods ran on `lenscloud-eu-worker-1`
- MariaDB remains one replica on `local-path`; this is explicitly non-HA
