-- ============================================================
-- Migration: fix_create_family_remaining_rls_blockers
-- Version:  20260609044959
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- BLOCKER 1: Relationship INSERT still requires FamilyMember to exist first
-- Fix: also allow if user owns the Family (same pattern as Person fix)
DROP POLICY IF EXISTS "Members can insert relationships in their families" ON public."Relationship";

CREATE POLICY "Members can insert relationships in their families"
ON public."Relationship"
FOR INSERT
WITH CHECK (
  "familyId" IN (
    SELECT "familyId" FROM "FamilyMember" WHERE "userId" = (auth.uid())::text
  )
  OR
  "familyId" IN (
    SELECT id FROM "Family" WHERE "createdBy" = (auth.uid())::text
  )
);

-- BLOCKER 2: Family UPDATE (setting anchorPersonId after Person is created)
-- Current policy requires being owner/admin via FamilyMember — but during creation
-- the FamilyMember row may not be committed yet in the same transaction
DROP POLICY IF EXISTS "Only owners and admins can update family settings" ON public."Family";

CREATE POLICY "Only owners and admins can update family settings"
ON public."Family"
FOR UPDATE
USING (
  -- Normal case: already a member with owner/admin role
  id IN (
    SELECT "familyId" FROM "FamilyMember"
    WHERE "userId" = (auth.uid())::text
      AND role = ANY (ARRAY['owner', 'admin'])
  )
  OR
  -- Creation flow: user is the createdBy of this family
  "createdBy" = (auth.uid())::text
);

-- BLOCKER 3: PersonPrivacySetting INSERT requires FamilyMember — same deadlock
-- Fix: also allow if the person's familyId is owned by the user
DROP POLICY IF EXISTS "Members can create privacy settings" ON public."PersonPrivacySetting";

CREATE POLICY "Members can create privacy settings"
ON public."PersonPrivacySetting"
FOR INSERT
WITH CHECK (
  "personId" IN (
    SELECT p.id FROM "Person" p
    WHERE p."familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = (auth.uid())::text
        AND role = ANY (ARRAY['owner', 'admin', 'member'])
    )
    OR p."familyId" IN (
      SELECT id FROM "Family" WHERE "createdBy" = (auth.uid())::text
    )
  )
);
