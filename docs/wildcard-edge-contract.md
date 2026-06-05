# Wildcard Edge Contract

## Purpose

LensCloud standard Sites use:

```text
cloud.lmnaslens.com
*.cloud.lmnaslens.com
```

GoDaddy remains authoritative for `lmnaslens.com`. The wildcard A record points
to the EU ingress endpoint `116.203.22.81`. No per-Site DNS record or
certificate is created during onboarding.

## Ownership

LensCloud Infra owns:

- GoDaddy wildcard/apex records
- Traefik installation and health
- wildcard certificate issuance and renewal
- GoDaddy production API credentials
- `traefik/lenscloud-cloud-wildcard-tls`
- non-secret edge readiness handoff

LensCloud Platform owns:

- unique hostname reservation
- Region and Cluster placement
- Frappe Site, database, and route orchestration
- customer/operator accessibility status

LensCloud Platform never receives GoDaddy credentials and never calls the
GoDaddy API for standard Sites.

## Certificate Runtime

Certbot uses `certbot-dns-godaddy==2.8.0` with a production GoDaddy API key.
The plugin creates temporary `_acme-challenge` TXT records only for ACME
validation. The certificate contains:

```text
cloud.lmnaslens.com
*.cloud.lmnaslens.com
```

`headlamp.cloud.lmnaslens.com` is covered by the wildcard.

Certificate state is stored in `lenscloud-edge/certbot-state`. A daily CronJob
renews the certificate and deploys it to:

```text
namespace: traefik
Secret: lenscloud-cloud-wildcard-tls
```

Traefik's default TLSStore serves this certificate to customer routes.

## Site Routing

Each FrappeSite uses:

- its full hostname as `siteName` and `domain`
- ingress class `traefik`
- `websecure` and TLS router annotations
- no per-Site Certificate
- no per-Site DNS object
- no per-Site TLS Secret

Deleting a Site must not remove wildcard DNS, Certbot state, or the shared TLS
Secret.

## Multi-Region Constraint

One wildcard A record points to one edge endpoint. Before EU and US actively
serve the same wildcard namespace, add a global routing layer with regional
origin pools and health checks. Do not reintroduce per-customer DNS records.

## Required Handoff

Infra publishes:

- root domain and wildcard hostname
- wildcard target and resolution status
- ingress class and entrypoints
- TLS Secret reference, readiness, and expiry
- certificate renewal status
- route health
- regional edge mode

Never publish DNS credentials or TLS private keys.

## Acceptance Test

1. Confirm an arbitrary wildcard hostname resolves to `116.203.22.81`.
2. Confirm GoDaddy TXT create/read/restore preflight passes.
3. Issue the wildcard certificate.
4. Run `certbot renew --dry-run`.
5. Create `wildcard-smoke.cloud.lmnaslens.com`.
6. Confirm HTTPS presents the wildcard certificate.
7. Confirm no per-Site DNS or Certificate resource exists.
8. Delete a test route and verify shared edge resources remain.

## Workitems

| Work Item | Expected Outcome | Status |
|---|---|---|
| GoDaddy wildcard A record | Arbitrary customer hostnames resolve to EU ingress | Complete |
| GoDaddy production API preflight | Disposable TXT record can be created and restored | Complete |
| Build and pin Certbot GoDaddy image | Immutable compatible image is available to K3s | Complete |
| Store GoDaddy credentials in Kubernetes | Infra-only Secret exists | Complete |
| Issue and dry-run renew certificate | Shared TLS Secret is valid and renewable | Complete |
| Cut over Traefik public ports | HTTPS, redirect, Headlamp, and Sites pass | Complete |
| Rehearse ingress-nginx rollback | Legacy ingress can be restored before retirement | Complete |
| Retire ingress-nginx | Traefik is the sole live public ingress | Complete |
| Design EU/US global routing | Region placement works under one wildcard | Later |
