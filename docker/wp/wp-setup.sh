#!/bin/bash
# wp-setup.sh — Runs inside the wp-cli container.
# Uses raw PHP for MySQL connectivity and SQL import to avoid
# MariaDB CLI SSL issues entirely.

set -euo pipefail

log() { echo "[wp-setup $(date '+%H:%M:%S')] $*"; }

DB_HOST="${WORDPRESS_DB_HOST:-mysql}"
DB_USER="${WORDPRESS_DB_USER}"
DB_PASS="${WORDPRESS_DB_PASSWORD}"
DB_NAME="${WORDPRESS_DB_NAME}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD}"
MAX_TRIES=60
SEED_FILE="/docker-entrypoint-initdb/seed.sql"

# ── 1. Wait for wp-config.php ────────────────────────────────────
log "Waiting for wp-config.php..."
for i in $(seq 1 $MAX_TRIES); do
  [ -f /var/www/html/wp-config.php ] && { log "wp-config.php found (attempt $i)."; break; }
  [ "$i" -eq "$MAX_TRIES" ] && { log "ERROR: wp-config.php not found."; exit 1; }
  sleep 3
done

# ── 2. Wait for MySQL via raw PHP ────────────────────────────────
log "Waiting for MySQL at $DB_HOST..."
for i in $(seq 1 $MAX_TRIES); do
  RESULT=$(php -r "
    \$c = @new mysqli('$DB_HOST', 'root', '$DB_ROOT_PASS', '$DB_NAME');
    if (\$c->connect_error) { exit(1); }
    echo 'ok';
  " 2>/dev/null) || true

  if [ "$RESULT" = "ok" ]; then
    log "MySQL is ready (attempt $i)."
    break
  fi
  if [ "$i" -eq "$MAX_TRIES" ]; then
    log "ERROR: MySQL not reachable after $MAX_TRIES attempts."
    php -r "
      \$c = @new mysqli('$DB_HOST', 'root', '$DB_ROOT_PASS', '$DB_NAME');
      echo \$c->connect_error ?? 'no error' ;
    " 2>&1
    exit 1
  fi
  sleep 3
done

# ── 3. Check if DB has tables ────────────────────────────────────
TABLE_COUNT=$(php -r "
  \$c = new mysqli('$DB_HOST', 'root', '$DB_ROOT_PASS', '$DB_NAME');
  \$r = \$c->query(\"SELECT COUNT(*) AS cnt FROM information_schema.tables WHERE table_schema = '$DB_NAME'\");
  echo \$r->fetch_assoc()['cnt'];
" 2>/dev/null || echo "0")

log "Found $TABLE_COUNT tables in '$DB_NAME'."

# ── 4. Import seed SQL if DB is empty ────────────────────────────
if [ "$TABLE_COUNT" -lt 2 ]; then
  if [ -f "$SEED_FILE" ]; then
    log "Cleaning SQL dump (stripping SUPER-privilege statements)..."
    # Strip statements that require SUPER/SESSION_VARIABLES_ADMIN
    CLEAN_SQL="/tmp/seed_clean.sql"
    sed -E \
      -e '/^SET @@SESSION\.SQL_LOG_BIN/d' \
      -e '/^SET @@GLOBAL\./d' \
      -e '/^SET @@session\./d' \
      -e '/MYSQLDUMP_TEMP_LOG_BIN/d' \
      "$SEED_FILE" > "$CLEAN_SQL"

    log "Importing seed SQL as root via PHP..."
    php -r "
      mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
      \$c = new mysqli('$DB_HOST', 'root', '$DB_ROOT_PASS', '$DB_NAME');
      \$c->set_charset('utf8mb4');
      \$sql = file_get_contents('$CLEAN_SQL');
      if (!\$c->multi_query(\$sql)) {
        fwrite(STDERR, 'Import failed: ' . \$c->error . PHP_EOL);
        exit(1);
      }
      // Drain all result sets
      do {
        if (\$result = \$c->store_result()) { \$result->free(); }
      } while (\$c->more_results() && \$c->next_result());

      if (\$c->errno) {
        fwrite(STDERR, 'Error during import: ' . \$c->error . PHP_EOL);
        exit(1);
      }
      echo 'done';
    "
    log "Seed SQL imported successfully."
    rm -f "$CLEAN_SQL"
  else
    log "No seed.sql — running fresh wp core install..."
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
  log "Database already populated — skipping import."
fi

# ── 5. Patch admin credentials from .env ─────────────────────────
log "Updating admin user (ID 1) from environment variables..."

wp user update 1 \
  --user_pass="${WP_ADMIN_PASSWORD}" \
  --display_name="${WP_ADMIN_USER}" \
  --user_email="${WP_ADMIN_EMAIL}" \
  --skip-email

log "Admin credentials updated from .env."

# ── 6. Patch site URL ───────────────────────────────────────────
log "Setting site URL to ${WP_URL}..."
wp option update siteurl "${WP_URL}"
wp option update home "${WP_URL}"

# ── 7. Flush ─────────────────────────────────────────────────────
wp rewrite flush --hard 2>/dev/null || true
wp cache flush 2>/dev/null || true

log "=============================="
log "  WordPress setup complete!"
log "  URL:   ${WP_URL}"
log "  Admin: ${WP_ADMIN_USER}"
log "=============================="
