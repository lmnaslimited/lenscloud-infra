# Headlamp SOP

Headlamp is the first operational UI for the platform team. It starts in the EU cluster and can later include the US cluster through a multi-context kubeconfig.

## Current EU Access

Headlamp is installed in namespace `headlamp`.

```bash
kubectl -n headlamp get pods,svc,ingress
kubectl -n headlamp create token headlamp-frappe-operator
```

Open:

```text
http://headlamp.eu.lmnaslens.com
```

Current DNS target:

```text
headlamp.eu.lmnaslens.com -> 116.203.22.81
```

## RBAC Boundary

The `headlamp-frappe-operator` service account can:

- read cluster nodes, namespaces, CRDs, pods, services, events, PVCs
- manage Frappe Operator resources in the runtime namespace
- read MariaDB Operator resources

If Headlamp menus are hidden or disabled, check RBAC first.

## Multi-Cluster Direction

Headlamp supports multiple clusters using kubeconfig contexts. For US later:

1. Create the US cluster.
2. Create a restricted service account/token for the US cluster.
3. Add the US context to the Headlamp kubeconfig.
4. Verify the cluster switcher shows EU and US.

For production, consider moving Headlamp into a dedicated management cluster if EU and US runtime isolation should not depend on the EU cluster.
