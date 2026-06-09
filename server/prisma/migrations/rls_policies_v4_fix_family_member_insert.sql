-- ============================================================
-- DAXELO KINREL — Row Level Security Policies v4
-- Fix: FamilyMember chicken-and-egg INSERT problem
-- Fix: Family SELECT access for createdBy users
-- Run these in Supabase SQL Editor
-- ============================================================
--
-- Problem: When a user creates a new family, the FamilyMember
-- INSERT RLS requires the user to already be a member of the
-- family — which is impossible for a brand-new family.
-- This is a chicken-and-egg problem.
--
-- Solution:
-- 1. Allow FamilyMember INSERT when the user is the createdBy
--    of the family (they just created it, so they should be admin)
-- 2. Add Family SELECT policy for createdBy users (so creators
--    can see their own families even before FamilyMember row exists)
--
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Drop old restrictive FamilyMember INSERT policies
-- ────────────────────────────────────────────────────────────

-- Drop the v2 policy that requires user to already be a member
DROP POLICY IF EXISTS "Owners and admins can add family members" ON "FamilyMember";

-- ────────────────────────────────────────────────────────────
-- 2. New FamilyMember INSERT policy — allows creators to add themselves
-- ────────────────────────────────────────────────────────────

-- Users can add members to a family if:
-- (a) They are already an owner/admin of the family, OR
-- (b) They are the creator of the family (createdBy matches their user ID)
--     This handles the chicken-and-egg case for new families.
CREATE POLICY "Owners admins and creators can add family members"
  ON "FamilyMember" FOR INSERT
  WITH CHECK (
    -- Case 1: User is already an owner/admin of this family
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
    OR
    -- Case 2: User is the creator of this family (new family scenario)
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 3. New Family SELECT policy — creators can see their own families
-- ────────────────────────────────────────────────────────────

-- Users can see families where:
-- (a) They are a FamilyMember (existing policies cover this), OR
-- (b) They are the creator (createdBy matches their user ID)
--     This ensures creators can see their families even if
--     the FamilyMember insert hasn't happened yet.
CREATE POLICY "Creators can view their families"
  ON "Family" FOR SELECT
  USING (
    "createdBy" = auth.uid()::text
  );

-- ────────────────────────────────────────────────────────────
-- 4. New Family UPDATE policy — creators can update their families
-- ────────────────────────────────────────────────────────────

-- Creators can update their families even if they don't have
-- a FamilyMember row yet (covers the case where FamilyMember
-- insert failed due to the old RLS policy).
CREATE POLICY "Creators can update their families"
  ON "Family" FOR UPDATE
  USING (
    "createdBy" = auth.uid()::text
  )
  WITH CHECK (
    "createdBy" = auth.uid()::text
  );

-- ────────────────────────────────────────────────────────────
-- 5. New FamilyMember SELECT policy — creators can see members
-- ────────────────────────────────────────────────────────────

-- Creators can view members of families they created.
CREATE POLICY "Creators can view family members"
  ON "FamilyMember" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 6. Person INSERT policy — creators can add persons to their families
-- ────────────────────────────────────────────────────────────

-- Creators can add persons to families they created, even if
-- the FamilyMember row doesn't exist yet.
CREATE POLICY "Creators can create persons in their families"
  ON "Person" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 7. Person SELECT policy — creators can see persons in their families
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Creators can view persons in their families"
  ON "Person" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 8. Person UPDATE policy — creators can update persons in their families
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Creators can update persons in their families"
  ON "Person" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 9. Relationship INSERT policy — creators can add relationships
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Creators can create relationships in their families"
  ON "Relationship" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 10. Relationship SELECT policy — creators can view relationships
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Creators can view relationships in their families"
  ON "Relationship" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 11. Reload PostgREST schema cache
-- ────────────────────────────────────────────────────────────

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Instructions:
-- 1. Go to supabase.com → your project
-- 2. Click SQL Editor
-- 3. Paste and run this entire file
-- 4. Verify in Authentication → Policies that the new policies exist
-- 5. Test: Create a new family and verify the creator can:
--    a. See the family in the list
--    b. Add themselves as a FamilyMember
--    c. Add persons to the family
--    d. Add relationships
-- ============================================================
