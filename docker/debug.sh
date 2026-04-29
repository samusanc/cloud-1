# 1. Is OPcache actually enabled?
sudo docker compose exec wordpress php -r "echo (function_exists('opcache_get_status') && opcache_get_status()['opcache_enabled']) ? 'OPcache ON' : 'OPcache OFF';"

# 2. Are the WORDPRESS_CONFIG_EXTRA defines being applied?
sudo docker compose exec wordpress php -r "
  require '/var/www/html/wp-config.php';
  echo 'WP_HOME: ' . (defined('WP_HOME') ? WP_HOME : 'NOT SET') . PHP_EOL;
  echo 'DISABLE_WP_CRON: ' . (defined('DISABLE_WP_CRON') ? 'SET' : 'NOT SET') . PHP_EOL;
" 2>/dev/null

# 3. Is WordPress making slow loopback HTTP calls? This is the #1 suspect
sudo docker compose exec wordpress sh -c "
  time wget -q -O /dev/null --timeout=5 https://lanubedelgatoargentino.duckdns.org/ 2>&1 || echo 'failed/timed out'
"

# 4. Time just PHP loading WordPress (isolates PHP vs network)
sudo docker compose exec wordpress php -r "
  \$t = microtime(true);
  \$_SERVER['HTTP_HOST'] = 'localhost';
  \$_SERVER['REQUEST_URI'] = '/';
  require '/var/www/html/wp-load.php';
  echo round((microtime(true)-\$t)*1000) . 'ms to load WordPress' . PHP_EOL;
" 2>/dev/null
