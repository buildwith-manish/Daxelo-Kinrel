-- Migration: fix_relationship_insert_rls
-- Version:  20260623100000
--
-- ROOT CAUSE: The relationship_insert RLS policy required the user to be
-- a FamilyMember with role owner/admin/member. But the FamilyMember table
-- had 0 rows for many families (created via Flutter direct Supabase writes
-- which don't always create FamilyMember rows). This meant RLS denied
-- every Relationship INSERT — silently failing when adding members with
-- kinship.
--
-- FIX: Use check_user_family_access (SECURITY DEFINER, bypasses RLS)
-- which checks if the user exists in the FamilyMember table OR is the
-- family creator. This is the same function used by the SELECT policy.
-- Also add a fallback for family creators (createdBy = auth.uid()).

DROP POLICY IF EXISTS "relationship_insert" ON public."Relationship";

CREATE POLICY "relationship_insert"
  ON public."Relationship" FOR INSERT
  WITH CHECK (
    public.check_user_family_access("familyId", auth.uid()::text)
    OR "familyId" IN (
      SELECT "id" FROM public."Family"
      WHERE "createdBy" = auth.uid()::text
      AND "deletedAt" IS NULL
    )
  );
