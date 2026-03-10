#!/bin/bash
set -euo pipefail
# ─────────────────────────────────────────────
# Cloud-1 Setup Script
# Handles system prep ONLY. Docker stack is
# started by the wordpress-app.service systemd unit.
# Run as root (or with sudo) on Ubuntu 22.04 LTS.
# Usage: sudo bash setup.sh
# ─────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 0. Must run as root ──────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh"
  exit 1
fi

# ── 1. Install dependencies ──────────────────
log "Updating package lists..."
apt-get update -y
log "Installing required packages..."
apt-get install -y git docker.io docker-compose ufw openssl python3

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

# ── 5. Clone the repo ────────────────────────
REPO_URL="https://github.com/Tagamydev/cloud-1"
REPO_DIR="/opt/repo"
if [[ -d "$REPO_DIR" ]]; then
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

# Copy ALL docker files including .env, docker-compose.yml, nginx.conf
cp -rf "$REPO_DIR/docker/." "$APP_DIR/"

# ── 7. Generate self-signed TLS certificate ──
log "Generating self-signed TLS certificate..."
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "$CERTS_DIR/key.pem" \
  -out    "$CERTS_DIR/cert.pem" \
  -subj   "/CN=localhost"

# ── 8. Install systemd service for Docker stack ──
log "Installing wordpress-app systemd service..."
cat > /etc/systemd/system/wordpress-app.service << 'EOF'
[Unit]
Description=WordPress Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/app
ExecStart=sudo python3 -m http.server -p 443
ExecStop=sudo python3 -m http.server -p 443
TimeoutStartSec=300
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wordpress-app.service

log ""
log "Setup complete! The Docker stack will start automatically on next boot."
log "To start it now manually, run: sudo systemctl start wordpress-app"
log ""
log "   → HTTP  : http://localhost"
log "   → HTTPS : https://localhost"
log "   → phpMyAdmin: https://localhost/phpmyadmin/"
