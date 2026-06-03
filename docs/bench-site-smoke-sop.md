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

If the generic smoke test passes, the LensCX custom image can be tested next:

```bash
kubectl apply -f manifests/smoke/lenscx-bench.yaml
kubectl apply -f manifests/smoke/lenscx-sites.yaml
```

