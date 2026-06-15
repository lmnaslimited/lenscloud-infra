# LensCloud Test Cluster Handoff Record

Do not include credentials, Secret values, tokens, private keys, or kubeconfig
content in this record.

## Build

- Handoff ID:
- Build date:
- Infra operator:
- Team lead:
- Platform owner:
- Hetzner project:
- Infra Git revision:
- Change/approval reference:

## Cluster

- Cluster name: `lenscloud-eu-test`
- Provider: `hcloud`
- Region/environment: EU Test
- Manager name:
- Manager public IPv4:
- Manager private IPv4:
- Worker name:
- Worker private IPv4:
- Location:
- K3s/Kubernetes version:
- Private network:
- Firewall:
- Default StorageClass: `local-path`
- Runtime namespace: `lenscloud-runtime-eu`

## Human Access

- Project Owner:
- Team Lead role verified:
- Infra Operator role verified:
- Infra SSH fingerprint:
- Team Lead SSH fingerprint:
- Infra SSH test result:
- Team Lead break-glass SSH test result:
- 2FA confirmation:

## Operators

- MariaDB Operator version/status:
- Frappe Operator version/status:
- Frappe API version:
- Required CRDs:
- Headlamp version/status:
- Headlamp URL:

## Edge

- Root domain: `testcloud.lmnaslens.com`
- Wildcard hostname: `*.testcloud.lmnaslens.com`
- Wildcard target:
- DNS resolver tests:
- Ingress class: `traefik`
- HTTP redirect result:
- Certificate issuer:
- Certificate SANs:
- Certificate expiry:
- Renewal dry-run result:
- Headlamp HTTPS result:
- Wildcard route result:
- Rollback rehearsal result:

## Runtime Acceptance

- Shared MariaDB: `MariaDB/default/frappe-mariadb`
- Shared MariaDB health:
- Frappe image:
  `ghcr.io/lmnaslimited/lensdocker/lens-pure:v16.14.1`
- Bench Ready result:
- Site Ready result:
- Site URL: `https://handoff.testcloud.lmnaslens.com`
- HTTPS result:
- Generated asset result:
- Workload worker-placement result:
- Smoke cleanup result:
- Protected baseline preserved:

## Restricted Platform Access

- Service account:
  `lenscloud-platform-system/lenscloud-platform`
- Credential filename: `lenscloud-eu-test.kubeconfig`
- Platform credential reference:
  `file:/run/secrets/lenscloud-eu-test.kubeconfig`
- Credential delivery channel:
- File mode verified:
- Port 6443 source `/32`:
- Positive RBAC result:
- Negative RBAC result:
- Unlabelled deletion denial:
- Protected MariaDB denial:
- Platform Python API preflight:

## Capacity

- Node readiness:
- Pressure conditions:
- Worker CPU requests:
- Worker memory requests:
- Worker available memory:
- Worker free disk:
- Warnings:

## Retained Resources

- Shared MariaDB:
- Operators:
- Edge/TLS:
- Headlamp:
- Platform RBAC:
- Other:

## Open Risks

- Database HA:
- Backups/restore:
- NetworkPolicy:
- Multi-region routing:
- Monitoring/alerting:
- Other:

## Sign-Off

- Infra acceptance:
- Team Lead acceptance:
- Platform acceptance:
- Handoff timestamp:
- Platform live-apply state after acceptance:
