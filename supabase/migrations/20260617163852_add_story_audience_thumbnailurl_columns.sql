-- ============================================================
-- Migration: add_story_audience_thumbnailurl_columns
-- Version:  20260617163852
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 7: Story — add audience + thumbnailUrl (Agent-03 req #1)
-- ============================================================

ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "audience" TEXT NOT NULL DEFAULT 'PUBLIC';
ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "thumbnailUrl" TEXT;

CREATE INDEX IF NOT EXISTS "Story_audience_idx" ON "Story"("audience");

-- Update Story SELECT policy to respect audience
-- PUBLIC stories visible to followers, FAMILY_ONLY to family members
DROP POLICY IF EXISTS "Users can view stories" ON "Story";

CREATE POLICY "Users can view stories"
  ON "Story" FOR SELECT
  USING (
    "userId" = auth.uid()::text
    OR (
      audience = 'PUBLIC'
      AND "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
      )
    )
    OR (
      audience = 'FAMILY_ONLY'
      AND "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
      )
    )
    OR (
      -- Also allow viewing own-family stories if no familyId (personal stories)
      "familyId" IS NULL AND "userId" = auth.uid()::text
    )
  );
