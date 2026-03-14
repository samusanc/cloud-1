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

# ── 10. DuckDNS Dynamic DNS Setup ───────────
log ""
log "─────────────────────────────────────────────"
log "Setting up DuckDNS dynamic DNS..."
log "─────────────────────────────────────────────"

# Check that cron is running
log "Checking cron is running..."
if ! ps -ef | grep cr[o]n | grep -v grep | grep -q .; then
  log "WARNING: cron does not appear to be running."
  log "Please install and start cron for your Linux distribution before continuing."
  log "  e.g. Ubuntu/Debian : apt-get install -y cron && systemctl start cron"
  log "  e.g. Alpine        : apk add dcron && rc-update add dcron"
  log "  e.g. CentOS/RHEL   : yum install -y cronie && systemctl start crond"
  log "Exiting — re-run this script once cron is available."
  exit 1
fi
log "cron is running ✓"

# Check that curl is installed
log "Checking curl is installed..."
if ! command -v curl >/dev/null 2>&1; then
  log "WARNING: curl is not installed."
  log "Please install curl for your Linux distribution before continuing."
  log "  e.g. Ubuntu/Debian : apt-get install -y curl"
  log "  e.g. Alpine        : apk add curl"
  log "  e.g. CentOS/RHEL   : yum install -y curl"
  log "Exiting — re-run this script once curl is available."
  exit 1
fi
log "curl is installed ✓"

# Create DuckDNS directory and script
log "Creating DuckDNS directory and update script..."
DUCK_DIR="$HOME/duckdns"
mkdir -p "$DUCK_DIR"

cat > "$DUCK_DIR/duck.sh" <<'DUCKSCRIPT'
echo url="https://www.duckdns.org/update?domains=lanubedelgatoargentino&token=56d14142-d773-4ca1-b424-32d55110105f&ip=" | curl -k -o ~/duckdns/duck.log -K -
DUCKSCRIPT

chmod 700 "$DUCK_DIR/duck.sh"
log "duck.sh created and made executable ✓"

# Add cron job (every 5 minutes) if not already present
log "Registering DuckDNS cron job (every 5 minutes)..."
CRON_JOB="*/5 * * * * $DUCK_DIR/duck.sh >/dev/null 2>&1"
if crontab -l 2>/dev/null | grep -qF "$DUCK_DIR/duck.sh"; then
  log "Cron job already exists — skipping."
else
  ( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -
  log "Cron job added ✓"
fi

# Run the script once now to test
log "Running duck.sh to test the connection..."
"$DUCK_DIR/duck.sh"

log "Checking DuckDNS response..."
if [[ -f "$DUCK_DIR/duck.log" ]]; then
  DUCK_RESULT=$(cat "$DUCK_DIR/duck.log")
  if [[ "$DUCK_RESULT" == "OK" ]]; then
    log "DuckDNS update: OK ✓"
  else
    log "DuckDNS update: $DUCK_RESULT — check your token/domain and retry."
  fi
else
  log "duck.log not found — something went wrong with the curl request."
fi

log ""
log "DuckDNS setup complete."
log "   → Update log : $DUCK_DIR/duck.log"
log "   → Script     : $DUCK_DIR/duck.sh"
log "   → Cron       : every 5 minutes"
