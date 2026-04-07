#!/bin/bash
set -e

CLUSTER_NAME="iotcluster"
PIDS_FILE="/tmp/iot_p3_pids"



echo "[1/4] Stopping background port-forwards..."
if [ -f "$PIDS_FILE" ]; then
  while IFS= read -r pid; do
    kill "$pid" 2>/dev/null && echo "  Killed PID $pid" || true
  done < "$PIDS_FILE"
  rm -f "$PIDS_FILE"
fi

pkill -f "kubectl port-forward.*k3d-${CLUSTER_NAME}" 2>/dev/null || true
echo "  Port-forwards stopped."


echo "[2/4] Deleting k3d cluster '${CLUSTER_NAME}'..."
if command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  k3d cluster delete "${CLUSTER_NAME}"
  echo "  Cluster deleted."
else
  echo "  No cluster named '${CLUSTER_NAME}' found — skipping."
fi


echo "[3/4] Removing stale Docker containers for cluster '${CLUSTER_NAME}'..."
if docker info >/dev/null 2>&1; then

  CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null \
    | grep "^k3d-${CLUSTER_NAME}-" || true)
  if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | xargs docker rm -f
    echo "  Removed: $CONTAINERS"
  else
    echo "  No containers for cluster '${CLUSTER_NAME}' found — skipping."
  fi
else
  echo "  Docker daemon not running — skipping."
fi


echo "[4/4] Clearing leftover kubeconfig context..."
kubectl config delete-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
kubectl config delete-cluster "k3d-${CLUSTER_NAME}"  2>/dev/null || true
kubectl config unset "users.admin@k3d-${CLUSTER_NAME}" 2>/dev/null || true
echo "  Kubeconfig cleaned."

echo ""
echo "Clean complete!"
