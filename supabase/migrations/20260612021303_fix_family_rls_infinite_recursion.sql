-- ============================================================
-- Migration: fix_family_rls_infinite_recursion
-- Version:  20260612021303
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- Same issue as FamilyMember: duplicate ad-hoc policies on "Family" directly
-- query "FamilyMember" (and vice versa), creating a cross-table recursive
-- RLS cycle -> "infinite recursion detected in policy for relation Family" (42P17).
--
-- The remaining "Family ... policy" set already covers all cases safely via
-- get_my_family_ids() / is_family_admin() (both SECURITY DEFINER) and createdBy.

DROP POLICY IF EXISTS "family_select" ON "Family";
DROP POLICY IF EXISTS "family_insert" ON "Family";
DROP POLICY IF EXISTS "family_update" ON "Family";
DROP POLICY IF EXISTS "family_delete" ON "Family";
