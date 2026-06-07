# Infra Workitems

This is the canonical tracker for LensCloud Infra. Product work is tracked in
`lenscloud-platform`.

| Workitem | Outcome | Status |
| --- | --- | --- |
| EU K3s substrate | Manager, worker, private network, firewall, storage | Complete |
| Operators and edge | MariaDB Operator, Frappe Operator, Traefik, wildcard TLS | Complete |
| Restricted Platform access | Server-side kubeconfig and baseline RBAC | Complete |
| Runtime lifecycle authority | Runtime CRUD/delete, ownership admission guard, protected baseline | In progress |
| Lifecycle permission evidence | Positive managed deletes and protected/unowned denial | Pending live verification |
| Public acceptance cleanup | Remove only `run-20260607-0623*` runtime resources | Pending live verification |
| Infra-to-Platform lifecycle handoff | Publish exact authority, limits, and next Platform work | In progress |
| Private Shared/Private capacity | Confirm sequential acceptance headroom | Pending post-cleanup check |
| US region | Repeatable second regional cluster | Later |
| Local Docker runtime | Standalone developer runtime | Later |

## Current Gate

Infra must finish and publish the lifecycle authority handoff before Platform
resumes Private Shared and Private acceptance. `MariaDB/default/frappe-mariadb`
is protected and must remain available as the Public database baseline.
