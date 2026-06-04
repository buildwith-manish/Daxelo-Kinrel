#!/usr/bin/env bash
# =============================================================================
# DAXELO KINREL — Automated Database Backup Script
# =============================================================================
# Creates a timestamped, gzip-compressed backup of the SQLite database.
# Retains the last 30 days of backups; auto-deletes older ones.
#
# Usage:
#   ./scripts/backup.sh [database_path]
#
# Default database path: db/custom.db
#
# Cron example (daily at 3 AM):
#   0 3 * * * /path/to/scripts/backup.sh
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SERVER_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
DB_PATH="${1:-${SERVER_ROOT}/../db/custom.db}"
BACKUP_DIR="${SERVER_ROOT}/backups"
RETENTION_DAYS=30
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ── Resolve paths ─────────────────────────────────────────────────────────────
# If DB_PATH is relative, resolve it against SERVER_ROOT
if [[ "${DB_PATH}" != /* ]]; then
  DB_PATH="${SERVER_ROOT}/${DB_PATH}"
fi

BACKUP_FILENAME="custom_db_${TIMESTAMP}.gz"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILENAME}"

# ── Helper: structured JSON log ───────────────────────────────────────────────
log_json() {
  local action="${1}"
  local source="${2}"
  local backup="${3}"
  local size_bytes="${4}"
  local status="${5}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"timestamp":"%s","action":"%s","source":"%s","backup":"%s","size_bytes":%s,"status":"%s"}\n' \
    "${ts}" "${action}" "${source}" "${backup}" "${size_bytes}" "${status}"
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if [[ ! -f "${DB_PATH}" ]]; then
  log_json "backup" "${DB_PATH}" "" "0" "error:database_not_found"
  exit 1
fi

# ── Create backup directory if it doesn't exist ───────────────────────────────
mkdir -p "${BACKUP_DIR}"

# ── Create compressed backup ──────────────────────────────────────────────────
# Using sqlite3 .backup to get a consistent snapshot, then gzip it.
# Falls back to direct file copy + gzip if sqlite3 CLI is unavailable.
TEMP_BACKUP="${BACKUP_DIR}/.tmp_backup_${TIMESTAMP}.db"

if command -v sqlite3 &>/dev/null; then
  # Use SQLite's built-in .backup for a consistent, non-corrupt snapshot
  if ! sqlite3 "${DB_PATH}" ".backup '${TEMP_BACKUP}'" 2>/dev/null; then
    # Fallback: direct copy (may have minor inconsistency under write load)
    cp "${DB_PATH}" "${TEMP_BACKUP}"
  fi
else
  # No sqlite3 CLI available — fall back to direct copy
  cp "${DB_PATH}" "${TEMP_BACKUP}"
fi

# Compress the backup with gzip
gzip -c "${TEMP_BACKUP}" > "${BACKUP_FILE}"

# Remove the temporary uncompressed backup
rm -f "${TEMP_BACKUP}"

# ── Verify backup integrity ───────────────────────────────────────────────────
if [[ ! -f "${BACKUP_FILE}" ]]; then
  log_json "backup" "${DB_PATH}" "${BACKUP_FILE}" "0" "error:backup_file_missing"
  exit 1
fi

BACKUP_SIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || stat -f%z "${BACKUP_FILE}" 2>/dev/null || echo "0")

if [[ "${BACKUP_SIZE}" -eq 0 ]]; then
  rm -f "${BACKUP_FILE}"
  log_json "backup" "${DB_PATH}" "${BACKUP_FILE}" "0" "error:backup_empty"
  exit 1
fi

# Verify gzip integrity
if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
  rm -f "${BACKUP_FILE}"
  log_json "backup" "${DB_PATH}" "${BACKUP_FILE}" "${BACKUP_SIZE}" "error:gzip_integrity_failed"
  exit 1
fi

# ── Delete backups older than RETENTION_DAYS ──────────────────────────────────
DELETED_COUNT=0
if command -v find &>/dev/null; then
  while IFS= read -r -d '' old_backup; do
    rm -f "${old_backup}"
    DELETED_COUNT=$((DELETED_COUNT + 1))
  done < <(find "${BACKUP_DIR}" -name "custom_db_*.gz" -type f -mtime +"${RETENTION_DAYS}" -print0 2>/dev/null)
fi

# ── Log success ───────────────────────────────────────────────────────────────
log_json "backup" "${DB_PATH}" "${BACKUP_FILE}" "${BACKUP_SIZE}" "success"

if [[ "${DELETED_COUNT}" -gt 0 ]]; then
  log_json "cleanup" "${BACKUP_DIR}" "" "${DELETED_COUNT}" "deleted_old_backups"
fi
