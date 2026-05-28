#!/usr/bin/env bash
# =============================================================================
# DAXELO KINREL — Pre-Migration Safety Check Script
# =============================================================================
# Reads pending migration SQL files and checks for dangerous operations:
#   - DROP COLUMN (without "-- deprecated" or "-- safe" comment)
#   - DROP TABLE  (without "-- deprecated" or "-- safe" comment)
#   - DROP INDEX  (without "-- deprecated" or "-- safe" comment)
# Warns about:
#   - ALTER TABLE modifications
# Returns exit code 1 if dangerous operations are found.
#
# Usage:
#   ./scripts/pre-migration-check.sh [migration_dir]
#
# Default migration dir: prisma/migrations
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SERVER_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
MIGRATION_DIR="${1:-${SERVER_ROOT}/prisma/migrations}"

# Resolve relative path
if [[ "${MIGRATION_DIR}" != /* ]]; then
  MIGRATION_DIR="${SERVER_ROOT}/${MIGRATION_DIR}"
fi

# ── Counters ──────────────────────────────────────────────────────────────────
DANGEROUS_COUNT=0
WARNING_COUNT=0
FILES_CHECKED=0

# ── Colors for terminal output ────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ── Helper functions ──────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "  Pre-Migration Safety Check"
  echo "  Migration dir: ${MIGRATION_DIR}"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
}

print_result() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  if [[ "${DANGEROUS_COUNT}" -gt 0 ]]; then
    echo -e "  ${RED}FAILED: ${DANGEROUS_COUNT} dangerous operation(s) found${NC}"
    echo -e "  ${YELLOW}Warnings: ${WARNING_COUNT}${NC}"
    echo ""
    echo "  Fix: Add '-- deprecated' or '-- safe' comments to suppress"
    echo "  dangerous operation warnings, or use a safer migration strategy."
    echo "═══════════════════════════════════════════════════════════"
    exit 1
  else
    echo -e "  ${GREEN}PASSED: No dangerous operations found${NC}"
    if [[ "${WARNING_COUNT}" -gt 0 ]]; then
      echo -e "  ${YELLOW}Warnings: ${WARNING_COUNT} (review recommended)${NC}"
    fi
    echo "═══════════════════════════════════════════════════════════"
    exit 0
  fi
}

# ── Check migration directory exists ──────────────────────────────────────────
if [[ ! -d "${MIGRATION_DIR}" ]]; then
  echo "Migration directory not found: ${MIGRATION_DIR}" >&2
  echo "No migrations to check. Exiting with success."
  exit 0
fi

print_header

# ── Find and check migration SQL files ────────────────────────────────────────
# Prisma migrations are in subdirectories: prisma/migrations/<timestamp_name>/migration.sql
MIGRATION_FILES=()
while IFS= read -r -d '' file; do
  MIGRATION_FILES+=("${file}")
done < <(find "${MIGRATION_DIR}" -name "migration.sql" -type f -print0 2>/dev/null | sort -z)

if [[ ${#MIGRATION_FILES[@]} -eq 0 ]]; then
  echo "No migration.sql files found in ${MIGRATION_DIR}"
  echo "Nothing to check."
  print_result
fi

for migration_file in "${MIGRATION_FILES[@]}"; do
  # Get the migration folder name (e.g., "20250101_000000_add_user_table")
  migration_name="$(basename "$(dirname "${migration_file}")")"
  FILES_CHECKED=$((FILES_CHECKED + 1))

  echo "Checking: ${migration_name}"
  echo "  File: ${migration_file}"

  # Read the migration SQL content
  sql_content=""
  if [[ -f "${migration_file}" ]]; then
    sql_content="$(cat "${migration_file}")"
  else
    echo "  SKIP: File not readable"
    continue
  fi

  # Skip if the file is empty or only comments
  if [[ -z "$(echo "${sql_content}" | sed '/^--/d' | sed '/^$/d' | tr -d '[:space:]')" ]]; then
    echo "  SKIP: Empty migration (comments only)"
    echo ""
    continue
  fi

  # ── Check for DROP COLUMN ───────────────────────────────────────────────────
  # Match lines containing "DROP COLUMN" that are NOT commented out
  while IFS= read -r line; do
    line_number="$(echo "${line}" | cut -d: -f1)"
    line_content="$(echo "${line}" | cut -d: -f2-)"

    # Check if the line has a -- deprecated or -- safe comment on the same line
    if echo "${line_content}" | grep -qiE '(--.*deprecated|--.*safe)'; then
      echo -e "  ${GREEN}  OK${NC}: Line ${line_number}: DROP COLUMN with deprecation/safe comment"
    else
      echo -e "  ${RED}  DANGEROUS${NC}: Line ${line_number}: DROP COLUMN without deprecation comment"
      echo "    ${line_content}"
      DANGEROUS_COUNT=$((DANGEROUS_COUNT + 1))
    fi
  done < <(echo "${sql_content}" | grep -niE 'DROP\s+COLUMN' | grep -v '^--')

  # ── Check for DROP TABLE ────────────────────────────────────────────────────
  while IFS= read -r line; do
    line_number="$(echo "${line}" | cut -d: -f1)"
    line_content="$(echo "${line}" | cut -d: -f2-)"

    if echo "${line_content}" | grep -qiE '(--.*deprecated|--.*safe)'; then
      echo -e "  ${GREEN}  OK${NC}: Line ${line_number}: DROP TABLE with deprecation/safe comment"
    else
      echo -e "  ${RED}  DANGEROUS${NC}: Line ${line_number}: DROP TABLE without deprecation comment"
      echo "    ${line_content}"
      DANGEROUS_COUNT=$((DANGEROUS_COUNT + 1))
    fi
  done < <(echo "${sql_content}" | grep -niE 'DROP\s+TABLE' | grep -v '^--')

  # ── Check for DROP INDEX ────────────────────────────────────────────────────
  while IFS= read -r line; do
    line_number="$(echo "${line}" | cut -d: -f1)"
    line_content="$(echo "${line}" | cut -d: -f2-)"

    if echo "${line_content}" | grep -qiE '(--.*deprecated|--.*safe)'; then
      echo -e "  ${GREEN}  OK${NC}: Line ${line_number}: DROP INDEX with deprecation/safe comment"
    else
      echo -e "  ${RED}  DANGEROUS${NC}: Line ${line_number}: DROP INDEX without deprecation comment"
      echo "    ${line_content}"
      DANGEROUS_COUNT=$((DANGEROUS_COUNT + 1))
    fi
  done < <(echo "${sql_content}" | grep -niE 'DROP\s+INDEX' | grep -v '^--')

  # ── Warn about ALTER TABLE ──────────────────────────────────────────────────
  alter_count=0
  while IFS= read -r line; do
    line_number="$(echo "${line}" | cut -d: -f1)"
    line_content="$(echo "${line}" | cut -d: -f2-)"
    echo -e "  ${YELLOW}  WARNING${NC}: Line ${line_number}: ALTER TABLE modification"
    echo "    ${line_content}"
    WARNING_COUNT=$((WARNING_COUNT + 1))
    alter_count=$((alter_count + 1))
  done < <(echo "${sql_content}" | grep -niE 'ALTER\s+TABLE' | grep -v '^--')

  if [[ ${alter_count} -eq 0 ]] && [[ ${DANGEROUS_COUNT} -eq 0 ]]; then
    echo -e "  ${GREEN}  CLEAN${NC}: No dangerous or concerning operations"
  fi

  echo ""
done

echo "Files checked: ${FILES_CHECKED}"
print_result
