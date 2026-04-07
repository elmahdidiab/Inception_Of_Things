#!/bin/bash
set -e

ip addr add 192.168.56.110/24 dev eth0 2>/dev/null || true

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644 --node-ip=192.168.56.110 --tls-san=10.0.2.2 --tls-san=192.168.56.110" \
  sh -

echo "Waiting for K3s API..."
until kubectl get --raw='/readyz' >/dev/null 2>&1; do sleep 2; done

echo "Waiting for node Ready..."
NODE=$(hostname | tr '[:upper:]' '[:lower:]')
until [ "$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
  sleep 2
done

echo "K3s server is ready."
kubectl get nodes -o wide
