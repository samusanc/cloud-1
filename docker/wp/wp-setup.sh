#!/bin/bash
# wp-setup.sh — Runs inside the wp-cli container.
# Waits for MySQL + WordPress, imports the seed DB, then patches the
# admin credentials using values from .env so no secrets live in the dump.

set -euo pipefail

log() { echo "[wp-setup $(date '+%H:%M:%S')] $*"; }

# ── 1. Wait for MySQL to actually accept queries ──────────────────
log "Waiting for MySQL at ${WORDPRESS_DB_HOST}..."
MAX_TRIES=60
for i in $(seq 1 $MAX_TRIES); do
  if wp db check --quiet 2>/dev/null; then
    log "MySQL is ready (attempt $i)."
    break
  fi
  if [ "$i" -eq "$MAX_TRIES" ]; then
    log "ERROR: MySQL not reachable after $MAX_TRIES attempts."
    exit 1
  fi
  sleep 3
done

# ── 2. Import the seed SQL if the DB is empty ─────────────────────
TABLE_COUNT=$(wp db query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${WORDPRESS_DB_NAME}';" --skip-column-names 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -lt 2 ]; then
  log "Database looks empty — importing seed SQL..."
  if [ -f /docker-entrypoint-initdb/seed.sql ]; then
    wp db import /docker-entrypoint-initdb/seed.sql
    log "Seed SQL imported successfully."
  else
    log "WARNING: No seed.sql found, running wp core install instead..."
    wp core install \
      --url="${WP_URL}" \
      --title="${WP_TITLE}" \
      --admin_user="${WP_ADMIN_USER}" \
      --admin_password="${WP_ADMIN_PASSWORD}" \
      --admin_email="${WP_ADMIN_EMAIL}" \
      --skip-email
    log "Fresh WordPress installed."
    exit 0
  fi
else
  log "Database already has $TABLE_COUNT tables — skipping import."
fi

# ── 3. Wait for WordPress files to be ready ───────────────────────
log "Waiting for wp-config.php..."
for i in $(seq 1 30); do
  [ -f /var/www/html/wp-config.php ] && break
  sleep 2
done
if [ ! -f /var/www/html/wp-config.php ]; then
  log "ERROR: wp-config.php not found."
  exit 1
fi

# ── 4. Patch admin credentials from .env ──────────────────────────
# This replaces whatever was in the SQL dump with the .env values.
log "Updating admin user (ID 1) from environment variables..."

# Update username
wp user update 1 \
  --user_login="${WP_ADMIN_USER}" \
  --user_nicename="${WP_ADMIN_USER}" \
  --display_name="${WP_ADMIN_USER}" \
  --skip-email 2>/dev/null || true

# Update password (wp-cli hashes it properly with phpass)
wp user update 1 \
  --user_pass="${WP_ADMIN_PASSWORD}" \
  --skip-email

# Update email
wp user update 1 \
  --user_email="${WP_ADMIN_EMAIL}" \
  --skip-email

log "Admin credentials updated from .env."

# ── 5. Patch site URL ────────────────────────────────────────────
log "Setting site URL to ${WP_URL}..."
wp option update siteurl "${WP_URL}"
wp option update home "${WP_URL}"

# ── 6. Flush rewrite rules and cache ─────────────────────────────
wp rewrite flush --hard 2>/dev/null || true
wp cache flush 2>/dev/null || true

log "=============================="
log "  WordPress setup complete!"
log "  URL:   ${WP_URL}"
log "  Admin: ${WP_ADMIN_USER}"
log "=============================="
