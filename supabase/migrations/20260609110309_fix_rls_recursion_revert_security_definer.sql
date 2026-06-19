-- ============================================================
-- Migration: fix_rls_recursion_revert_security_definer
-- Version:  20260609110309
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ================================================================
-- ROOT CAUSE: get_my_family_ids() and is_family_admin() were switched
-- to SECURITY INVOKER, causing infinite RLS recursion:
--
--   FamilyMember SELECT policy → calls get_my_family_ids()
--   get_my_family_ids() queries FamilyMember (as current user)
--   → triggers FamilyMember SELECT policy again → LOOP → stack overflow
--
-- FIX: Restore SECURITY DEFINER so the function runs as postgres
-- (bypassing RLS), breaking the recursion. Keep fixed search_path
-- and anon EXECUTE revoked for security.
-- ================================================================

-- 1. Restore get_my_family_ids as SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.get_my_family_ids()
  RETURNS SETOF text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public
AS $$
  SELECT "familyId" FROM "FamilyMember" WHERE "userId" = (auth.uid())::text;
$$;

-- 2. Restore is_family_admin as SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.is_family_admin(p_family_id text)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id
      AND "userId" = (auth.uid())::text
      AND role IN ('owner', 'admin')
  );
$$;

-- 3. Keep anon EXECUTE revoked
REVOKE EXECUTE ON FUNCTION public.get_my_family_ids() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_family_admin(text) FROM anon;

-- 4. Fix FamilyMember SELECT policy: remove the redundant get_my_family_ids()
-- call (userId = auth.uid() already covers it, and calling it from FamilyMember
-- is the loop trigger even with SECURITY DEFINER in edge cases)
DROP POLICY IF EXISTS "FamilyMember select policy" ON "FamilyMember";
CREATE POLICY "FamilyMember select policy"
  ON "FamilyMember" FOR SELECT
  USING (
    -- User is this member
    "userId" = (auth.uid())::text
    OR
    -- User is the creator of the family
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = (auth.uid())::text
    )
  );

-- 5. Also drop the now-redundant duplicate "Creators can view family members" policy
DROP POLICY IF EXISTS "Creators can view family members" ON "FamilyMember";

-- 6. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
