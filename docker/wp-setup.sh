#!/bin/bash
# ─────────────────────────────────────────────
# wp-setup.sh — runs inside the wp-cli container
# Imports the seed DB and configures WordPress.
# ─────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 1. Wait for MySQL TCP to be ready ────────
log "Waiting for MySQL..."
until wp db check --allow-root --path=/var/www/html 2>/dev/null; do
  sleep 3
done
log "MySQL is up"

# ── 2. Wait for wp-config.php ────────────────
log "Waiting for wp-config.php..."
until [ -f /var/www/html/wp-config.php ]; do
  sleep 3
done
log "wp-config.php found"

# ── 3. Import seed DB (as root to avoid SUPER privilege errors) ──
log "Importing seed.sql..."
# wp db import uses the DB credentials from wp-config.php.
# The dump requires SUPER/SYSTEM_VARIABLES_ADMIN so we pipe via mysql root.
mysql -h"$WORDPRESS_DB_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" \
  "$WORDPRESS_DB_NAME" < /docker-entrypoint-initdb/seed.sql
log "Import complete"

# ── 4. Update site URLs to match current env ─
log "Updating site URLs to $WP_URL..."
wp option update siteurl "$WP_URL" --allow-root --path=/var/www/html
wp option update home    "$WP_URL" --allow-root --path=/var/www/html

# ── 5. Reset admin password to match .env ────
log "Resetting admin password..."
wp user update "$WP_ADMIN_USER" \
  --user_pass="$WP_ADMIN_PASSWORD" \
  --allow-root --path=/var/www/html

wp cache flush --allow-root --path=/var/www/html
log "Done! WordPress is ready."
