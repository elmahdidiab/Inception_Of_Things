#!/bin/bash
set -euo pipefail


GITLAB_URL="${GITLAB_URL:-http://gitlab.gitlab.svc.cluster.local}"
GITLAB_USER="${GITLAB_USER:-root}"
GITLAB_PASSWORD="${GITLAB_PASSWORD:-5iveL!fe}"
GIT_REPO_NAME="${GIT_REPO_NAME:-42-aatki-inception-ot}"
GIT_REPO_PATH="${GIT_REPO_PATH:-manifests}"
GIT_PUSH="${GIT_PUSH:-true}"

GITLAB_PROJECT_URL="$GITLAB_URL/$GITLAB_USER/$GIT_REPO_NAME.git"

echo "Installing ArgoCD in namespace argocd..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD server to be ready..."
kubectl wait -n argocd --for=condition=available deployment/argocd-server --timeout=300s

kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

if [ "$GIT_PUSH" = "true" ]; then
    echo "Pushing manifests to GitLab..."

    if [ ! -d "$GIT_REPO_PATH/.git" ]; then
        git init "$GIT_REPO_PATH"
    fi

    cd "$GIT_REPO_PATH"

    git add .
    git commit -m "Initial commit of manifests" || echo "No changes to commit"

    if ! git rev-parse --verify main >/dev/null 2>&1; then
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            git branch -M main
        else
            git commit --allow-empty -m "Initial commit" || true
            git branch -M main
        fi
    fi

    git remote remove origin 2>/dev/null || true
    git remote add origin "http://$GITLAB_USER:$GITLAB_PASSWORD@${GITLAB_URL#http://}/$GITLAB_USER/$GIT_REPO_NAME.git"

    curl -s --fail -X POST "$GITLAB_URL/api/v4/projects" \
         -u "$GITLAB_USER:$GITLAB_PASSWORD" \
         -d "name=$GIT_REPO_NAME" || echo "Project may already exist"

    git push -u origin main --force || {
        echo "Initial push failed; attempting to push current HEAD to origin/main"
        git push -u origin HEAD:main --force
    }
    cd -
    echo "Manifests pushed to GitLab."
fi

echo "Creating GitLab credentials secret for ArgoCD..."

echo "Creating project deploy token for ArgoCD access..."
DEPLOY_RESP=$(curl -s -X POST "$GITLAB_URL/api/v4/projects/$GITLAB_USER%2F$GIT_REPO_NAME/deploy_tokens" \
    -u "$GITLAB_USER:$GITLAB_PASSWORD" \
    -d "name=argocd-token-$(date +%s)" \
    -d "scopes[]=read_repository" ) || true

DT_USERNAME=$(echo "$DEPLOY_RESP" | grep -o '"username":"[^"]*"' | sed -E 's/"username":"([^"]+)"/\1/' || true)
DT_TOKEN=$(echo "$DEPLOY_RESP" | grep -o '"token":"[^"]*"' | sed -E 's/"token":"([^"]+)"/\1/' || true)

if [ -n "$DT_TOKEN" ] && [ -n "$DT_USERNAME" ]; then
    echo "Deploy token created for ArgoCD."
    CRED_USER="$DT_USERNAME"
    CRED_PASS="$DT_TOKEN"
else
    echo "Could not create deploy token."
    CRED_USER="$GITLAB_USER"
    CRED_PASS="$GITLAB_PASSWORD"
fi

kubectl create secret generic gitlab-creds \
    -n argocd \
    --from-literal=username="$CRED_USER" \
    --from-literal=password="$CRED_PASS" \
    --from-literal=url="$GITLAB_PROJECT_URL" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl annotate secret gitlab-creds \
    -n argocd \
    argocd.argoproj.io/secret-type=repo-creds --overwrite

echo "GitLab credentials added to ArgoCD."

echo "Creating ArgoCD Application (wil-playground)..."
kubectl apply -f manifests/application.yaml
echo "ArgoCD Application created and linked to GitLab."

echo ""
echo "ArgoCD fully installed and configured!"
echo ""
echo "ArgoCD UI:"
echo "kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "Then open: https://localhost:8080"
echo ""
echo "Default login:"
echo "Username: admin"
echo "Password:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""