-- ============================================================
-- Migration: fix_family_member_rls_recursion
-- Version:  20260604060220
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Step 1: Create a helper function that bypasses RLS to get family IDs for the current user
CREATE OR REPLACE FUNCTION get_my_family_ids()
RETURNS SETOF text
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT "familyId" FROM "FamilyMember" WHERE "userId" = (auth.uid())::text;
$$;

-- Step 2: Drop the recursive policy
DROP POLICY IF EXISTS "Family members see own family" ON "FamilyMember";

-- Step 3: Recreate it using the helper function (no more recursion)
CREATE POLICY "Family members see own family"
ON "FamilyMember"
FOR ALL
USING (
  "familyId" IN (SELECT get_my_family_ids())
);
