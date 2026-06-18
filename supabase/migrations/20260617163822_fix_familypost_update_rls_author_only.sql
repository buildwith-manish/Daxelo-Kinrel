-- ============================================================
-- Migration: fix_familypost_update_rls_author_only
-- Version:  20260617163822
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 5: FamilyPost UPDATE policy — restrict to author only
-- Old policy allowed any family member to update any post.
-- Fix: only the post author or family admins can update.
-- ============================================================

DROP POLICY IF EXISTS "Members can update family posts" ON "FamilyPost";

CREATE POLICY "Authors and admins can update family posts"
  ON "FamilyPost" FOR UPDATE
  USING (
    "authorId" = auth.uid()::text
    OR "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );
