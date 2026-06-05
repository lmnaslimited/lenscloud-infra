FROM certbot/certbot:v5.5.0@sha256:78a7eaa40af657301e25731297b6e73646c695370d17e9bb03189fa82966d65c

ARG GODADDY_PLUGIN_VERSION=2.8.0
ARG KUBECTL_VERSION=v1.35.5

RUN apk add --no-cache curl \
    && python -m pip install --no-cache-dir \
      "certbot-dns-godaddy==${GODADDY_PLUGIN_VERSION}" \
    && curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && apk del curl

COPY deploy-certificate.sh /usr/local/bin/deploy-certificate
COPY run-certbot.sh /usr/local/bin/run-certbot

RUN chmod 0755 /usr/local/bin/deploy-certificate /usr/local/bin/run-certbot \
    && certbot plugins | grep -q dns-godaddy

ENTRYPOINT ["/usr/local/bin/run-certbot"]
