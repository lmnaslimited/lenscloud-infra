# Site Setup Complete Queue Overloaded

Date: 2026-07-20
Reported by: Platform
Source handoff:
`lenscloud-platform/frappe-bench/apps/lenscloud/docs/handoffs/infra/site-setup-complete-queue-overloaded-20260720.md`

## Status

Resolved at live infra/runtime level. Platform retry pending.

## Incident

`site_setup.complete` failed for:

```text
Site: tharahub.cloud.lmnaslens.com
Bench: run-20260702-free-prod-bench
Namespace: lenscloud-runtime-eu
Cluster: lenscloud-eu-dev
Action Log: ORCH-2026-00656
```

Sanitized failure:

```text
frappe.exceptions.QueueOverloaded: Too many queued background jobs (750).
```

## Findings

The target Bench Redis queue existed and was reachable. The app-aware
setup-complete Job reached Frappe/Redis far enough for Frappe to count queued
jobs and reject enqueueing.

Before remediation:

```text
run-20260702-free-prod-bench-worker-default  0/0
run-20260702-free-prod-bench-worker-short    0/0
run-20260702-free-prod-bench-worker-long     0/0

rq:queue:home-frappe-frappe-bench:default = 766
rq:queue:home-frappe-frappe-bench:long    = 204
```

The FrappeBench CR desired workers at zero replicas, so this was not only a
Deployment drift:

```text
worker-default.staticReplicas = 0
worker-short.staticReplicas   = 0
worker-long.staticReplicas    = 0
```

## Remediation

Live patched the FrappeBench CR:

```text
scheduler.staticReplicas      = 1
worker-default.staticReplicas = 1
worker-short.staticReplicas   = 1
worker-long.staticReplicas    = 1
```

Workers rolled out and consumed queued jobs. No Redis queue keys were flushed.

After remediation:

```text
run-20260702-free-prod-bench-scheduler        1/1
run-20260702-free-prod-bench-worker-default   1/1
run-20260702-free-prod-bench-worker-short     1/1
run-20260702-free-prod-bench-worker-long      1/1

rq:queue:home-frappe-frappe-bench:default = 0
rq:queue:home-frappe-frappe-bench:long    = 0
```

## Follow-Up

Platform generator must keep active Benches at one scheduler and one worker per
queue unless a separate autoscaling/min-replica policy replaces static
replicas. Infra SOP now requires worker and queue checks before customer setup
retries, app-aware setup tests, and Bench upgrades.
