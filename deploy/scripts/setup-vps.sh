#!/usr/bin/env bash
# =============================================================================
# Daxelo-Kinrel — Oracle Cloud VPS Initial Setup Script
# =============================================================================
# Run this ONCE on a fresh Oracle Cloud Free Tier VPS (Ubuntu/Oracle Linux)
# to install Docker, configure firewall, and prepare the deployment directory.
#
# Usage:
#   chmod +x deploy/scripts/setup-vps.sh
#   sudo ./deploy/scripts/setup-vps.sh
#
# What it does:
#   1. System update & essential packages
#   2. Docker Engine + Docker Compose v2
#   3. UFW firewall (80, 443, 22)
#   4. Swap file (2GB — Oracle Free Tier has 1GB RAM)
#   5. Deployment directory structure at /opt/kinrel
#   6. Nginx SSL directory with self-signed cert for Cloudflare Origin Pull
#   7. Download Cloudflare Origin Pull CA certificate
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root. Use: sudo $0"
fi

DEPLOY_DIR="/opt/kinrel"

log "Starting VPS setup for Daxelo-Kinrel..."
log "Deploy directory: ${DEPLOY_DIR}"

# ── 1. System update & essential packages ──────────────────────────────────
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  curl wget git unzip \
  ufw htop nano \
  ca-certificates gnupg lsb-release \
  software-properties-common

# ── 2. Install Docker Engine + Compose v2 ─────────────────────────────────
if ! command -v docker &>/dev/null; then
  log "Installing Docker Engine..."
  
  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Start Docker
  systemctl enable docker
  systemctl start docker

  log "Docker installed successfully!"
else
  warn "Docker is already installed, skipping..."
fi

# Verify Docker Compose v2
docker compose version || err "Docker Compose v2 not found!"

# ── 3. Configure UFW Firewall ─────────────────────────────────────────────
log "Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp
# HTTP (Cloudflare → Nginx)
ufw allow 80/tcp
# HTTPS (Cloudflare → Nginx)
ufw allow 443/tcp

ufw --force enable
ufw status verbose

log "Firewall configured: 22, 80, 443 allowed"

# ── 4. Create swap file (2GB) ─────────────────────────────────────────────
if [[ ! -f /swapfile ]]; then
  log "Creating 2GB swap file (Oracle Free Tier has limited RAM)..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  
  # Make swap persistent across reboots
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
  
  # Optimize swappiness for server
  sysctl vm.swappiness=10
  if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
  fi
  
  log "Swap file created and activated!"
else
  warn "Swap file already exists, skipping..."
fi

# ── 5. Create deployment directory ────────────────────────────────────────
log "Creating deployment directory at ${DEPLOY_DIR}..."
mkdir -p "${DEPLOY_DIR}"/{nginx/ssl,scripts,logs,backups}
mkdir -p "${DEPLOY_DIR}"/nginx/conf.d

log "Directory structure created!"

# ── 6. Generate self-signed SSL certificate ────────────────────────────────
# This is used for Cloudflare Origin Pull (Cloudflare validates its own cert,
# so the origin cert can be self-signed)
SSL_DIR="${DEPLOY_DIR}/nginx/ssl"

if [[ ! -f "${SSL_DIR}/cert.pem" ]]; then
  log "Generating self-signed SSL certificate for Cloudflare Origin Pull..."
  openssl req -x509 -nodes \
    -days 3650 \
    -newkey rsa:2048 \
    -keyout "${SSL_DIR}/key.pem" \
    -out "${SSL_DIR}/cert.pem" \
    -subj "/C=IN/ST=Karnataka/L=Bangalore/O=Daxelo/CN=api.kinrel.app"
  
  chmod 600 "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  
  log "SSL certificate generated at ${SSL_DIR}/"
else
  warn "SSL certificate already exists, skipping..."
fi

# ── 7. Download Cloudflare Origin Pull CA certificate ──────────────────────
CF_CA="${SSL_DIR}/cloudflare-origin-pull.pem"
if [[ ! -f "${CF_CA}" ]]; then
  log "Downloading Cloudflare Origin Pull CA certificate..."
  curl -fsSL \
    "https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem" \
    -o "${CF_CA}"
  
  if [[ -s "${CF_CA}" ]]; then
    log "Cloudflare Origin Pull CA downloaded!"
  else
    warn "Failed to download Cloudflare CA. You can manually download from:"
    warn "  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem"
    rm -f "${CF_CA}"
  fi
else
  warn "Cloudflare Origin Pull CA already exists, skipping..."
fi

# ── 8. Configure kernel parameters ────────────────────────────────────────
log "Optimizing kernel parameters for production..."
cat > /etc/sysctl.d/99-kinrel.conf << 'EOF'
# Increase max file descriptors
fs.file-max = 65535

# Optimize TCP
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# Enable TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Reduce swap tendency
vm.swappiness = 10
EOF

sysctl --system 2>/dev/null || true

# ── 9. Increase file descriptor limits ─────────────────────────────────────
if ! grep -q 'kinrel' /etc/security/limits.conf; then
  cat >> /etc/security/limits.conf << 'EOF'
# Kinrel deployment limits
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
fi

# ── Done! ──────────────────────────────────────────────────────────────────
log "============================================"
log "VPS setup complete!"
log "============================================"
log ""
log "Next steps:"
log "  1. Copy your project to the VPS:"
log "     git clone https://github.com/buildwith-manish/Daxelo-Kinrel.git ${DEPLOY_DIR}/repo"
log ""
log "  2. Create .env.production from the template:"
log "     cp ${DEPLOY_DIR}/repo/deploy/.env.production.template ${DEPLOY_DIR}/.env.production"
log "     nano ${DEPLOY_DIR}/.env.production"
log ""
log "  3. Run the deploy script:"
log "     cd ${DEPLOY_DIR}/repo && sudo ./deploy/scripts/deploy.sh"
log ""
log "  4. Configure Cloudflare DNS to point to this VPS IP"
log ""
log "VPS IP addresses:"
hostname -I | tr ' ' '\n' | while read ip; do
  log "  - ${ip}"
done
