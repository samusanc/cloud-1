#!/bin/bash

APP_DIR="/opt/app"
CERTS_DIR="$APP_DIR/certs"
DB_DIR="$APP_DIR/db"

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

# ── 7. Set up app directory ──────────────────
log "Creating app directory structure..."
mkdir -p "$CERTS_DIR"
cp -rf "$REPO_DIR/docker/." "$APP_DIR/"

# ── 7b. Place SQL seed file ──────────────────
log "Copying SQL seed file..."
mkdir -p "$DB_DIR"
cp "$REPO_DIR/sql.qsl" "$DB_DIR/seed.sql"

# ── 7c. Restore wp-content from saved word/ directory ──
log "Restoring wp-content from saved files..."
mkdir -p "$APP_DIR/wp-content"
cp -rf "$REPO_DIR/word/wp-content/." "$APP_DIR/wp-content/"
# www-data uid 33 — matches wordpress:fpm
chown -R 33:33 "$APP_DIR/wp-content"

./setup/certificates.sh

log "Starting Docker Compose stack..."
cd "$APP_DIR"
docker-compose down || true
docker-compose up -d

log ""
log "   → HTTP  : http://localhost"
log "   → HTTPS : https://localhost"
log "   → phpMyAdmin: https://localhost/phpmyadmin/"
