-- ============================================================
-- Migration: fix_delete_and_orphan_families
-- Version:  20260609052902
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- FIX 1: Delete policy must also allow createdBy user
DROP POLICY IF EXISTS "Family delete policy" ON "Family";

CREATE POLICY "Family delete policy"
  ON "Family" FOR DELETE
  USING (
    is_family_admin(id)
    OR "createdBy" = (auth.uid())::text
  );

-- FIX 2: Insert missing FamilyMember rows only for users that exist in User table
INSERT INTO "FamilyMember" (id, "familyId", "userId", role, "joinedAt")
SELECT 
  'fm_' || f.id,
  f.id,
  f."createdBy",
  'owner',
  f."createdAt"
FROM "Family" f
WHERE f."deletedAt" IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = f.id
  )
  AND EXISTS (
    SELECT 1 FROM "User" u WHERE u.id = f."createdBy"
  )
ON CONFLICT DO NOTHING;

-- FIX 3: Update memberCount
UPDATE "Family" f
SET "memberCount" = (
  SELECT COUNT(*) FROM "FamilyMember" fm WHERE fm."familyId" = f.id
)
WHERE f."deletedAt" IS NULL;

NOTIFY pgrst, 'reload schema';
