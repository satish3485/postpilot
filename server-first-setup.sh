#!/usr/bin/env bash
# One-time bootstrap on the Hetzner VPS (run via SSH as the deploy user, before the first GitHub Action).
#
# Usage:
#   ./scripts/server-first-setup.sh https://github.com/YOUR_ORG/YOUR_REPO.git
#
# Private repo: use SSH URL and add a deploy key to GitHub first:
#   ./scripts/server-first-setup.sh git@github.com:YOUR_ORG/YOUR_REPO.git

set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-/opt/postpilot}"
REPO_URL="${1:-${REPO_URL:-}}"

if [[ -z "$REPO_URL" ]]; then
  echo "Usage: $0 <git-clone-url>" >&2
  echo "Example: $0 https://github.com/your-org/postpilot.leitbuilt.com.git" >&2
  exit 1
fi

if [[ -d "$DEPLOY_PATH/.git" ]]; then
  echo "Repo already exists at $DEPLOY_PATH — skip clone. Edit .env and run: docker compose up -d --build"
  exit 0
fi

if [[ ! -d "$DEPLOY_PATH" ]]; then
  if [[ -w /opt ]] || [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "$DEPLOY_PATH"
    if [[ "$(id -u)" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
      chown "$SUDO_USER:$SUDO_USER" "$DEPLOY_PATH"
    fi
  else
    echo "Creating $DEPLOY_PATH (may ask for sudo password)…"
    sudo mkdir -p "$DEPLOY_PATH"
    sudo chown "$USER:$USER" "$DEPLOY_PATH"
  fi
fi

echo "Cloning $REPO_URL → $DEPLOY_PATH"
git clone "$REPO_URL" "$DEPLOY_PATH"

cd "$DEPLOY_PATH"
cp -n .env.example .env 2>/dev/null || cp .env.example .env
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x scripts/lib/*.sh 2>/dev/null || true

cat <<EOF

First-time setup done.

1. Edit secrets on the server:
     nano $DEPLOY_PATH/.env
   (POSTGRES_PASSWORD, NEXT_PUBLIC_APP_URL, TOKEN_ENCRYPTION_KEY, SESSION_SECRET, OAuth, …)

2. Start PostPilot:
     cd $DEPLOY_PATH && docker compose up -d --build

3. Push to main (or run "Deploy to Hetzner" workflow) for future deploys.

EOF
