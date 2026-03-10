#!/bin/bash
set -euo pipefail

# ── Preparation ───────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Detect Docker Compose path dynamically
DOCKER_COMPOSE_BIN=$(command -v docker-compose || echo "docker compose")

# ── 0. Must run as root ───────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh"
  exit 1
fi

# ── 1. Install dependencies (if missing) ──────────────────
if ! command -v docker &>/dev/null || ! command -v git &>/dev/null; then
  log "Installing required packages..."
  apt-get update -y
  apt-get install -y git docker.io docker-compose ufw openssl python3
else
  log "Packages already present, skipping apt install."
fi

# ── 2. Configure hostname ─────────────────────────────────
log "Setting hostname to 'myserver'..."
hostnamectl set-hostname myserver

# ── 3. Enable & start Docker ──────────────────────────────
log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# ── 4. Configure UFW ──────────────────────────────────────
log "Configuring firewall (UFW)..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ── 5. Locate or clone the repo ───────────────────────────
REPO_URL="https://github.com/Tagamydev/cloud-1"
REPO_DIR="/opt/repo"
# Use absolute paths to avoid CD issues
if [[ -d "$REPO_DIR/.git" ]]; then
  log "Repo already exists at $REPO_DIR — pulling latest..."
  git -C "$REPO_DIR" pull
else
  log "Cloning repo from $REPO_URL..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ── 6. Set up app directory ───────────────────────────────
APP_DIR="/opt/app"
CERTS_DIR="$APP_DIR/certs"
log "Creating app directory structure..."
mkdir -p "$CERTS_DIR"
cp -rf "$REPO_DIR/docker/." "$APP_DIR/"

# ── 7. Generate TLS certificate ───────────────────────────
if [[ ! -f "$CERTS_DIR/cert.pem" ]]; then
  log "Generating self-signed TLS certificate..."
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$CERTS_DIR/key.pem" \
    -out    "$CERTS_DIR/cert.pem" \
    -subj   "/CN=localhost"
fi

# ── 8. Pull images ────────────────────────────────────────
log "Pre-pulling Docker images..."
cd "$APP_DIR"
$DOCKER_COMPOSE_BIN pull

# ── 9. Install systemd service ────────────────────────────
log "Installing wordpress-stack systemd service..."
cat > /etc/systemd/system/wordpress-stack.service << SERVICE
[Unit]
Description=WordPress Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=$DOCKER_COMPOSE_BIN up -d --remove-orphans
ExecStop=$DOCKER_COMPOSE_BIN down
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable wordpress-stack.service

# ── 10. Start the stack ───────────────────────────────────
log "Starting Docker Compose stack..."
systemctl start wordpress-stack.service
log "Setup Complete."
