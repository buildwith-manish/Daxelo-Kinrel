-- ============================================================
-- Migration: enable_pgtrgm_and_gin_indexes
-- Version:  20260609105800
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Enable pg_trgm for fuzzy/trigram search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN trigram indexes for fast ILIKE / similarity search
CREATE INDEX IF NOT EXISTS "Person_name_trgm_idx"
  ON "Person" USING GIN ("name" gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "User_username_trgm_idx"
  ON "User" USING GIN ("username" gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "User_name_trgm_idx"
  ON "User" USING GIN ("name" gin_trgm_ops);
