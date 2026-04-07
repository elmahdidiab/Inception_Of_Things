#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(dirname "$SCRIPT_DIR")"


PAT_TOKEN="glpat-iotsetup42bonus00000001"
GITLAB_PASSWORD="Iot42BonuS!xKp9"
GITLAB_HOST_URL="http://localhost:30090"
GITLAB_INTERNAL_URL="http://gitlab.gitlab.svc.cluster.local"
GITLAB_USER="root"
GIT_REPO_NAME="inception-ot"
MANIFESTS_DIR="$BONUS_DIR/manifests"


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   [1/5]  Creating k3d cluster           │"
echo "└─────────────────────────────────────────┘"
bash "$SCRIPT_DIR/install_k3d.sh"


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   [2/5]  Deploying GitLab               │"
echo "└─────────────────────────────────────────┘"

(cd "$BONUS_DIR/confs" && bash "$SCRIPT_DIR/install-gitlap.sh")


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   [3/5]  Bootstrapping GitLab           │"
echo "│          (PAT + project — fast path)     │"
echo "└─────────────────────────────────────────┘"

echo "Waiting for GitLab Rails to be ready..."
until kubectl exec -n gitlab deploy/gitlab -- \
        curl -fsS http://localhost/-/health &>/dev/null; do
  printf '.'
  sleep 15
done
echo ""
echo "GitLab is healthy!"


kubectl port-forward -n gitlab svc/gitlab 30090:80 &>/dev/null &
GITLAB_PF_PID=$!
sleep 2


echo "Creating PAT + project via GitLab web session..."


BOOTSTRAP_SCRIPT=$(mktemp)
cat > "$BOOTSTRAP_SCRIPT" << 'WEBSCRIPT'
#!/bin/bash
set -e
PASSWORD="Iot42BonuS!xKp9"
rm -f /tmp/cookies

echo "[1/4] Getting login CSRF token..."
CSRF=$(curl -sS -c /tmp/cookies http://localhost/users/sign_in \
  | grep "csrf-token" | head -1 | sed 's/.*content="//;s/".*//')
if [ -z "$CSRF" ]; then
  echo "ERROR: Could not extract CSRF from login page"
  exit 1
fi
echo "  CSRF: ${CSRF:0:20}..."

echo "[2/4] Signing in as root..."
curl -sS -b /tmp/cookies -c /tmp/cookies -o /dev/null \
  -X POST http://localhost/users/sign_in \
  --data-urlencode "authenticity_token=$CSRF" \
  --data-urlencode "user[login]=root" \
  --data-urlencode "user[password]=$PASSWORD"

# Follow redirect to get CSRF from the authenticated dashboard
CSRF2=$(curl -sS -L -b /tmp/cookies http://localhost/dashboard/projects \
  | grep "csrf-token" | head -1 | sed 's/.*content="//;s/".*//')
echo "  Session CSRF: ${CSRF2:0:20}..."

echo "[3/4] Creating PAT via API (session auth)..."
PAT_RESP=$(curl -sS -b /tmp/cookies \
  -H "X-CSRF-Token: $CSRF2" \
  -X POST "http://localhost/api/v4/users/1/personal_access_tokens" \
  -d "name=iotsetup-bonus" \
  -d "scopes[]=api" \
  -d "scopes[]=read_repository" \
  -d "scopes[]=write_repository" \
  -d "expires_at=2027-03-06" 2>&1)

