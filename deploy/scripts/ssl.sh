#!/usr/bin/env bash
# =============================================================================
# Daxelo-Kinrel — SSL Certificate Management
# =============================================================================
# Manages SSL certificates for Cloudflare Origin Pull setup.
#
# Usage:
#   ./deploy/scripts/ssl.sh [--generate] [--cloudflare-origin]
#
# Flags:
#   --generate           Generate a new self-signed certificate
#   --cloudflare-origin  Download/update Cloudflare Origin Pull CA
# =============================================================================
set -euo pipefail

DEPLOY_DIR="/opt/kinrel"
SSL_DIR="${DEPLOY_DIR}/nginx/ssl"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[SSL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

GENERATE=false
CF_ORIGIN=false

for arg in "$@"; do
  case $arg in
    --generate)          GENERATE=true ;;
    --cloudflare-origin) CF_ORIGIN=true ;;
  esac
done

mkdir -p "${SSL_DIR}"

# ── Generate self-signed certificate ──────────────────────────────────────
if [[ "${GENERATE}" == "true" ]]; then
  log "Generating self-signed SSL certificate..."
  
  # Backup existing cert if present
  if [[ -f "${SSL_DIR}/cert.pem" ]]; then
    BACKUP_TS=$(date +%Y%m%d_%H%M%S)
    cp "${SSL_DIR}/cert.pem" "${SSL_DIR}/cert.pem.bak.${BACKUP_TS}"
    cp "${SSL_DIR}/key.pem" "${SSL_DIR}/key.pem.bak.${BACKUP_TS}"
    warn "Backed up existing certificate"
  fi
  
  openssl req -x509 -nodes \
    -days 3650 \
    -newkey rsa:2048 \
    -keyout "${SSL_DIR}/key.pem" \
    -out "${SSL_DIR}/cert.pem" \
    -subj "/C=IN/ST=Karnataka/L=Bangalore/O=Daxelo/CN=api.kinrel.app"
  
  chmod 600 "${SSL_DIR}/key.pem"
  chmod 644 "${SSL_DIR}/cert.pem"
  
  log "Self-signed certificate generated!"
  log "  Cert: ${SSL_DIR}/cert.pem"
  log "  Key:  ${SSL_DIR}/key.pem"
  log ""
  log "NOTE: With Cloudflare Full (Strict) SSL mode, self-signed certs"
  log "are acceptable because Cloudflare validates using Origin Pull CA."
fi

# ── Download Cloudflare Origin Pull CA ─────────────────────────────────────
if [[ "${CF_ORIGIN}" == "true" ]]; then
  log "Downloading Cloudflare Origin Pull CA certificate..."
  
  curl -fsSL \
    "https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem" \
    -o "${SSL_DIR}/cloudflare-origin-pull.pem"
  
  if [[ -s "${SSL_DIR}/cloudflare-origin-pull.pem" ]]; then
    log "Cloudflare Origin Pull CA downloaded!"
    log "  ${SSL_DIR}/cloudflare-origin-pull.pem"
  else
    warn "Download failed. Get it manually from:"
    warn "  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem"
    rm -f "${SSL_DIR}/cloudflare-origin-pull.pem"
  fi
fi

# ── Verify certificates ──────────────────────────────────────────────────
log "Verifying certificates..."
echo ""

if [[ -f "${SSL_DIR}/cert.pem" ]]; then
  log "Server certificate:"
  openssl x509 -in "${SSL_DIR}/cert.pem" -noout -subject -dates 2>/dev/null || warn "Invalid cert.pem"
else
  warn "cert.pem not found"
fi

echo ""

if [[ -f "${SSL_DIR}/cloudflare-origin-pull.pem" ]]; then
  log "Cloudflare Origin Pull CA:"
  openssl x509 -in "${SSL_DIR}/cloudflare-origin-pull.pem" -noout -subject -dates 2>/dev/null || warn "Invalid cloudflare-origin-pull.pem"
else
  warn "cloudflare-origin-pull.pem not found — download with --cloudflare-origin"
fi
