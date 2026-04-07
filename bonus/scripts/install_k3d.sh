#!/bin/bash

set -e

echo "[1/6] Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  echo "→ Homebrew already installed."
fi

echo "[2/6] Installing Docker..."
if ! command -v docker &>/dev/null; then
  brew install --cask docker
  echo "Docker installed."
else
  echo "Docker already installed."
fi

echo "[3/6] Installing k3d..."
if ! command -v k3d &>/dev/null; then
  brew install k3d
  echo "k3d installed."
else
  echo "k3d already installed."
fi

echo "[4/6] Creating k3d cluster..."
if k3d cluster list | grep -q 13-cluster; then
  echo "Cluster 13-cluster already exists."
else
  k3d cluster create 13-cluster \
    --servers 1 \
    --agents 1
  echo "Cluster 13-cluster created."
fi

echo "[5/6] Installing kubectl..."
if ! command -v kubectl &>/dev/null; then
  brew install kubectl
  echo "kubectl installed."
else
  echo "kubectl already installed."
fi

echo "[6/6] Configuring kubectl context..."
mkdir -p ~/.kube
k3d kubeconfig get 13-cluster > ~/.kube/config
kubectl config use-context k3d-13-cluster

echo "kubectl now points to 13-cluster"
echo "Done!"
