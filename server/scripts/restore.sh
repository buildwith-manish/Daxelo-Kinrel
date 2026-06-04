#!/usr/bin/env bash
# =============================================================================
# DAXELO KINREL — Database Restore Script
# =============================================================================
# Restores the SQLite database from a gzip-compressed backup file.
# Creates a pre-restore safety backup of the current database before replacing.
#
# Usage:
#   ./scripts/restore.sh <backup_file>
#
# Example:
#   ./scripts/restore.sh backups/custom_db_20250101_030000.gz
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SERVER_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
DB_PATH="${SERVER_ROOT}/../db/custom.db"
BACKUP_DIR="${SERVER_ROOT}/backups"

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

# ── Validate arguments ────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: ./scripts/restore.sh <backup_file>" >&2
  echo "Example: ./scripts/restore.sh backups/custom_db_20250101_030000.gz" >&2
  log_json "restore" "" "" "0" "error:missing_argument"
  exit 1
fi

BACKUP_FILE="${1}"

# Resolve relative path against SERVER_ROOT
if [[ "${BACKUP_FILE}" != /* ]]; then
  BACKUP_FILE="${SERVER_ROOT}/${BACKUP_FILE}"
fi

# ── Verify backup file exists ─────────────────────────────────────────────────
if [[ ! -f "${BACKUP_FILE}" ]]; then
  log_json "restore" "${BACKUP_FILE}" "${DB_PATH}" "0" "error:backup_file_not_found"
  exit 1
fi

# ── Verify backup is valid gzip ───────────────────────────────────────────────
if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
  log_json "restore" "${BACKUP_FILE}" "${DB_PATH}" "0" "error:invalid_gzip"
  exit 1
fi

BACKUP_SIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || stat -f%z "${BACKUP_FILE}" 2>/dev/null || echo "0")

# ── Create pre-restore safety backup of current DB ────────────────────────────
if [[ -f "${DB_PATH}" ]]; then
  mkdir -p "${BACKUP_DIR}"
  PRE_RESTORE_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  PRE_RESTORE_FILE="${BACKUP_DIR}/pre_restore_${PRE_RESTORE_TIMESTAMP}.gz"

  echo "Creating pre-restore safety backup..."
  gzip -c "${DB_PATH}" > "${PRE_RESTORE_FILE}"

  # Verify the pre-restore backup
  if [[ -f "${PRE_RESTORE_FILE}" ]] && gzip -t "${PRE_RESTORE_FILE}" 2>/dev/null; then
    PRE_RESTORE_SIZE=$(stat -c%s "${PRE_RESTORE_FILE}" 2>/dev/null || stat -f%z "${PRE_RESTORE_FILE}" 2>/dev/null || echo "0")
    log_json "pre_restore_backup" "${DB_PATH}" "${PRE_RESTORE_FILE}" "${PRE_RESTORE_SIZE}" "success"
  else
    log_json "pre_restore_backup" "${DB_PATH}" "${PRE_RESTORE_FILE}" "0" "error:pre_restore_failed"
    echo "WARNING: Pre-restore backup failed. Aborting restore to protect current data." >&2
    exit 1
  fi
else
  echo "No current database found at ${DB_PATH}. Skipping pre-restore backup."
  log_json "pre_restore_backup" "${DB_PATH}" "" "0" "skipped:no_current_db"
fi

# ── Decompress and replace the current database ───────────────────────────────
echo "Restoring database from ${BACKUP_FILE}..."

# Decompress to a temporary file first
TEMP_RESTORE="${BACKUP_DIR}/.tmp_restore_$$.db"
gunzip -c "${BACKUP_FILE}" > "${TEMP_RESTORE}"

# Verify the decompressed file is non-empty
RESTORE_SIZE=$(stat -c%s "${TEMP_RESTORE}" 2>/dev/null || stat -f%z "${TEMP_RESTORE}" 2>/dev/null || echo "0")

if [[ "${RESTORE_SIZE}" -eq 0 ]]; then
  rm -f "${TEMP_RESTORE}"
  log_json "restore" "${BACKUP_FILE}" "${DB_PATH}" "${BACKUP_SIZE}" "error:decompressed_empty"
  exit 1
fi

# Verify the decompressed file is a valid SQLite database
if command -v sqlite3 &>/dev/null; then
  if ! sqlite3 "${TEMP_RESTORE}" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
    rm -f "${TEMP_RESTORE}"
    log_json "restore" "${BACKUP_FILE}" "${DB_PATH}" "${BACKUP_SIZE}" "error:sqlite_integrity_failed"
    exit 1
  fi
fi

# Replace the current database with the restored one
mv "${TEMP_RESTORE}" "${DB_PATH}"

# ── Log success ───────────────────────────────────────────────────────────────
FINAL_SIZE=$(stat -c%s "${DB_PATH}" 2>/dev/null || stat -f%z "${DB_PATH}" 2>/dev/null || echo "0")
log_json "restore" "${BACKUP_FILE}" "${DB_PATH}" "${FINAL_SIZE}" "success"
echo "Database restored successfully from ${BACKUP_FILE}"
