-- ============================================================
-- Migration: fix_infinite_recursion_rls
-- Version:  20260609052508
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX: infinite recursion in FamilyMember + Family policies
-- Root cause: FamilyMember SELECT policies call get_my_family_ids()
-- which queries FamilyMember → triggers the same SELECT policy → loop
-- Also: Family SELECT policy queries FamilyMember → FamilyMember SELECT
-- policy queries Family → second loop
-- Solution: use SECURITY DEFINER function that bypasses RLS
-- ============================================================

-- Step 1: Drop ALL recursive policies
DROP POLICY IF EXISTS "Family members can view own family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Users can view family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Creators can view family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Admins can remove family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Admins can update family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Owners admins and creators can add family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Family members can read family data" ON "Family";
DROP POLICY IF EXISTS "Only owners can delete families" ON "Family";
DROP POLICY IF EXISTS "Only owners and admins can update family settings" ON "Family";

-- Step 2: Replace get_my_family_ids with SECURITY DEFINER (bypasses RLS, no recursion)
CREATE OR REPLACE FUNCTION get_my_family_ids()
RETURNS SETOF text
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT "familyId" FROM "FamilyMember" WHERE "userId" = (auth.uid())::text;
$$;

-- Step 3: Helper function for admin check (SECURITY DEFINER, no recursion)
CREATE OR REPLACE FUNCTION is_family_admin(p_family_id text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id
      AND "userId" = (auth.uid())::text
      AND role IN ('owner', 'admin')
  );
$$;

-- Step 4: Recreate FamilyMember policies WITHOUT self-referencing queries
-- SELECT: user can see their own rows OR rows in families they created
CREATE POLICY "FamilyMember select policy"
  ON "FamilyMember" FOR SELECT
  USING (
    "userId" = (auth.uid())::text
    OR "familyId" IN (
      SELECT id FROM "Family" WHERE "createdBy" = (auth.uid())::text
    )
    OR "familyId" IN (SELECT get_my_family_ids())
  );

-- INSERT: creator of family OR already admin (via SECURITY DEFINER, safe)
CREATE POLICY "FamilyMember insert policy"
  ON "FamilyMember" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT id FROM "Family" WHERE "createdBy" = (auth.uid())::text
    )
    OR is_family_admin("familyId")
    OR "userId" = (auth.uid())::text  -- allow self-insert via invite
  );

-- UPDATE: only admins (via SECURITY DEFINER)
CREATE POLICY "FamilyMember update policy"
  ON "FamilyMember" FOR UPDATE
  USING (is_family_admin("familyId"));

-- DELETE: only admins (via SECURITY DEFINER)
CREATE POLICY "FamilyMember delete policy"
  ON "FamilyMember" FOR DELETE
  USING (is_family_admin("familyId"));

-- Step 5: Recreate Family policies using get_my_family_ids (now SECURITY DEFINER)
CREATE POLICY "Family select policy"
  ON "Family" FOR SELECT
  USING (
    id IN (SELECT get_my_family_ids())
    OR "createdBy" = (auth.uid())::text
    OR "privacyMode" = 'public'
  );

CREATE POLICY "Family update policy"
  ON "Family" FOR UPDATE
  USING (
    is_family_admin(id)
    OR "createdBy" = (auth.uid())::text
  );

CREATE POLICY "Family delete policy"
  ON "Family" FOR DELETE
  USING (is_family_admin(id));

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
