-- ============================================================
-- Migration: add_missing_performance_indexes
-- Version:  20260608184736
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Family soft-delete and createdBy indexes
CREATE INDEX IF NOT EXISTS "Family_deletedAt_idx" ON public."Family" ("deletedAt");
CREATE INDEX IF NOT EXISTS "Family_createdBy_idx" ON public."Family" ("createdBy");

-- FamilyInvite familyId+status composite index
CREATE INDEX IF NOT EXISTS "FamilyInvite_familyId_status_idx" ON public."FamilyInvite" ("familyId", status);
