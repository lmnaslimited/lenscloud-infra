# Bench And Site Smoke SOP

Run on the manager VM.

```bash
cd /root/lenscloud-infra
export KUBECONFIG=/root/.kube/config

./scripts/60-run-smoke.sh
./scripts/70-verify-runtime.sh
```

Expected objects:

```bash
kubectl get nodes -o wide
kubectl get mariadb,frappebench,frappesite,pvc,pods -o wide
```

The smoke manifests request:

```yaml
nodeSelector:
  lenscloud.io/node-role: worker
```

This proves the first placement rule: app/database pods run on the worker node, while Kubernetes administration stays on the manager.

The reusable model puts `dbConfig.mariadbRef` on `FrappeBench`; Sites inherit
that database server.

If the generic smoke test passes, the LensCX custom image can be tested next:

```bash
kubectl apply -f manifests/smoke/lenscx-bench.yaml
kubectl apply -f manifests/smoke/lenscx-sites.yaml
```

Run the proven two-Bench smoke:

```bash
./scripts/42-run-shared-database-smoke.sh
```

It creates two separate `FrappeBench` resources that both carry:

```yaml
spec:
  dbConfig:
    provider: mariadb
    mode: shared
    mariadbRef:
      name: frappe-mariadb
      namespace: default
```

The script creates one Site under each Bench and verifies distinct logical
database/user identifiers and credential Secrets on the same MariaDB server.
See [database-server-runtime-contract.md](./database-server-runtime-contract.md).
