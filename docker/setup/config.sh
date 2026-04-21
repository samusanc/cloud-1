log "Waiting for apt lock to clear..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  log "dpkg locked — waiting..."
  sleep 5
done
apt-get update -y

log "Installing required packages..."
apt-get install -y git docker.io docker-compose ufw openssl python3

log "setting up hostname"
hostnamectl set-hostname myserver

log "Configuring firewall (UFW)..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

