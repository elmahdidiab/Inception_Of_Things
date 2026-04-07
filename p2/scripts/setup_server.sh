#!/bin/bash
set -e

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644" sh -

echo "Waiting for K3s API..."
until kubectl get --raw='/readyz' >/dev/null 2>&1; do sleep 2; done

echo "Waiting for node Ready..."
NODE=$(hostname | tr '[:upper:]' '[:lower:]')
until [ "$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
  sleep 2
done
echo "K3s node is ready."

echo "Pre-pulling nginx:alpine image..."
sudo k3s crictl pull nginx:alpine

kubectl apply -f /tmp/confs/

echo "Waiting for all pods to be Running..."
for i in $(seq 1 120); do
  TOTAL=$(kubectl get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
  READY=$(kubectl get pods --no-headers 2>/dev/null | grep -cE '([0-9]+)/\1' || true)
  if [ "$TOTAL" -gt 0 ] && [ "$READY" -eq "$TOTAL" ]; then
    echo "  All $TOTAL pods ready."
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "  Warning: pods not all ready after 10 min; continuing anyway."
  else
    echo "  Waiting... ($READY/$TOTAL ready)"
    sleep 5
  fi
done

echo "All applications deployed successfully."
kubectl get pods -o wide
kubectl get ingress