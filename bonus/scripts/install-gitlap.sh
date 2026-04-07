#!/bin/bash
set -euo pipefail


echo "Creating namespace 'gitlab'..."
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -


echo "Applying GitLab Deployment..."
kubectl apply -n gitlab -f gitlab-deployment.yaml

echo "Applying GitLab Service..."
kubectl apply -n gitlab -f gitlab-service.yaml

echo "Waiting for GitLab Deployment to be ready..."
kubectl rollout status deployment/gitlab -n gitlab --timeout=600s

echo "GitLab is deployed in namespace gitlab!"
echo "You can access it inside the cluster at: http://gitlab.gitlab.svc.cluster.local"