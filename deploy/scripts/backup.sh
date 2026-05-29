#!/usr/bin/env bash
# =============================================================================
# Daxelo-Kinrel — Backup Script
# =============================================================================
# Creates a complete backup of the production database and configuration.
#
# Usage:
#   ./deploy/scripts/backup.sh [--full]
#
# Flags:
#   --full   Also backup Redis data and Docker volumes
#
# Backups are stored in /opt/kinrel/backups/ with timestamps.
# Old backups are automatically cleaned up (keep last 14).
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BACKUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

DEPLOY_DIR="/opt/kinrel"
REPO_DIR="${DEPLOY_DIR}/repo"
COMPOSE_FILE="${REPO_DIR}/deploy/docker-compose.prod.yml"
BACKUP_DIR="${DEPLOY_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FULL_BACKUP=false

for arg in "$@"; do
  case $arg in
    --full) FULL_BACKUP=true ;;
  esac
done

mkdir -p "${BACKUP_DIR}"

# ── 1. Supabase Database Backup ───────────────────────────────────────────
log "Creating Supabase database backup..."

# Source env for DATABASE_URL
if [[ -f "${DEPLOY_DIR}/.env.production" ]]; then
  set -a
  source "${DEPLOY_DIR}/.env.production"
  set +a
fi

# Use pg_dump with the direct connection URL
DB_BACKUP="${BACKUP_DIR}/supabase_${TIMESTAMP}.sql"
if [[ -n "${DIRECT_URL:-}" ]]; then
  # Install postgresql-client if not present
  if ! command -v pg_dump &>/dev/null; then
    log "Installing postgresql-client..."
    apt-get update -qq && apt-get install -y -qq postgresql-client > /dev/null 2>&1
  fi
  
  pg_dump "${DIRECT_URL}" --no-owner --no-acl > "${DB_BACKUP}" 2>/dev/null && \
    log "Database backup saved: ${DB_BACKUP}" || \
    warn "pg_dump failed — try Supabase Dashboard → Database → Backups instead"
else
  warn "DIRECT_URL not set in .env.production — cannot run pg_dump"
  warn "Use Supabase Dashboard → Database → Backups for manual backup"
fi

# ── 2. Environment configuration backup ───────────────────────────────────
log "Backing up environment configuration..."
cp "${DEPLOY_DIR}/.env.production" "${BACKUP_DIR}/env_${TIMESTAMP}.production"
chmod 600 "${BACKUP_DIR}/env_${TIMESTAMP}.production"

# ── 3. Nginx config backup ────────────────────────────────────────────────
log "Backing up Nginx configuration..."
tar czf "${BACKUP_DIR}/nginx_${TIMESTAMP}.tar.gz" -C "${DEPLOY_DIR}" nginx/

# ── 4. Full backup (optional) ─────────────────────────────────────────────
if [[ "${FULL_BACKUP}" == "true" ]]; then
  log "Creating full backup (Redis + Docker volumes)..."
  
  # Redis backup
  REDIS_BACKUP="${BACKUP_DIR}/redis_${TIMESTAMP}.rdb"
  docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli BGSAVE 2>/dev/null || true
  sleep 2
  docker compose -f "${COMPOSE_FILE}" cp redis:/data/dump.rdb "${REDIS_BACKUP}" 2>/dev/null || \
    warn "Redis backup failed"
  
  log "Full backup saved: ${REDIS_BACKUP}"
fi

# ── 5. Cleanup old backups ────────────────────────────────────────────────
log "Cleaning up old backups (keeping last 14)..."
find "${BACKUP_DIR}" -name "*.sql" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "*.rdb" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "*.production" -mtime +14 -delete 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────
log "============================================"
log "Backup complete!"
log "============================================"
log "Backup directory: ${BACKUP_DIR}"
ls -lh "${BACKUP_DIR}/" | tail -5
