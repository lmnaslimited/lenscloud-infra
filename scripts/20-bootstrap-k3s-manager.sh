#!/usr/bin/env bash
set -euo pipefail

PUBLIC_IP="${1:?manager public IP required}"
PRIVATE_IP="${2:?manager private IP required}"

install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-lenscloud.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 3
EOF
chmod 644 /etc/ssh/sshd_config.d/99-lenscloud.conf
sshd -t
systemctl restart ssh

if ! swapon --show | grep -q /swapfile; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
fi

grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

cat >/etc/sysctl.d/99-k3s-lenscloud.conf <<'EOF'
vm.swappiness=10
fs.inotify.max_user_instances=1024
fs.inotify.max_user_watches=1048576
EOF
sysctl --system

apt-get update
apt-get install -y curl ca-certificates jq gettext-base git

if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable=traefik --node-ip ${PRIVATE_IP} --advertise-address ${PRIVATE_IP} --flannel-iface enp7s0 --tls-san ${PUBLIC_IP} --tls-san ${PRIVATE_IP}" sh -
fi

systemctl enable k3s
systemctl restart k3s

for _ in $(seq 1 90); do
  if k3s kubectl get nodes >/dev/null 2>&1; then
    mkdir -p /root/.kube
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
    chmod 600 /root/.kube/config
    k3s kubectl get nodes
    exit 0
  fi
  sleep 2
done

systemctl status k3s --no-pager
exit 1
