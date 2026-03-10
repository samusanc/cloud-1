#!/bin/bash

# Exit on error
set -e

# ── 1. Configuration ───────────────────────────────────────
APP_DIR="/opt/wordpress-app"
REPO_DIR="/opt/repo"
LOG_FILE="/var/log/app_setup.log"
DOCKER_COMPOSE_BIN="docker-compose"

# ── 2. Logging Function ────────────────────────────────────
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting optimized setup process..."

# ── 3. Create Directory Structure ──────────────────────────
log "Creating application directories..."
sudo mkdir -p "$APP_DIR/nginx/conf.d"
sudo mkdir -p "$APP_DIR/nginx/ssl"
sudo mkdir -p "$APP_DIR/wordpress"
sudo mkdir -p "$APP_DIR/mysql_data"

# ── 4. Copy Docker Configs ─────────────────────────────────
log "Copying configuration files from repo..."
sudo cp "$REPO_DIR/docker/docker-compose.yml" "$APP_DIR/"
sudo cp "$REPO_DIR/docker/nginx.conf" "$APP_DIR/nginx/conf.d/default.conf"

# ── 5. Generate SSL (Self-Signed for now) ──────────────────
if [ ! -f "$APP_DIR/nginx/ssl/server.crt" ]; then
    log "Generating self-signed SSL certificate..."
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$APP_DIR/nginx/ssl/server.key" \
        -out "$APP_DIR/nginx/ssl/server.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
fi

# ── 6. Sequential Image Pulling (STALL PREVENTION) ────────
log "Pulling Docker images sequentially to prevent network congestion..."
cd "$APP_DIR"

images=("mysql" "wordpress" "nginx" "phpmyadmin")

for img in "${images[@]}"; do
    log ">>> Pulling image: $img"
    # Retry loop: Try up to 3 times per image
    for i in {1..3}; do
        if sudo $DOCKER_COMPOSE_BIN pull "$img"; then
            log "Successfully pulled $img."
            break
        else
            if [ $i -lt 3 ]; then
                log "Warning: Pull failed for $img. Retrying ($i/3) in 10 seconds..."
                sleep 10
            else
                log "Error: Failed to pull $img after 3 attempts. Check your internet connection."
                exit 1
            fi
        fi
    done
done

# ── 7. Start Containers ────────────────────────────────────
log "Launching containers..."
sudo $DOCKER_COMPOSE_BIN up -d

log "Setup Complete! Your site should be accessible shortly."
