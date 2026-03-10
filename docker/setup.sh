#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Cloud-1 Setup Script
# Works both ways:
#   1. Called by cloud-init after git clone (bash /opt/repo/docker/setup.sh)
#   2. Run standalone on a fresh machine     (sudo bash setup.sh)
# Usage: sudo bash setup.sh
# ─────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 0. Must run as root ──────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh"
  exit 1
fi

# ── 1. Install dependencies (skip if already done by cloud-init) ─────────────
if ! command -v docker &>/dev/null || ! command -v git &>/dev/null; then
  log "Installing required packages..."
  apt-get update -y
  apt-get install -y git docker.io docker-compose ufw openssl python3
else
  log "Packages already present, skipping apt install."
fi

# ── 2. Configure hostname ────────────────────
log "Setting hostname to 'myserver'..."
hostnamectl set-hostname myserver

# ── 3. Enable & start Docker ─────────────────
log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# ── 4. Configure UFW firewall ────────────────
log "Configuring firewall (UFW)..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# ── 5. Locate or clone the repo ──────────────
REPO_URL="https://github.com/Tagamydev/cloud-1"
REPO_DIR="/opt/repo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFERRED_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$INFERRED_REPO/.git/config" ]]; then
  log "Script is running from inside the repo at $INFERRED_REPO"
  REPO_DIR="$INFERRED_REPO"
elif [[ -d "$REPO_DIR/.git" ]]; then
  log "Repo already exists at $REPO_DIR — pulling latest..."
  git -C "$REPO_DIR" pull
else
  log "Cloning repo from $REPO_URL..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ── 6. Set up app directory ──────────────────
APP_DIR="/opt/app"
CERTS_DIR="$APP_DIR/certs"

log "Creating app directory structure..."
mkdir -p "$CERTS_DIR"
cp -rf "$REPO_DIR/docker/." "$APP_DIR/"

# ── 7. Generate self-signed TLS certificate ──
log "Generating self-signed TLS certificate..."
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "$CERTS_DIR/key.pem" \
  -out    "$CERTS_DIR/cert.pem" \
  -subj   "/CN=localhost"

# ── 8. Pull images now (no timeout risk later) ───────────────────────────────
log "Pre-pulling Docker images (this may take a few minutes)..."
cd "$APP_DIR"
/usr/bin/docker-compose pull

# ── 9. Install systemd service for auto-start on boot ────────────────────────
log "Installing wordpress-stack systemd service..."
cat > /etc/systemd/system/wordpress-stack.service << 'SERVICE'
[Unit]
Description=WordPress Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/app
# Images are pre-pulled, so startup is fast — but infinity avoids any edge case
TimeoutStartSec=infinity
ExecStart=/usr/bin/docker-compose up -d --remove-orphans
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable wordpress-stack.service

# ── 10. Start the stack ──────────────────────
log "Starting Docker Compose stack..."
systemctl start wordpress-stack.service

log ""
log "   → HTTP       : http://localhost"
log "   → HTTPS      : https://localhost"
log "   → phpMyAdmin : https://localhost/phpmyadmin/"
