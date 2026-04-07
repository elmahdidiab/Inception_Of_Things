#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(dirname "$SCRIPT_DIR")"

echo "Cleaning up bonus environment..."


pkill -f "kubectl port-forward.*8080" 2>/dev/null && echo "→ Stopped ArgoCD port-forward." || true
pkill -f "kubectl port-forward.*30090" 2>/dev/null && echo "→ Stopped GitLab port-forward." || true
pkill -f "kubectl port-forward.*8888" 2>/dev/null && echo "→ Stopped wil-playground port-forward." || true


if kubectl cluster-info &>/dev/null 2>&1; then
  # Remove finalizers from all resources in argocd namespace before deleting
  for ns in argocd dev; do
    if kubectl get namespace "$ns" &>/dev/null; then
      echo "→ Cleaning finalizers in $ns namespace..."
      kubectl api-resources --verbs=list --namespaced=true -o name | \
        while read resource; do
          kubectl get "$resource" -n "$ns" -o name 2>/dev/null | \
            while read obj; do
              kubectl patch "$obj" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
        done
      sleep 1
      echo "→ Deleting $ns namespace..."
      kubectl delete namespace "$ns" --grace-period=0 --force 2>/dev/null && echo "  ✓ Deleted." || true
    fi
  done
else
  echo "No cluster reachable."
fi


if [ -d "$BONUS_DIR/manifests/.git" ]; then
  git -C "$BONUS_DIR/manifests" remote remove origin 2>/dev/null && \
    echo "→Removed git remote from manifests/." || true
fi

echo ""
echo "Clean complete!"
