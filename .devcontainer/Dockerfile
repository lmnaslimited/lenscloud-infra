FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    python3 \
    python3-pip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspaces/lenscloud-infra

