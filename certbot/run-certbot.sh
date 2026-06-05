#!/usr/bin/env sh
set -eu

: "${GODADDY_CREDENTIALS_FILE:=/var/run/godaddy/credentials.ini}"
: "${CERTBOT_DOMAIN:=cloud.lmnaslens.com}"
: "${CERTBOT_PROPAGATION_SECONDS:=900}"

case "${1:-issue}" in
  issue)
    : "${CERTBOT_EMAIL:?Set CERTBOT_EMAIL}"
    certbot certonly \
      --non-interactive \
      --agree-tos \
      --email "$CERTBOT_EMAIL" \
      --cert-name "$CERTBOT_DOMAIN" \
      --authenticator dns-godaddy \
      --dns-godaddy-credentials "$GODADDY_CREDENTIALS_FILE" \
      --dns-godaddy-propagation-seconds "$CERTBOT_PROPAGATION_SECONDS" \
      --deploy-hook /usr/local/bin/deploy-certificate \
      -d "$CERTBOT_DOMAIN" \
      -d "*.$CERTBOT_DOMAIN"
    ;;
  renew)
    certbot renew \
      --non-interactive \
      --no-random-sleep-on-renew \
      --deploy-hook /usr/local/bin/deploy-certificate
    ;;
  renew-dry-run)
    certbot renew \
      --dry-run \
      --non-interactive \
      --no-random-sleep-on-renew \
      --deploy-hook /usr/local/bin/deploy-certificate
    ;;
  plugins)
    certbot plugins
    ;;
  *)
    exec "$@"
    ;;
esac
