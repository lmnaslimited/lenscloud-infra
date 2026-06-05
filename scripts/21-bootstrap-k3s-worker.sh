#!/usr/bin/env bash
set -euo pipefail

MANAGER_PRIVATE_IP="${1:?manager private IP required}"
NODE_TOKEN="${2:?K3s node token required}"
WORKER_PRIVATE_IP="${3:?worker private IP required}"

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
apt-get install -y curl ca-certificates

if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | K3S_URL="https://${MANAGER_PRIVATE_IP}:6443" K3S_TOKEN="${NODE_TOKEN}" INSTALL_K3S_EXEC="agent --node-ip ${WORKER_PRIVATE_IP} --flannel-iface enp7s0" sh -
fi

systemctl enable k3s-agent
systemctl restart k3s-agent
systemctl status k3s-agent --no-pager
