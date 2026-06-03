# Operator Install SOP

Run on the K3s manager VM from `/root/lenscloud-infra`.

```bash
export KUBECONFIG=/root/.kube/config
./scripts/35-install-ingress.sh
./scripts/40-install-operators.sh
```

Verify:

```bash
kubectl get pods -A
kubectl get crd | grep -E 'frappe|mariadb|sitebackup|siterestore'
```

Required Frappe Operator resources:

- `FrappeBench`
- `FrappeSite`
- `SiteBackup`
- `SiteRestore`

Do not assume `SiteJob` is production-ready until the operator implementation proves it.

## Compatibility Notes

The working Frappe Operator pairing for the EU dev cluster is:

- API version: `vyogo.tech/v1`
- image: `ghcr.io/vyogotech/frappe-operator:4.0.0`

Do not mix this with older package tags that expect `vyogo.tech/v1alpha1`.

The MariaDB Operator requires both Helm charts:

- `mariadb-operator-crds`
- `mariadb-operator`
