#!/bin/bash
# DAXELO KINREL — Database Restore Script (P3-B4)
#
# Restores a database backup with a safety prompt.
# Supports both PostgreSQL and SQLite.
#
# Usage: bash scripts/restore_db.sh [backup_file]

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# ── Load environment ──────────────────────────────────────────────
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

# ── Validate ──────────────────────────────────────────────────────
if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL not set. Please configure .env"
  exit 1
fi

# ── Select backup file ──────────────────────────────────────────
BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
  echo "📦 Available backups:"
  echo ""
  ls -lht "$BACKUP_DIR"/backup_* 2>/dev/null || echo "  No backups found"
  echo ""
  read -rp "Enter the backup filename to restore: " BACKUP_FILE
  BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Backup file not found: $BACKUP_FILE"
  exit 1
fi

# ── Safety prompt ────────────────────────────────────────────────
echo ""
echo "⚠️  WARNING: This will OVERWRITE the current database!"
echo "   Backup file: $BACKUP_FILE"
echo "   Size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo ""
read -rp "Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Restore cancelled"
  exit 0
fi

# ── Create pre-restore backup ───────────────────────────────────
echo "📦 Creating pre-restore safety backup..."
bash "$SCRIPT_DIR/backup_db.sh"

# ── Restore based on database type ──────────────────────────────
if echo "$DATABASE_URL" | grep -qi "postgresql\|postgres"; then
  echo "🐘 Restoring PostgreSQL database..."
  
  if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | psql "$DATABASE_URL"
  else
    psql "$DATABASE_URL" < "$BACKUP_FILE"
  fi
  
  echo "✅ PostgreSQL restore complete"

elif echo "$DATABASE_URL" | grep -qi "file:"; then
  echo "🗄️  Restoring SQLite database..."
  
  DB_PATH="${DATABASE_URL#file:}"
  if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" > "$DB_PATH"
  else
    cp "$BACKUP_FILE" "$DB_PATH"
  fi
  
  echo "✅ SQLite restore complete"
else
  echo "❌ Unsupported database type"
  exit 1
fi

echo "✅ Restore finished successfully"
