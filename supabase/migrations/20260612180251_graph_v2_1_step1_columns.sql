-- ============================================================
-- Migration: graph_v2_1_step1_columns
-- Version:  20260612180251
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- 1. valid_from / valid_to on Relationship
ALTER TABLE "Relationship"
  ADD COLUMN IF NOT EXISTS valid_from TIMESTAMPTZ DEFAULT now();
ALTER TABLE "Relationship"
  ADD COLUMN IF NOT EXISTS valid_to TIMESTAMPTZ DEFAULT NULL;

-- 2. location columns on Person
ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS location_name TEXT;

-- 3. visibility on Person
ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public'
  CHECK (visibility IN ('public', 'family_only', 'private'));

-- 4. is_private on Relationship
ALTER TABLE "Relationship"
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT false;
