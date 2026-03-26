#!/bin/bash
# Wait for MySQL to be ready
until wp db check --allow-root 2>/dev/null; do
  echo "Waiting for DB..."; sleep 3
done

# Import the seed
wp db import /docker-entrypoint-initdb/seed.sql --allow-root

# Optionally update the site URL if it changed
wp option update siteurl "$WP_URL" --allow-root
wp option update home "$WP_URL" --allow-root

wp cache flush --allow-root
