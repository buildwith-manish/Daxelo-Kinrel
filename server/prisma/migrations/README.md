# Database Migration Safety Guide

This document describes the migration safety practices for the DAXELO KINREL backend. Following these guidelines ensures zero-downtime deployments and prevents data loss.

---

## Table of Contents

1. [Creating Safe Migrations](#creating-safe-migrations)
2. [Deprecation Period Rules](#deprecation-period-rules)
3. [Using the Pre-Migration Check Script](#using-the-pre-migration-check-script)
4. [Rollback Procedures](#rollback-procedures)
5. [Emergency Rollback](#emergency-rollback)
6. [Safe vs Unsafe Migration Examples](#safe-vs-unsafe-migration-examples)

---

## Creating Safe Migrations

### General Principles

1. **Never drop columns or tables directly** — always deprecate first.
2. **Additive changes are safe** — adding columns, tables, or indexes is always non-destructive.
3. **Destructive changes require a deprecation period** — at least one full release cycle.
4. **Always backup before migrating** — use `bun run db:backup`.
5. **Test migrations on a copy of production data** before deploying.

### Migration Workflow

```bash
# 1. Backup the database before any migration
bun run db:backup

# 2. Run the pre-migration safety check
bun run db:check-migration

# 3. If the check passes, create and apply the migration
bunx prisma migrate dev --name your_migration_name

# 4. Verify the migration result
bunx prisma migrate status
```

### Rules for Different Operations

| Operation | Risk Level | Requires Deprecation | Requires Comment |
|---|---|---|---|
| `CREATE TABLE` | Safe | No | No |
| `CREATE INDEX` | Safe | No | No |
| `ADD COLUMN` | Safe | No | No |
| `ALTER TABLE ... RENAME COLUMN` | Medium | Recommended | `-- safe` |
| `ALTER TABLE ... ALTER COLUMN` | Medium | Recommended | `-- safe` |
| `DROP COLUMN` | Dangerous | **Yes** | `-- deprecated` |
| `DROP TABLE` | Dangerous | **Yes** | `-- deprecated` |
| `DROP INDEX` | Dangerous | **Yes** | `-- deprecated` |

---

## Deprecation Period Rules

### Minimum Deprecation: 1 Full Release

When you need to remove a column, table, or index, you **must** follow this process:

1. **Release N (Deprecation Release):**
   - Mark the column/table/index as deprecated in code comments.
   - Stop reading/writing to the column in application code.
   - Add a `-- deprecated` comment to the migration SQL.
   - The pre-migration check will allow the drop only with this comment.

2. **Release N+1 (Removal Release — minimum):**
   - Now you may create the actual `DROP` migration.
   - The `-- deprecated` or `-- safe` comment must be present in the SQL.
   - The pre-migration check will pass.

### Example Timeline

```
Week 1 (Release 1.2.0):
  - Migration: ALTER TABLE "User" ADD COLUMN "newField" TEXT
  - Code: Start writing to "newField", stop reading "oldField"
  - "oldField" is marked deprecated in code but NOT dropped

Week 2+ (Release 1.3.0 — minimum):
  - Migration: ALTER TABLE "User" DROP COLUMN "oldField" -- deprecated
  - Pre-migration check passes because of -- deprecated comment
  - Column is safely removed after all code has stopped using it
```

### Why This Matters

- **Zero downtime**: Application code never references a column that doesn't exist.
- **Rollback safety**: If you need to roll back, the deprecated column is still there.
- **Data recovery**: Even if something goes wrong, backups contain the deprecated data.

---

## Using the Pre-Migration Check Script

The `pre-migration-check.sh` script automatically scans all migration SQL files for dangerous operations.

### Usage

```bash
# Check default directory (prisma/migrations)
bun run db:check-migration

# Or specify a custom directory
./scripts/pre-migration-check.sh path/to/migrations
```

### What It Checks

1. **DROP COLUMN** — Fails unless the line contains `-- deprecated` or `-- safe`
2. **DROP TABLE** — Fails unless the line contains `-- deprecated` or `-- safe`
3. **DROP INDEX** — Fails unless the line contains `-- deprecated` or `-- safe`
4. **ALTER TABLE** — Warns (does not fail) about structural modifications

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | All migrations pass safety checks |
| 1 | Dangerous operations found without deprecation comments |

### Suppressing Warnings

To allow a destructive operation, add a comment on the same line:

```sql
-- This is allowed: has -- deprecated comment
ALTER TABLE "User" DROP COLUMN "oldField"; -- deprecated since v1.2.0

-- This is also allowed: has -- safe comment
DROP INDEX "User_email_idx"; -- safe: replaced by composite index
```

---

## Rollback Procedures

### Prisma Migration Rollback

Prisma does not natively support rollback. Use these strategies instead:

#### 1. Additive Migration Rollback (Recommended)

Create a new migration that reverses the change:

```bash
# Instead of rolling back, create a fix-forward migration
bunx prisma migrate dev --name revert_add_column
```

```sql
-- In the new migration.sql:
ALTER TABLE "User" DROP COLUMN "unwantedColumn"; -- deprecated: rollback of v1.2.0
```

#### 2. Restore from Backup

If a migration causes data corruption or loss:

```bash
# 1. Stop the application
# 2. Restore from the pre-migration backup
bun run db:restore backups/custom_db_20250101_030000.gz

# 3. Reset migration state to before the bad migration
bunx prisma migrate resolve --rolled-back <migration_name>

# 4. Restart the application
```

#### 3. Manual SQL Rollback

For simple changes, manually run the inverse SQL:

```bash
sqlite3 db/custom.db
```

```sql
-- Undo: ADD COLUMN
-- (SQLite doesn't support DROP COLUMN before 3.35.0)
-- Use backup restore instead for older SQLite versions

-- Undo: CREATE TABLE
DROP TABLE "TempTable"; -- safe: temporary table

-- Undo: CREATE INDEX
DROP INDEX "TempIndex"; -- safe: temporary index
```

### Rollback by Operation Type

| Operation | Rollback Strategy |
|---|---|
| `CREATE TABLE` | `DROP TABLE` (if no data to preserve) |
| `ADD COLUMN` | Restore from backup (SQLite limitation) |
| `CREATE INDEX` | `DROP INDEX` |
| `DROP COLUMN` | Restore from backup (data may be lost) |
| `DROP TABLE` | Restore from backup (data may be lost) |
| `DROP INDEX` | Recreate the index |
| `ALTER COLUMN type` | Restore from backup (data may be truncated) |

---

## Emergency Rollback

When things go critically wrong in production:

### Step 1: Stop the Application

```bash
# If running via process manager
pkill -f "bun.*src/main.ts"

# Or stop the container/service
```

### Step 2: Create a Safety Backup of Current State

```bash
# Even if the DB is in a bad state, back it up first
cp db/custom.db db/custom.db.emergency_$(date +%Y%m%d_%H%M%S)
```

### Step 3: Restore from Last Known Good Backup

```bash
# List available backups
ls -lt backups/

# Restore the most recent working backup
./scripts/restore.sh backups/custom_db_YYYYMMDD_HHMMSS.gz
```

### Step 4: Reset Migration State

```bash
# Check migration status
bunx prisma migrate status

# Mark the failed migration as rolled back
bunx prisma migrate resolve --rolled-back <failed_migration_name>

# Or mark it as applied (if the DB schema matches the migration)
bunx prisma migrate resolve --applied <migration_name>
```

### Step 5: Verify and Restart

```bash
# Verify database integrity
sqlite3 db/custom.db "PRAGMA integrity_check;"

# Verify schema matches application expectations
bunx prisma validate

# Restart the application
bun run dev
```

### Emergency Contacts

If the above steps don't resolve the issue:

1. Check the application logs for specific errors
2. Review the migration SQL for syntax errors
3. Consider using `prisma db push --force-reset` as a **last resort** (destroys all data)

---

## Safe vs Unsafe Migration Examples

### ✅ Safe: Adding a Column

```sql
-- prisma/migrations/20250101_000000_add_user_bio/migration.sql
ALTER TABLE "User" ADD COLUMN "bio" TEXT;
```

This is always safe — existing rows get `NULL` for the new column.

---

### ✅ Safe: Adding a Table

```sql
-- prisma/migrations/20250101_000001_add_audit_log/migration.sql
CREATE TABLE "AuditLog" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "action" TEXT NOT NULL,
  "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

---

### ✅ Safe: Adding an Index

```sql
-- prisma/migrations/20250101_000002_add_user_email_idx/migration.sql
CREATE INDEX "User_email_idx" ON "User"("email");
```

---

### ✅ Safe: Dropping with Deprecation Comment

```sql
-- prisma/migrations/20250115_000000_drop_old_field/migration.sql
-- This column was deprecated in v1.2.0 and is no longer used
ALTER TABLE "User" DROP COLUMN "oldField"; -- deprecated since v1.2.0
```

The `-- deprecated` comment tells the pre-migration check script that this drop was intentional and followed the deprecation process.

---

### ❌ Unsafe: Dropping Without Deprecation

```sql
-- prisma/migrations/20250101_000003_drop_user_bio/migration.sql
ALTER TABLE "User" DROP COLUMN "bio";
```

**This will be rejected** by the pre-migration check because there is no `-- deprecated` or `-- safe` comment. Any code still reading `bio` will crash.

---

### ❌ Unsafe: Dropping a Table Without Deprecation

```sql
-- prisma/migrations/20250101_000004_drop_temp_table/migration.sql
DROP TABLE "TempTable";
```

**This will be rejected** unless you add a comment:

```sql
DROP TABLE "TempTable"; -- safe: temporary table, never used in production
```

---

### ⚠️ Warning: ALTER TABLE Modifications

```sql
-- prisma/migrations/20250101_000005_alter_user_name/migration.sql
ALTER TABLE "User" ALTER COLUMN "name" SET DATA TYPE TEXT;
```

This generates a **warning** (not an error) from the pre-migration check. Review these carefully — type changes can truncate data.

---

### ✅ Safe: Renaming with Comment

```sql
-- prisma/migrations/20250101_000006_rename_column/migration.sql
ALTER TABLE "User" RENAME COLUMN "oldName" TO "newName"; -- safe: backward-compatible rename
```

---

## Quick Reference

```bash
# Backup before migration
bun run db:backup

# Check migration safety
bun run db:check-migration

# Restore from backup
bun run db:restore backups/custom_db_TIMESTAMP.gz

# Setup daily auto-backups (3 AM)
./scripts/cron-setup.sh
```
