#!/bin/bash
set -e

ip addr add 192.168.56.111/24 dev eth0 2>/dev/null || true

echo "Waiting for node-token..."
until [ -f /tmp/node-token ] && [ -s /tmp/node-token ]; do
  sleep 2
done

K3S_TOKEN=$(cat /tmp/node-token)

K3S_URL="https://10.0.2.2:6443"

echo "Joining cluster at $K3S_URL ..."
curl -sfL https://get.k3s.io | \
  K3S_URL="${K3S_URL}" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111" \
  INSTALL_K3S_SKIP_START=true \
  sh -

systemctl enable k3s-agent
nohup systemctl start k3s-agent >/dev/null 2>&1 &
echo "K3s agent service enabled and started."