TOKEN=$(echo "$PAT_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "  Response: $(echo "$PAT_RESP" | head -c 200)"
  echo "ERROR: PAT creation failed"
  exit 1
fi
echo "  PAT: ${TOKEN:0:20}..."

echo "[4/4] Creating project via API..."
# Retry up to 6 times (60 s) — GitLab API can still be warming up after /-/health
for _attempt in 1 2 3 4 5 6; do
  PROJ_RESP=$(curl -sS \
    -H "PRIVATE-TOKEN: $TOKEN" \
    -X POST "http://localhost/api/v4/projects" \
    -d "name=inception-ot" \
    -d "visibility=private" 2>&1)
  if echo "$PROJ_RESP" | grep -q 'has already been taken'; then
    echo "  Project: already exists (reusing)"
    break
  elif echo "$PROJ_RESP" | grep -q '"full_path"'; then
    echo "  Project: $(echo "$PROJ_RESP" | grep -o '"full_path":"[^"]*"')"
    break
  else
    echo "  API not ready yet (attempt $_attempt/6) — retrying in 10s..."
    sleep 10
  fi
done
if ! echo "$PROJ_RESP" | grep -q 'has already been taken\|full_path'; then
  echo "  Project response: $(echo "$PROJ_RESP" | head -c 200)"
  echo "ERROR: project creation failed after retries"
  exit 1
fi

echo "$TOKEN" > /tmp/pat_token.txt
echo "BOOTSTRAP_DONE"
WEBSCRIPT


GITLAB_POD=$(kubectl get pod -n gitlab -l app=gitlab -o jsonpath='{.items[0].metadata.name}')
kubectl cp "$BOOTSTRAP_SCRIPT" "gitlab/${GITLAB_POD}:/tmp/web_bootstrap.sh"
rm -f "$BOOTSTRAP_SCRIPT"
kubectl exec -n gitlab "$GITLAB_POD" -- bash /tmp/web_bootstrap.sh


PAT_TOKEN=$(kubectl exec -n gitlab "$GITLAB_POD" -- cat /tmp/pat_token.txt 2>/dev/null | tr -d '\n\r')

if [ -z "$PAT_TOKEN" ]; then
  echo "ERROR: Bootstrap failed — no PAT token"
  exit 1
fi
echo "PAT acquired: ${PAT_TOKEN:0:20}..."
GIT_CRED="oauth2:${PAT_TOKEN}"

echo "GitLab bootstrapped!"


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   [4/5]  Pushing manifests to GitLab    │"
echo "└─────────────────────────────────────────┘"


echo "Verifying GitLab port-forward on :30090 ..."
kill "$GITLAB_PF_PID" 2>/dev/null || true
pkill -f "kubectl port-forward.*gitlab.*30090" 2>/dev/null || true
sleep 1
kubectl port-forward -n gitlab svc/gitlab 30090:80 &>/dev/null &
GITLAB_PF_PID=$!
for _pf in $(seq 1 15); do
  if curl -fsS http://localhost:30090/-/health &>/dev/null; then
    echo "Port-forward ready."
    break
  fi
  sleep 2
done
if ! curl -fsS http://localhost:30090/-/health &>/dev/null; then
  echo "ERROR: GitLab port-forward not responding after 30s"
  exit 1
fi

cd "$MANIFESTS_DIR"
if [ ! -d ".git" ]; then
  git init
fi
git add .
git commit -m "Initial commit of manifests" 2>/dev/null || echo "→ Nothing new to commit."
if ! git rev-parse --verify main >/dev/null 2>&1; then
  git branch -M main
fi
git remote remove origin 2>/dev/null || true
git remote add origin "http://${GIT_CRED}@${GITLAB_HOST_URL#http://}/${GITLAB_USER}/${GIT_REPO_NAME}.git"

GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
  git -c credential.helper="" \
  push -u origin HEAD:main --force
echo "Manifests pushed!"
cd "$BONUS_DIR"


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   [5/5]  ArgoCD + GitLab wiring         │"
echo "└─────────────────────────────────────────┘"

GIT_PUSH=false \
GITLAB_URL="$GITLAB_HOST_URL" \
GITLAB_PASSWORD="${PAT_TOKEN:-$GITLAB_PASSWORD}" \
GIT_REPO_NAME="$GIT_REPO_NAME" \
GIT_REPO_PATH="$MANIFESTS_DIR" \
  bash "$SCRIPT_DIR/install_bonus.sh"

echo "Patching ArgoCD secret..."

kubectl label secret gitlab-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite
kubectl patch secret gitlab-creds -n argocd \
  --type=merge \
  -p "{\"stringData\":{
        \"type\":\"git\",
        \"username\":\"oauth2\",
        \"password\":\"${PAT_TOKEN}\",
        \"url\":\"${GITLAB_INTERNAL_URL}/${GITLAB_USER}/${GIT_REPO_NAME}.git\"
      }}"
echo "ArgoCD secret patched."


kubectl rollout restart deploy/argocd-repo-server -n argocd
kubectl rollout status deploy/argocd-repo-server -n argocd --timeout=60s


echo ""
echo "┌─────────────────────────────────────────┐"
echo "│   Port-forwards                         │"
echo "└─────────────────────────────────────────┘"


pkill -f "kubectl port-forward.*argocd-server.*8080" 2>/dev/null || true
pkill -f "kubectl port-forward.*8888" 2>/dev/null || true

kill "$GITLAB_PF_PID" 2>/dev/null || true
pkill -f "kubectl port-forward.*gitlab.*30090" 2>/dev/null || true
kubectl port-forward -n gitlab svc/gitlab 30090:80 &>/dev/null &
disown $!

kubectl port-forward -n argocd svc/argocd-server 8080:443 &>/dev/null &
disown $!

( while true; do
    kubectl port-forward -n dev svc/wil-playground 8888:8888 2>/dev/null
    sleep 2
  done ) &>/dev/null &
disown $!

echo "→ ArgoCD UI forwarded      ➜  https://localhost:8080"
echo "→ GitLab UI forwarded      ➜  http://localhost:30090"
echo "→ wil-playground forwarded ➜  http://localhost:8888"

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

echo ""
echo "╔═════════════════════════════════════════╗"
echo "║              !ALL DONE!                 ║"
echo "╠═════════════════════════════════════════╣"
echo "║                                         ║"
echo "║  GitLab  ➜  http://localhost:30090      ║"
echo "║    user: root                           ║"
printf  "║    pass: %-31s║\n" "$GITLAB_PASSWORD"
echo "║                                         ║"
echo "║  ArgoCD  ➜  https://localhost:8080      ║"
echo "║    user: admin                          ║"
printf  "║    pass: %-31s║\n" "$ARGOCD_PASS"
echo "║                                         ║"
printf  "║  PAT  : %-32s║\n" "${PAT_TOKEN:-N/A}"
echo "║                                         ║"
echo "║  App    ➜  http://localhost:8888         ║"
echo "║                                         ║"
echo "╚═════════════════════════════════════════╝"
