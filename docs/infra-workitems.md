# Infra Workitems

This is the canonical tracker for LensCloud Infra. Product work is tracked in
`lenscloud-platform`.

| Workitem | Outcome | Status |
| --- | --- | --- |
| EU K3s substrate | Manager, worker, private network, firewall, storage | Complete |
| Operators and edge | MariaDB Operator, Frappe Operator, Traefik, wildcard TLS | Complete |
| Restricted Platform access | Server-side kubeconfig and baseline RBAC | Complete |
| Runtime lifecycle authority | Runtime CRUD/delete, ownership admission guard, protected baseline | Complete |
| Lifecycle permission evidence | Positive managed deletes and protected/unowned denial | Complete |
| Public acceptance cleanup | Remove only `run-20260607-0623*` runtime resources | Complete |
| Infra-to-Platform lifecycle handoff | Publish exact authority, limits, and next Platform work | Complete |
| Private Shared/Private capacity | Confirm sequential acceptance headroom | Complete |
| US region | Repeatable second regional cluster | Later |
| Local Docker runtime | Standalone developer runtime | Later |

## Current Gate

Platform may resume Private Shared and Private acceptance sequentially.
`MariaDB/default/frappe-mariadb` remains protected and available as the Public
database baseline.

Evidence: `docs/platform-runtime-lifecycle-evidence-20260608.md`.
