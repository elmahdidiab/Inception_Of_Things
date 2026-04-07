#!/bin/bash
set -e

CLUSTER_NAME="iotcluster"


echo "[1/7] Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  echo "  Homebrew already installed."
fi


echo "[2/7] Checking Docker..."
if ! command -v docker &>/dev/null; then
  brew install --cask docker
  echo ""
  echo "  Docker installed. Please open Docker.app from Applications to start the"
  echo "  Docker daemon, then re-run this script."
  open -a Docker 2>/dev/null || true
  exit 0
else
  echo "  Docker CLI found."
fi


echo "  Waiting for Docker daemon..."
WAIT=0
until docker info >/dev/null 2>&1; do
  sleep 3
  WAIT=$((WAIT + 3))
  if [ "$WAIT" -ge 120 ]; then
    echo "ERROR: Docker daemon did not start after 120s."
    exit 1
  fi
done
echo "  Docker daemon is running."


echo "[3/7] Installing k3d and kubectl..."
if ! command -v k3d &>/dev/null; then
  brew install k3d
  echo "  k3d installed."
else
  echo "  k3d already installed."
fi
if ! command -v kubectl &>/dev/null; then
  brew install kubectl
  echo "  kubectl installed."
else
  echo "  kubectl already installed."
fi


echo "[4/7] Setting up k3d cluster '${CLUSTER_NAME}'..."
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  echo "  Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 1
  echo "  Cluster '${CLUSTER_NAME}' created."
fi

mkdir -p ~/.kube
k3d kubeconfig get "${CLUSTER_NAME}" > ~/.kube/config
kubectl config use-context "k3d-${CLUSTER_NAME}"
echo "  kubectl context set to k3d-${CLUSTER_NAME}."


echo "[5/7] Creating namespaces..."
kubectl get namespace argocd >/dev/null 2>&1 || kubectl create namespace argocd
kubectl get namespace dev     >/dev/null 2>&1 || kubectl create namespace dev
echo "  Namespaces 'argocd' and 'dev' are ready."


echo "[6/7] Installing ArgoCD in namespace 'argocd'..."

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "  Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
echo "  ArgoCD is ready."


echo "[7/7] Applying ArgoCD Application manifest..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl apply -f "${SCRIPT_DIR}/../confs/application.yaml"

echo "  Waiting for wil-playground pod to be Ready..."

WAIT=0
until kubectl get pod -n dev -l app=wil-playground 2>/dev/null | grep -qv "^NAME"; do
  sleep 5; WAIT=$((WAIT + 5))
  [ "$WAIT" -ge 180 ] && { echo "  WARNING: pod not found yet, ArgoCD may still be syncing"; break; }
done

kubectl wait --for=condition=ready pod -n dev -l app=wil-playground --timeout=180s 2>/dev/null || true
kubectl get pods -n dev -l app=wil-playground 2>/dev/null || true

PIDS_FILE="/tmp/iot_p3_pids"


if [ -f "$PIDS_FILE" ]; then
  while IFS= read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < "$PIDS_FILE"
  rm -f "$PIDS_FILE"
fi
lsof -ti tcp:8080 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti tcp:8888 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

echo "  Starting self-healing port-forward watcher: ArgoCD UI → https://localhost:8080"
(
  while true; do
    kubectl port-forward -n argocd svc/argocd-server 8080:443 \
      >>/tmp/iot_pf_argocd.log 2>&1 || true

    sleep 3
  done
) &
echo $! >> "$PIDS_FILE"

echo "  Starting self-healing port-forward watcher: App → http://localhost:8888"
(
  while true; do

    kubectl wait --for=condition=ready pod -n dev -l app=wil-playground \
      --timeout=120s >>/tmp/iot_pf_app.log 2>&1 || true

    sleep 2

    lsof -ti tcp:8888 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
    kubectl port-forward -n dev svc/wil-playground 8888:8888 \
      >>/tmp/iot_pf_app.log 2>&1 || true

    sleep 2
  done
) &
echo $! >> "$PIDS_FILE"


echo "  Verifying app on :8888 is reachable..."
WAIT=0
until curl -s --max-time 2 --output /dev/null --write-out "%{http_code}" \
      http://localhost:8888 2>/dev/null | grep -qE "^[0-9]{3}"; do
  sleep 3; WAIT=$((WAIT + 3))
  if [ "$WAIT" -ge 30 ]; then
    echo "  WARNING: app on :8888 not responding — check: cat /tmp/iot_pf_app.log"
    break
  fi
done


ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo)

APP_IMAGE=$(kubectl -n dev get deployment wil-playground \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "(syncing)")

echo ""
echo "======================================================================"
echo " Setup complete!"
echo "======================================================================"
echo ""
echo " ArgoCD UI  : https://localhost:8080"
echo " Username   : admin"
echo " Password   : ${ARGOCD_PASS}"
echo ""
echo " App URL    : http://localhost:8888"
echo " App image  : ${APP_IMAGE}"
echo ""
echo "======================================================================"
