-- ============================================================
-- Migration: fix_familymember_rls_infinite_recursion
-- Version:  20260612020828
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- Drop the buggy, recursive duplicate policies on FamilyMember.
-- These directly query "FamilyMember" from within a "FamilyMember" policy
-- without going through the SECURITY DEFINER is_family_admin() function,
-- causing "infinite recursion detected in policy for relation FamilyMember" (42P17).
--
-- The remaining "FamilyMember ... policy" set (select/insert/update/delete) already
-- covers all the same access patterns safely via is_family_admin() (SECURITY DEFINER)
-- and the Family.createdBy escape hatch for newly created families.

DROP POLICY IF EXISTS "family_member_select" ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_insert" ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_update" ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_delete" ON "FamilyMember";
