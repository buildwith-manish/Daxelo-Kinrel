-- ============================================================
-- Migration: fix_person_rls_recursion
-- Version:  20260621050000
-- Source:   graph_blank_fix_report (1).md — Fix #5
-- ============================================================
--
-- ROOT CAUSE:
-- The Person table's SELECT policy queries FamilyMember to check
-- membership. FamilyMember's SELECT policy queries Person (via
-- get_my_family_ids() which is SECURITY DEFINER, so it doesn't
-- recurse). However, the Person policy's inline subquery:
--
--   "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)
--
-- triggers FamilyMember's SELECT policy, which in turn may reference
-- Person indirectly through other policies, causing PostgreSQL to
-- detect an infinite recursion and return an error/timeout.
--
-- SOLUTION:
-- Create a SECURITY DEFINER function check_user_family_access() that
-- bypasses RLS entirely (runs as the postgres/superuser role). Replace
-- the inline subquery in Person's SELECT policy with a call to this
-- function. This breaks the recursive chain because the function
-- executes with elevated privileges and does NOT trigger RLS on
-- FamilyMember.
--
-- This mirrors the approach already used for FamilyMember and Family
-- tables in migration 20260609052508_fix_infinite_recursion_rls.sql.
-- ============================================================

-- Step 1: Create the SECURITY DEFINER helper function
-- This function checks if a user is a member of a family WITHOUT
-- triggering RLS on FamilyMember (because it runs as SECURITY DEFINER).
CREATE OR REPLACE FUNCTION public.check_user_family_access(
  p_family_id text,
  p_user_id text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public."FamilyMember"
    WHERE "familyId" = p_family_id
      AND "userId" = p_user_id
      AND "deletedAt" IS NULL
  );
$$;

-- Grant execute to authenticated users (anon can't access any family data)
GRANT EXECUTE ON FUNCTION public.check_user_family_access(text, text) TO authenticated;

-- Step 2: Drop the existing Person SELECT policy that has the recursive subquery
DROP POLICY IF EXISTS "person_select" ON public."Person";

-- Step 3: Recreate the Person SELECT policy using the non-recursive function
CREATE POLICY "person_select"
  ON public."Person" FOR SELECT
  USING (
    (
      -- Use SECURITY DEFINER function — bypasses RLS, no recursion
      public.check_user_family_access("familyId", auth.uid()::text)
      OR
      -- Fallback: family creator always has access
      "familyId" IN (
        SELECT "id" FROM public."Family"
        WHERE "createdBy" = auth.uid()::text
        AND "deletedAt" IS NULL
      )
    )
    AND (
      "deletedAt" IS NULL
      OR "deletedAt" IS NOT NULL
    )
  );

-- Step 4: Also fix the Relationship table's SELECT policy if it has
-- the same recursive pattern. Relationship queries often check
-- FamilyMember membership, which can recurse back through Person.
DROP POLICY IF EXISTS "relationship_select" ON public."Relationship";
DROP POLICY IF EXISTS "Members can view relationships" ON public."Relationship";

CREATE POLICY "relationship_select"
  ON public."Relationship" FOR SELECT
  USING (
    -- Use the same SECURITY DEFINER function — no recursion
    public.check_user_family_access("familyId", auth.uid()::text)
    OR
    "familyId" IN (
      SELECT "id" FROM public."Family"
      WHERE "createdBy" = auth.uid()::text
      AND "deletedAt" IS NULL
    )
  );

-- Step 5: Add a comment for documentation
COMMENT ON FUNCTION public.check_user_family_access(text, text) IS
  'SECURITY DEFINER: Checks if a user is a member of a family without triggering RLS recursion. Used by Person and Relationship SELECT policies.';
