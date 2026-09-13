#!/usr/bin/env bash
# First-time Hetzner VPS bootstrap (Ubuntu 22.04/24.04).
# Run as root:  sudo bash scripts/hetzner-setup.sh
#
# Same VPC as another app (e.g. PriceWatcher): Docker, deploy user, and UFW may already
# exist — re-running this script is safe; it still ensures /opt/postpilot is ready.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (sudo bash scripts/hetzner-setup.sh)" >&2
  exit 1
fi

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/postpilot}"
SSH_PORT="${SSH_PORT:-22}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing packages"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release rsync ufw git

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker Engine"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "==> Creating deploy user: $DEPLOY_USER"
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi

usermod -aG docker "$DEPLOY_USER"

echo "==> Preparing $DEPLOY_PATH"
mkdir -p "$DEPLOY_PATH"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_PATH"

install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
AUTH_KEYS="/home/$DEPLOY_USER/.ssh/authorized_keys"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown "$DEPLOY_USER:$DEPLOY_USER" "$AUTH_KEYS"

if [[ -n "${DEPLOY_PUBKEY:-}" ]] && ! grep -qxF "$DEPLOY_PUBKEY" "$AUTH_KEYS"; then
  echo "$DEPLOY_PUBKEY" >> "$AUTH_KEYS"
  echo "==> Added DEPLOY_PUBKEY to $AUTH_KEYS"
fi

echo "==> Configuring UFW (SSH/${SSH_PORT}, HTTP, HTTPS)"
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw allow 443/udp comment "HTTP/3"
ufw --force enable

GITHUB_DEPLOY_KEY="/home/$DEPLOY_USER/.ssh/postpilot_github"
if [[ ! -f "$GITHUB_DEPLOY_KEY" ]]; then
  echo "==> Creating GitHub deploy key for $DEPLOY_USER (private repo git pull)"
  sudo -u "$DEPLOY_USER" ssh-keygen -t ed25519 -C "postpilot-vps" -f "$GITHUB_DEPLOY_KEY" -N ""
fi

SSH_CONFIG="/home/$DEPLOY_USER/.ssh/config"
GITHUB_SSH_HOST="${GITHUB_SSH_HOST:-github.com-postpilot}"
if ! sudo -u "$DEPLOY_USER" grep -q "Host ${GITHUB_SSH_HOST}" "$SSH_CONFIG" 2>/dev/null; then
  echo "==> Configuring SSH host alias ${GITHUB_SSH_HOST} (avoids clobbering other apps' github.com config)"
  sudo -u "$DEPLOY_USER" bash -c "cat >> \"$SSH_CONFIG\" <<EOF
Host ${GITHUB_SSH_HOST}
  HostName github.com
  User git
  IdentityFile ~/.ssh/postpilot_github
  IdentitiesOnly yes
EOF"
  chmod 600 "$SSH_CONFIG"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$SSH_CONFIG"
fi

echo
echo "Hetzner VPS is ready for PostPilot."
echo
echo "Next steps:"
echo "  1. Add the GitHub deploy key (repo → Settings → Deploy keys, read-only):"
echo "       sudo cat ${GITHUB_DEPLOY_KEY}.pub"
echo "  2. Test GitHub auth, then clone (use host alias ${GITHUB_SSH_HOST}, not github.com):"
echo "       sudo -u ${DEPLOY_USER} ssh -T git@${GITHUB_SSH_HOST}"
echo "       sudo -u ${DEPLOY_USER} git clone git@${GITHUB_SSH_HOST}:ORG/REPO.git ${DEPLOY_PATH}"
echo "       sudo -u ${DEPLOY_USER} bash -lc 'cd ${DEPLOY_PATH} && cp .env.example .env'"
echo "  3. Copy production .env (from your laptop):"
echo "       scp .env ${DEPLOY_USER}@<server-ip>:${DEPLOY_PATH}/.env"
echo "     Set POSTGRES_PASSWORD, NEXT_PUBLIC_APP_URL, secrets; BIND_HOST=127.0.0.1 if Caddy fronts the app."
echo "  4. First start on the server:"
echo "       sudo -u ${DEPLOY_USER} bash -lc 'cd ${DEPLOY_PATH} && docker compose up -d --build'"
echo "  5. GitHub Actions SSH key (laptop, not the server):"
echo "       ssh-keygen -t ed25519 -f hetzner-deploy -N \"\" -C \"github-actions\""
echo "       ssh-copy-id -i hetzner-deploy.pub ${DEPLOY_USER}@<server-ip>"
echo "     Or re-use the same hetzner-deploy key as your other app on this VPS."
echo "  6. GitHub repo secrets (same as PriceWatcher if shared VPS):"
echo "       HETZNER_HOST, HETZNER_USER=${DEPLOY_USER}, HETZNER_SSH_KEY, HETZNER_SSH_PORT=${SSH_PORT}"
echo "     Deploy path is fixed in the workflow: ${DEPLOY_PATH}"
echo "  7. Push to main — Actions SSHs in, git pull, docker compose build && up -d."
echo
