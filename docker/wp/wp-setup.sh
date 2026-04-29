#!/bin/bash
# wp-setup.sh — Runs inside the wp-cli container.
# Waits for wp-config.php + MySQL, imports the seed DB, then patches the
# admin credentials using values from .env so no secrets live in the dump.

set -euo pipefail

log() { echo "[wp-setup $(date '+%H:%M:%S')] $*"; }

MAX_TRIES=60

# ── 1. Wait for wp-config.php ────────────────────────────────────
log "Waiting for wp-config.php..."
for i in $(seq 1 $MAX_TRIES); do
  if [ -f /var/www/html/wp-config.php ]; then
    log "wp-config.php found (attempt $i)."
    break
  fi
  if [ "$i" -eq "$MAX_TRIES" ]; then
    log "ERROR: wp-config.php not found after $MAX_TRIES attempts."
    exit 1
  fi
  sleep 3
done

# ── 2. Wait for MySQL via PHP (avoids MariaDB CLI SSL issues) ────
log "Waiting for MySQL at ${WORDPRESS_DB_HOST:-mysql} (via PHP)..."
for i in $(seq 1 $MAX_TRIES); do
  # Use wp eval to test the DB connection through PHP's mysqli,
  # which doesn't have the MariaDB client SSL problem.
  if wp eval "global \$wpdb; \$wpdb->check_connection();" 2>/dev/null; then
    log "MySQL is ready (attempt $i)."
    break
  fi
  if [ "$i" -eq "$MAX_TRIES" ]; then
    log "ERROR: MySQL not reachable after $MAX_TRIES attempts."
    log "Debug — trying wp eval:"
    wp eval "global \$wpdb; \$wpdb->check_connection();" 2>&1 || true
    log "Debug — trying wp db check:"
    wp db check 2>&1 || true
    exit 1
  fi
  sleep 3
done

# ── 3. Import the seed SQL if the DB is empty ────────────────────
TABLE_COUNT=$(wp eval "
  global \$wpdb;
  \$result = \$wpdb->get_var(\"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DB_NAME\");
  echo \$result;
" 2>/dev/null || echo "0")

log "Found $TABLE_COUNT tables in database."

if [ "$TABLE_COUNT" -lt 2 ]; then
  log "Database looks empty — importing seed SQL..."
  if [ -f /docker-entrypoint-initdb/seed.sql ]; then
    # Try import; pass --skip-ssl in case my.cnf isn't picked up
    if wp db import /docker-entrypoint-initdb/seed.sql 2>/dev/null; then
      log "Seed SQL imported successfully."
    else
      log "First import attempt failed, retrying with explicit --skip-ssl..."
      wp db import /docker-entrypoint-initdb/seed.sql -- --skip-ssl 2>&1
      log "Seed SQL imported successfully (with --skip-ssl)."
    fi
  else
    log "No seed.sql found — running fresh wp core install..."
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

# ── 4. Patch admin credentials from .env ─────────────────────────
log "Updating admin user (ID 1) from environment variables..."

wp user update 1 \
  --user_pass="${WP_ADMIN_PASSWORD}" \
  --display_name="${WP_ADMIN_USER}" \
  --user_email="${WP_ADMIN_EMAIL}" \
  --skip-email

log "Admin credentials updated from .env."

# ── 5. Patch site URL ───────────────────────────────────────────
log "Setting site URL to ${WP_URL}..."
wp option update siteurl "${WP_URL}" 2>/dev/null || true
wp option update home "${WP_URL}" 2>/dev/null || true

# ── 6. Flush ─────────────────────────────────────────────────────
wp rewrite flush --hard 2>/dev/null || true
wp cache flush 2>/dev/null || true

log "=============================="
log "  WordPress setup complete!"
log "  URL:   ${WP_URL}"
log "  Admin: ${WP_ADMIN_USER}"
log "=============================="
