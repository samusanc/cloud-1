#!/bin/bash
set -euo pipefail
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# root check!
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh"
  exit 1
fi

# ── 1. Fix MTU (VirtualBox NAT drops large packets) ──
#log "Fixing MTU on virtual NIC..."
#IFACE=$(ip route | grep default | awk '{print $5}')
#ip link set "$IFACE" mtu 1450
#log "MTU set to 1450 on $IFACE"

./setup/config.sh

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

# ── 7b. Place SQL seed file ──────────────────
log "Copying SQL seed file..."
DB_DIR="$APP_DIR/db"
mkdir -p "$DB_DIR"
# NOTE: sql.qsl is intentionally misspelled in the repo — copy as seed.sql
cp "$REPO_DIR/sql.qsl" "$DB_DIR/seed.sql"

# ── 7c. Restore wp-content from saved word/ directory ──
log "Restoring wp-content from saved files..."
mkdir -p "$APP_DIR/wp-content"
cp -rf "$REPO_DIR/word/wp-content/." "$APP_DIR/wp-content/"
# www-data uid 33 — matches wordpress:fpm
chown -R 33:33 "$APP_DIR/wp-content"

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
# Bring down any previous run first (idempotency)
docker-compose down || true
docker-compose up -d

log ""
log "   → HTTP  : http://localhost"
log "   → HTTPS : https://localhost"
log "   → phpMyAdmin: https://localhost/phpmyadmin/"
