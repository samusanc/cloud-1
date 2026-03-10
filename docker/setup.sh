#!/bin/bash
set -euo pipefail
# ─────────────────────────────────────────────
# Cloud-1 Setup Script
# Equivalent to cloud-init runcmd section.
# Run as root (or with sudo) on Ubuntu 20.04 LTS.
# Usage: sudo bash setup.sh
# ─────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 0. Must run as root ──────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh"
  exit 1
fi

# ── 1. Fix MTU (VirtualBox NAT drops large packets) ──
log "Fixing MTU on virtual NIC..."
IFACE=$(ip route | grep default | awk '{print $5}')
ip link set "$IFACE" mtu 1450
log "MTU set to 1450 on $IFACE"

# ── 2. Install dependencies ──────────────────
log "Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  log "dpkg locked — waiting..."
  sleep 5
done

log "Updating package lists..."
apt-get update -y
log "Installing required packages..."
apt-get install -y git docker.io docker-compose ufw openssl python3

# ── 3. Configure hostname ────────────────────
log "Setting hostname to 'myserver'..."
hostnamectl set-hostname myserver

# ── 4. Enable & start Docker ─────────────────
log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# ── 5. Configure UFW firewall ────────────────
log "Configuring firewall (UFW)..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# ── 6. Clone the repo ────────────────────────
REPO_URL="https://github.com/Tagamydev/cloud-1"
REPO_DIR="/opt/repo"
if [[ -d "$REPO_DIR" ]]; then
  log "Repo already exists at $REPO_DIR — pulling latest..."
  git -C "$REPO_DIR" pull
else
  log "Cloning repo from $REPO_URL..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ── 7. Set up app directory ──────────────────
APP_DIR="/opt/app"
CERTS_DIR="$APP_DIR/certs"
log "Creating app directory structure..."
mkdir -p "$CERTS_DIR"
cp -rf "$REPO_DIR/docker/." "$APP_DIR/"

# ── 8. Generate self-signed TLS certificate ──
log "Generating self-signed TLS certificate..."
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "$CERTS_DIR/key.pem" \
  -out    "$CERTS_DIR/cert.pem" \
  -subj   "/CN=localhost"

# ── 9. Start Docker Compose ──────────────────
log "Starting Docker Compose stack..."
cd "$APP_DIR"
/usr/bin/docker-compose up -d

log ""
log "   → HTTP  : http://localhost"
log "   → HTTPS : https://localhost"
log "   → phpMyAdmin: https://localhost/phpmyadmin/"
