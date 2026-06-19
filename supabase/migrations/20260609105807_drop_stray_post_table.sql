-- ============================================================
-- Migration: drop_stray_post_table
-- Version:  20260609105807
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Drop stray Post table (Prisma scaffold leftover, not in schema, 0 rows)
DROP TABLE IF EXISTS "Post";
