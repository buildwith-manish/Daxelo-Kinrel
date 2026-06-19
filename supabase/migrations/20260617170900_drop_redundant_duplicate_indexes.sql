-- ============================================================
-- Migration: drop_redundant_duplicate_indexes
-- Version:  20260617170900
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- These indexes duplicate the index already created automatically by a UNIQUE constraint
-- on the exact same columns. Dropping them removes write overhead with zero functional loss.
DROP INDEX IF EXISTS public."FamilyMember_familyId_userId_idx";
DROP INDEX IF EXISTS public."Family_familyCode_idx";
DROP INDEX IF EXISTS public."Family_kinFamilyId_idx";
DROP INDEX IF EXISTS public."Family_username_idx";
DROP INDEX IF EXISTS public.idx_graph_cache_family_member;
