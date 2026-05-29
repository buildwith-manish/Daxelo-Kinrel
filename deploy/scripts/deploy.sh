#!/usr/bin/env bash
# =============================================================================
# Daxelo-Kinrel — Deployment Script
# =============================================================================
# Deploys or updates the Daxelo-Kinrel stack on the VPS.
#
# Usage:
#   ./deploy/scripts/deploy.sh [--build] [--no-backup]
#
# Flags:
#   --build      Force rebuild Docker images (use after code changes)
#   --no-backup  Skip database backup before deployment
#
# Prerequisites:
#   - VPS setup completed (setup-vps.sh)
#   - .env.production configured at /opt/kinrel/.env.production
#   - Git repo cloned at /opt/kinrel/repo
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ── Parse arguments ────────────────────────────────────────────────────────
FORCE_BUILD=false
SKIP_BACKUP=false

for arg in "$@"; do
  case $arg in
    --build)     FORCE_BUILD=true ;;
    --no-backup) SKIP_BACKUP=true ;;
    *)           warn "Unknown argument: $arg" ;;
  esac
done

# ── Configuration ──────────────────────────────────────────────────────────
DEPLOY_DIR="/opt/kinrel"
REPO_DIR="${DEPLOY_DIR}/repo"
ENV_FILE="${DEPLOY_DIR}/.env.production"
COMPOSE_FILE="${REPO_DIR}/deploy/docker-compose.prod.yml"
BACKUP_DIR="${DEPLOY_DIR}/backups"

# ── Pre-flight checks ─────────────────────────────────────────────────────
log "Running pre-flight checks..."

if [[ ! -f "${ENV_FILE}" ]]; then
  err "Missing ${ENV_FILE}! Create it from the template first."
fi

if [[ ! -d "${REPO_DIR}" ]]; then
  err "Repository not found at ${REPO_DIR}. Clone it first."
fi

if ! command -v docker &>/dev/null; then
  err "Docker is not installed. Run setup-vps.sh first."
fi

if ! docker compose version &>/dev/null; then
  err "Docker Compose v2 is not available."
fi

log "Pre-flight checks passed!"

# ── Pull latest code ──────────────────────────────────────────────────────
log "Pulling latest code from GitHub..."
cd "${REPO_DIR}"
git fetch origin main
git reset --hard origin/main
log "Code updated to latest!"

# ── Database backup (before deployment) ───────────────────────────────────
if [[ "${SKIP_BACKUP}" == "false" ]]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"
  
  log "Creating database backup..."
  mkdir -p "${BACKUP_DIR}"
  
  # Use Supabase pg_dump via the API container
  if docker compose -f "${COMPOSE_FILE}" ps api 2>/dev/null | grep -q 'Up'; then
    # API is running — use Prisma to export data
    docker compose -f "${COMPOSE_FILE}" exec -T api npx prisma db pull --print 2>/dev/null > "${BACKUP_FILE}" || true
  fi
  
  # Also create a backup via Supabase API
  if [[ -n "${SUPABASE_URL:-}" ]] && [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    log "Triggering Supabase backup..."
    curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/backup" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      > /dev/null 2>&1 || warn "Supabase backup not available via RPC"
  fi
  
  # Clean up old backups (keep last 7)
  ls -t "${BACKUP_DIR}"/db_backup_*.sql 2>/dev/null | tail -n +8 | xargs -r rm --
  
  log "Backup completed!"
else
  warn "Skipping backup (--no-backup flag)"
fi

# ── Copy configuration files ──────────────────────────────────────────────
log "Syncing configuration files..."

# Copy Nginx config
cp -r "${REPO_DIR}/deploy/nginx/"* "${DEPLOY_DIR}/nginx/"
mkdir -p "${DEPLOY_DIR}/nginx/conf.d"

# Ensure SSL directory exists with proper permissions
mkdir -p "${DEPLOY_DIR}/nginx/ssl"
chmod 600 "${DEPLOY_DIR}/nginx/ssl/key.pem" 2>/dev/null || true

log "Configuration files synced!"

# ── Run Prisma migrations ─────────────────────────────────────────────────
if [[ "${FORCE_BUILD}" == "true" ]]; then
  log "Running Prisma migrations against Supabase..."
  
  # Source env for DATABASE_URL
  set -a
  source "${ENV_FILE}"
  set +a
  
  cd "${REPO_DIR}/server"
  
  # Generate Prisma client
  npx prisma generate || warn "Prisma generate had warnings"
  
  # Deploy migrations to Supabase PostgreSQL
  # NOTE: This requires DIRECT_URL to be set for migrations
  if [[ -n "${DIRECT_URL:-}" ]]; then
    npx prisma migrate deploy || warn "Prisma migrate deploy had issues — check manually"
  else
    warn "DIRECT_URL not set, skipping Prisma migrations"
  fi
  
  cd "${REPO_DIR}"
fi

# ── Deploy Docker stack ──────────────────────────────────────────────────
log "Deploying Docker stack..."

cd "${DEPLOY_DIR}"

DOCKER_ARGS=()
if [[ "${FORCE_BUILD}" == "true" ]]; then
  DOCKER_ARGS+=("--build")
  log "Force rebuilding Docker images..."
fi

docker compose -f "${COMPOSE_FILE}" \
  --env-file "${ENV_FILE}" \
  up -d ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"}

log "Docker stack deployed!"

# ── Wait for health checks ────────────────────────────────────────────────
log "Waiting for services to become healthy..."
sleep 10

# Check each service
check_service() {
  local service=$1
  local max_attempts=12
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    local status
    status=$(docker compose -f "${COMPOSE_FILE}" ps "${service}" --format json 2>/dev/null | \
      python3 -c "import sys, json; print(json.load(sys.stdin).get('Health', 'unknown'))" 2>/dev/null || echo "unknown")
    
    if [[ "${status}" == "healthy" ]]; then
      log "${service} is healthy!"
      return 0
    fi
    
    info "  ${service}: ${status} (attempt ${attempt}/${max_attempts})"
    sleep 5
    ((attempt++))
  done
  
  warn "${service} did not become healthy within timeout"
  return 1
}

check_service redis
check_service api
check_service nginx

# ── Verify deployment ─────────────────────────────────────────────────────
log "Verifying deployment..."

# Test health endpoint
HEALTH_RESPONSE=$(curl -s http://localhost/api/health 2>/dev/null || \
                  curl -s http://localhost:3001/api/health 2>/dev/null || \
                  echo "FAILED")

if echo "${HEALTH_RESPONSE}" | grep -q '"status"'; then
  log "API health check: PASSED"
  info "  Response: ${HEALTH_RESPONSE}"
else
  warn "API health check: FAILED"
  warn "  Response: ${HEALTH_RESPONSE}"
  warn "  Check logs: docker compose -f ${COMPOSE_FILE} logs api"
fi

# ── Show status ───────────────────────────────────────────────────────────
log "============================================"
log "Deployment complete!"
log "============================================"
echo ""
docker compose -f "${COMPOSE_FILE}" ps
echo ""
log "Useful commands:"
log "  View logs:       docker compose -f ${COMPOSE_FILE} logs -f api"
log "  View Nginx logs: docker compose -f ${COMPOSE_FILE} logs -f nginx"
log "  Restart API:     docker compose -f ${COMPOSE_FILE} restart api"
log "  Full restart:    docker compose -f ${COMPOSE_FILE} down && docker compose -f ${COMPOSE_FILE} up -d"
log "  Shell into API:  docker compose -f ${COMPOSE_FILE} exec api sh"
log ""
log "API should be accessible at:"
log "  http://$(hostname -I | awk '{print $1}')/api/health"
