-- ============================================================
-- Migration: fix_create_family_rls_deadlock
-- Version:  20260609044724
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- FIX 1: Person INSERT — allow if already a member OR if they own the Family (creation flow)
DROP POLICY IF EXISTS "Members can insert persons in their families" ON public."Person";

CREATE POLICY "Members can insert persons in their families"
ON public."Person"
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

-- FIX 2: FamilyMember — replace circular ALL policy with proper SELECT
-- so new users can insert themselves during family creation
DROP POLICY IF EXISTS "Family members see own family" ON public."FamilyMember";

CREATE POLICY "Family members can view own family members"
ON public."FamilyMember"
FOR SELECT
USING (
  "familyId" IN (SELECT get_my_family_ids())
  OR "userId" = (auth.uid())::text
);
