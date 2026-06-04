#!/usr/bin/env bash
# =============================================================================
# DAXELO KINREL — Cron Job Setup Script
# =============================================================================
# Adds a daily database backup cron job (runs at 3 AM).
# Idempotent — will not add duplicate entries.
#
# Usage:
#   ./scripts/cron-setup.sh
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SERVER_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
BACKUP_SCRIPT="${SERVER_ROOT}/scripts/backup.sh"
CRON_SCHEDULE="0 3 * * *"
CRON_MARKER="# DAXELO_KINREL_DB_BACKUP"
CRON_ENTRY="${CRON_SCHEDULE} ${BACKUP_SCRIPT} ${CRON_MARKER}"

# ── Helper: structured JSON log ───────────────────────────────────────────────
log_json() {
  local action="${1}"
  local detail="${2}"
  local status="${3}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"timestamp":"%s","action":"%s","detail":"%s","status":"%s"}\n' \
    "${ts}" "${action}" "${detail}" "${status}"
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────

# Check if cron/crontab is available
if ! command -v crontab &>/dev/null; then
  log_json "cron_setup" "crontab command not found" "error:crontab_unavailable"
  echo "ERROR: crontab command is not available on this system." >&2
  echo "Please install cron and try again." >&2
  exit 1
fi

# Check if the backup script exists
if [[ ! -f "${BACKUP_SCRIPT}" ]]; then
  log_json "cron_setup" "Backup script not found: ${BACKUP_SCRIPT}" "error:backup_script_missing"
  echo "ERROR: Backup script not found: ${BACKUP_SCRIPT}" >&2
  exit 1
fi

# Ensure the backup script is executable
chmod +x "${BACKUP_SCRIPT}"

# ── Check if cron job already exists (idempotent) ─────────────────────────────
EXISTING_CRON=""
if crontab -l 2>/dev/null; then
  EXISTING_CRON="$(crontab -l 2>/dev/null)"
fi

if echo "${EXISTING_CRON}" | grep -qF "${CRON_MARKER}"; then
  log_json "cron_setup" "Cron job already exists (${CRON_SCHEDULE})" "skipped:already_exists"
  echo "Cron job already exists. No changes made."
  echo "Schedule: ${CRON_SCHEDULE}"
  echo "Script:   ${BACKUP_SCRIPT}"
  exit 0
fi

# ── Add cron job ──────────────────────────────────────────────────────────────
# Append the new cron entry to the existing crontab
NEW_CRON="${EXISTING_CRON}"
# Ensure we have a trailing newline before appending
if [[ -n "${NEW_CRON}" ]] && [[ "${NEW_CRON}" != *$'\n' ]]; then
  NEW_CRON="${NEW_CRON}"$'\n'
fi
NEW_CRON="${NEW_CRON}${CRON_ENTRY}"

echo "${NEW_CRON}" | crontab -

# ── Verify the cron job was added ─────────────────────────────────────────────
if crontab -l 2>/dev/null | grep -qF "${CRON_MARKER}"; then
  log_json "cron_setup" "Cron job added (${CRON_SCHEDULE} ${BACKUP_SCRIPT})" "success"
  echo "✓ Daily backup cron job added successfully."
  echo "  Schedule: ${CRON_SCHEDULE} (daily at 3:00 AM)"
  echo "  Script:   ${BACKUP_SCRIPT}"
  echo ""
  echo "To view current crontab: crontab -l"
  echo "To remove the cron job:  crontab -e (then delete the line with DAXELO_KINREL_DB_BACKUP)"
else
  log_json "cron_setup" "Failed to verify cron job" "error:verification_failed"
  echo "ERROR: Cron job may not have been added. Please verify with: crontab -l" >&2
  exit 1
fi
