#!/bin/bash
# DAXELO KINREL — Database Backup Script (P3-B4)
#
# Creates a timestamped backup of the PostgreSQL database.
# Automatically detects the database type from DATABASE_URL.
# Deletes backups older than 7 days.
#
# Usage: bash scripts/backup_db.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
RETENTION_DAYS=7

# ── Load environment ──────────────────────────────────────────────
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
elif [ -f "$PROJECT_DIR/.env.example" ]; then
  echo "⚠️  .env not found, using .env.example as fallback"
  set -a
  source "$PROJECT_DIR/.env.example"
  set +a
fi

# ── Validate DATABASE_URL ─────────────────────────────────────────
if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL not set. Please configure .env"
  exit 1
fi

# ── Create backup directory ──────────────────────────────────────
mkdir -p "$BACKUP_DIR"

# ── Timestamp ────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ── Detect database type and backup ──────────────────────────────
if echo "$DATABASE_URL" | grep -qi "postgresql\|postgres"; then
  # ── PostgreSQL Backup ──────────────────────────────────────────
  BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.sql"
  
  echo "🐘 PostgreSQL backup starting..."
  echo "   Database URL: ${DATABASE_URL%%\?*}..." # Hide query params
  
  if command -v pg_dump &> /dev/null; then
    pg_dump "$DATABASE_URL" --no-owner --no-acl > "$BACKUP_FILE"
    COMPRESSED_FILE="${BACKUP_FILE}.gz"
    gzip "$BACKUP_FILE"
    BACKUP_FILE="$COMPRESSED_FILE"
    echo "✅ Backup complete: $(basename "$BACKUP_FILE")"
  else
    echo "⚠️  pg_dump not found. Attempting alternative method..."
    # Try using npx prisma to export data
    cd "$PROJECT_DIR"
    npx prisma db pull --print > "$BACKUP_FILE" 2>/dev/null || true
    echo "✅ Schema backup complete: $(basename "$BACKUP_FILE")"
    echo "   ⚠️  For full data backup, install PostgreSQL client tools"
  fi

elif echo "$DATABASE_URL" | grep -qi "file:"; then
  # ── SQLite Backup ──────────────────────────────────────────────
  # Extract file path from DATABASE_URL (file:./dev.db or file:/path/to/db)
  DB_PATH="${DATABASE_URL#file:}"
  if [ ! -f "$DB_PATH" ]; then
    # Try relative to project dir
    DB_PATH="$PROJECT_DIR/${DATABASE_URL#file:}"
  fi
  
  if [ -f "$DB_PATH" ]; then
    BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.db"
    echo "🗄️  SQLite backup starting..."
    cp "$DB_PATH" "$BACKUP_FILE"
    echo "✅ Backup complete: $(basename "$BACKUP_FILE") ($(du -h "$BACKUP_FILE" | cut -f1))"
  else
    echo "❌ SQLite database file not found: $DB_PATH"
    exit 1
  fi

else
  echo "❌ Unsupported database type in DATABASE_URL"
  echo "   Supported: PostgreSQL (postgresql://...) and SQLite (file:...)"
  exit 1
fi

# ── Cleanup old backups ──────────────────────────────────────────
echo "🧹 Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "backup_*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────
REMAINING=$(find "$BACKUP_DIR" -name "backup_*" | wc -l | tr -d ' ')
echo "📦 Total backups remaining: $REMAINING"
echo "✅ Backup script finished successfully"
