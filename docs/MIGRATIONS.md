# Database Migration Policy — Daxelo-Kinrel

> **Source of truth:** `supabase/migrations/` (Supabase CLI)
> **Deprecated:** `server/prisma/migrations/` (archived to `server/prisma/_archive_pre_supabase_cli/`)
> **Prisma role:** Type generator only — refresh with `prisma db pull`, never `prisma migrate dev`

---

## TL;DR — The Rule

**Every schema change must be:**

1. Authored as a SQL file in `supabase/migrations/<timestamp>_<name>.sql`
2. Peer-reviewed in a Pull Request
3. Applied to Supabase via `supabase db push` from the repo

**NEVER use the Supabase Dashboard SQL Editor's "Save as migration" feature.**
That's what caused 57 migrations to be applied to production without ever
being committed to the repo (the original audit's #1 finding).

---

## Why Supabase CLI over Prisma Migrate

The Daxelo-Kinrel database makes heavy use of Supabase-native features
that Prisma Migrate cannot express:

- **Row-Level Security (RLS) policies** — 225 policies across 83 tables
- **`SECURITY DEFINER` RPC functions** — 12 functions in `public` schema
- **Postgres triggers** — 8 triggers including `on_auth_user_created`, `set_updated_at`
- **Storage bucket policies** — 3 policies on `storage.objects` for the avatars bucket
- **Realtime publication** — 4 tables in `supabase_realtime`
- **`pg_trgm` extension** — moved to `extensions` schema
- **`search_path` hardening** — pinned on every function

Prisma Migrate only handles tables/columns/indexes/relations. Using it
as the primary migration tool would require maintaining a parallel set
of raw SQL files for everything else — which is exactly the drift that
got us into the original audit mess.

---

## Setup (one-time)

```bash
# 1. Install Supabase CLI (macOS)
brew install supabase/tap/supabase

# Or via npm
npm install -g supabase

# 2. Login and link the project
supabase login
supabase link --project-ref promxswvsnvilplmrtsj

# 3. Verify the link works
supabase migration list
# Should show all 61 migrations as "Applied"
```

---

## Daily Workflow

### Making a schema change

```bash
# 1. Create a new migration file with a descriptive name
supabase migration new add_user_display_name
# Creates: supabase/migrations/<timestamp>_add_user_display_name.sql

# 2. Edit the file with your SQL
vim supabase/migrations/<timestamp>_add_user_display_name.sql

# 3. Apply locally (if you have a local Supabase running)
supabase db reset   # resets local DB and replays all migrations
# OR
supabase db push    # applies pending migrations to linked remote

# 4. Test your changes against the app

# 5. Commit the migration file
git add supabase/migrations/<timestamp>_add_user_display_name.sql
git commit -m "feat(db): add user_display_name column"

# 6. Open a PR, get review, merge

# 7. After merge, deploy to production
supabase db push --linked
```

### Refreshing the Prisma client types

After applying migrations, refresh Prisma's type definitions so the
NestJS backend can type-check the new schema:

```bash
cd server
# Pull the live schema into Prisma's schema.prisma
prisma db pull

# Regenerate the client
prisma generate
```

**Never run `prisma migrate dev` or `prisma migrate deploy`** — those
would create a `_prisma_migrations` table and conflict with Supabase's
`supabase_migrations.schema_migrations`.

---

## Migration File Naming

Supabase CLI expects: `<YYYYMMDDHHMMSS>_<snake_case_name>.sql`

Examples:
- `20260618000000_security_force_rls_fix_storage_drop_legacy_views.sql`
- `20260618010000_backfill_orphan_auth_users.sql`
- `20260617170900_drop_redundant_duplicate_indexes.sql`

The timestamp is the migration version. Once applied to any environment,
**never edit or rename a migration file** — create a new one to undo or
change behavior.

---

## Backfill Migrations (Data Changes)

Schema migrations change structure (DDL). Backfill migrations change
data (DML). Both go in `supabase/migrations/` with the same naming
convention.

For backfills:

1. **Always use `ON CONFLICT DO NOTHING`** or `ON CONFLICT DO UPDATE` —
   backfills must be idempotent so they can be safely re-run.
2. **Test on staging first** — backfills can be slow on large tables.
   Consider batching with `LIMIT` and `OFFSET` if row count > 100k.
3. **Include a verification query** as a comment at the bottom of the
   file showing what the expected state looks like after application.

Example:

```sql
-- Backfill: set default preferredLanguage for existing users
UPDATE public."User"
SET "preferredLanguage" = 'en'
WHERE "preferredLanguage" IS NULL;

-- Verification:
-- SELECT COUNT(*) FROM public."User" WHERE "preferredLanguage" IS NULL;
-- Expected: 0
```

---

## Dangerous Operations

The following require extra review and a `-- deprecated` or `-- safe`
comment in the SQL:

| Operation | Risk | Required comment |
|---|---|---|
| `DROP TABLE` | High | `-- deprecated: <reason>` |
| `DROP COLUMN` | High | `-- deprecated: <reason>` |
| `DROP INDEX` | Medium | `-- safe: <reason>` or `-- deprecated: <reason>` |
| `ALTER COLUMN type` | Medium | Review for data truncation risk |
| `TRUNCATE` | Critical | Avoid in migrations; use a backfill + delete instead |

---

## Rollback Strategy

Supabase migrations are forward-only. To "roll back" a migration:

1. **Create a new migration** that reverses the change
   (e.g., `DROP COLUMN` → `ADD COLUMN` with the old definition)
2. **Apply via `supabase db push`**
3. **Never delete or edit the original migration file** — the history
   must remain accurate for disaster recovery

For data loss scenarios, restore from the daily Supabase backup
(Storage → Backups in the dashboard) before applying the reverse
migration.

---

## Pre-Deployment Checklist

Before merging any migration PR:

- [ ] Migration file follows naming convention (`<timestamp>_<name>.sql`)
- [ ] SQL is idempotent (`IF EXISTS`, `IF NOT EXISTS`, `ON CONFLICT`)
- [ ] No `DROP` without `-- deprecated` or `-- safe` comment
- [ ] Tested locally with `supabase db reset`
- [ ] Prisma client regenerated (`prisma db pull && prisma generate`)
- [ ] Backend tests pass (`bun test`)
- [ ] Frontend builds without type errors
- [ ] PR description explains the change and links to the issue/ticket

---

## Current State (as of 2026-06-18)

- **61 migrations** in `supabase/migrations/`
- **83 tables** in `public` schema (80 PascalCase + 3 lowercase Graph V2.1)
- **225 RLS policies** — all tables have RLS enabled AND forced
- **19 functions** — all have `search_path` pinned
- **8 triggers** — all enabled
- **0 invalid foreign keys**
- **0 orphan auth users** (after 2026-06-18 backfill)
- **1 intentional seed user** (`demo@kinrel.app`, no auth.users entry, dev/test only)

The archived Prisma migrations live in `server/prisma/_archive_pre_supabase_cli/`
for historical reference. Do not add new files there.
