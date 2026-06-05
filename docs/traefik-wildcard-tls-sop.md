# Traefik And Wildcard TLS SOP

Run Kubernetes commands on `lenscloud-eu-manager-1` from
`/root/lenscloud-infra`.

## Variables

```bash
export WILDCARD_TARGET=116.203.22.81
export WORKER_PRIVATE_IP=10.20.1.2
export CERTBOT_IMAGE_REPOSITORY=ghcr.io/lmnaslimited/lenscloud-certbot-godaddy
export CERTBOT_IMAGE_TAG=2.8.0
export CERTBOT_EMAIL=operations@lmnas.com
```

## 1. Verify DNS

GoDaddy must contain:

```text
cloud.lmnaslens.com -> 116.203.22.81
*.cloud.lmnaslens.com -> 116.203.22.81
```

Verify:

```bash
dig +short A cloud.lmnaslens.com @1.1.1.1
dig +short A test.cloud.lmnaslens.com @1.1.1.1
```

## 2. Stage Traefik

```bash
./scripts/36-install-traefik-side-by-side.sh
WORKER_PRIVATE_IP="$WORKER_PRIVATE_IP" ./scripts/37-validate-traefik-side-by-side.sh
```

Ingress-nginx keeps public ports 80/443 while Traefik uses NodePorts
30080/30443.

The manager has a workload-exclusion taint. During cutover,
`34-allow-servicelb-on-manager.sh` adds a toleration only to the selected K3s
ServiceLB DaemonSet so the public manager IP can bind ports 80/443 without
making the manager generally schedulable.

## 3. Build And Publish Certbot

On a Docker host authenticated to GHCR:

```bash
export PUSH_CERTBOT_IMAGE=true
./scripts/40-build-certbot-image.sh
docker image inspect \
  "$CERTBOT_IMAGE_REPOSITORY:$CERTBOT_IMAGE_TAG" \
  --format '{{index .RepoDigests 0}}'
```

Record the immutable digest:

```bash
export CERTBOT_IMAGE='ghcr.io/lmnaslimited/lenscloud-certbot-godaddy@sha256:REPLACE_ME'
```

## 4. Store GoDaddy Credentials

On the manager, in the shell that holds the production credentials:

```bash
./scripts/43-preflight-godaddy-api.sh
./scripts/43-create-godaddy-secret.sh
unset GODADDY_API_KEY GODADDY_API_SECRET
kubectl -n lenscloud-edge get secret godaddy-dns-api
```

Never commit or print the credential values.

## 5. Issue And Test The Certificate

```bash
CERTBOT_IMAGE="$CERTBOT_IMAGE" \
CERTBOT_EMAIL="$CERTBOT_EMAIL" \
./scripts/44-render-certbot-manifests.sh

./scripts/45-install-certbot-wildcard.sh
./scripts/46-test-certbot-renewal.sh
```

Inspect:

```bash
kubectl -n traefik get secret lenscloud-cloud-wildcard-tls
kubectl -n traefik get secret lenscloud-cloud-wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' |
  base64 -d |
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

## 6. Cut Over

```bash
export CONFIRM_TRAEFIK_CUTOVER=yes
./scripts/38-cutover-traefik.sh
./scripts/47-run-wildcard-route-smoke.sh
./scripts/49-verify-edge-runtime.sh
```

Verify HTTP redirects to HTTPS, Headlamp works at
`https://headlamp.cloud.lmnaslens.com`, and customer Sites present the wildcard
certificate.

## 7. Roll Back Or Retire Nginx

Rollback:

```bash
export CONFIRM_INGRESS_ROLLBACK=yes
./scripts/39-rollback-ingress-nginx.sh
```

After final acceptance:

```bash
export CONFIRM_RETIRE_INGRESS_NGINX=yes
./scripts/50-retire-ingress-nginx.sh
```

## Monitoring

```bash
kubectl -n lenscloud-edge get job,cronjob,pod,pvc
kubectl -n lenscloud-edge logs job/certbot-wildcard-issue
kubectl -n traefik get secret,tlsstore
```
