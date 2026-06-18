-- ============================================================
-- Migration: add_family_insert_policy
-- Version:  20260612021318
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- Restore Family INSERT policy (was dropped along with the recursive duplicate set).
-- Any authenticated user can create a new family; ownership is established via createdBy
-- and the subsequent FamilyMember row.
CREATE POLICY "Family insert policy"
  ON "Family" FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);
