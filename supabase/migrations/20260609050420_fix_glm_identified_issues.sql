-- ============================================================
-- Migration: fix_glm_identified_issues
-- Version:  20260609050420
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- FIX 1: Family table has BOTH photoUrl AND avatarUrl columns
-- App was likely sending photoUrl but Drift model maps to avatarUrl
-- Consolidate: make photoUrl mirror avatarUrl via a generated column or just keep both
-- For now, ensure avatarUrl is always populated when photoUrl is set (trigger)
CREATE OR REPLACE FUNCTION sync_family_photo_url()
RETURNS TRIGGER AS $$
BEGIN
  -- If avatarUrl is set but photoUrl is not, sync it
  IF NEW."avatarUrl" IS NOT NULL AND NEW."photoUrl" IS NULL THEN
    NEW."photoUrl" = NEW."avatarUrl";
  END IF;
  -- If photoUrl is set but avatarUrl is not, sync it
  IF NEW."photoUrl" IS NOT NULL AND NEW."avatarUrl" IS NULL THEN
    NEW."avatarUrl" = NEW."photoUrl";
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_family_photo_url_trigger ON public."Family";
CREATE TRIGGER sync_family_photo_url_trigger
  BEFORE INSERT OR UPDATE ON public."Family"
  FOR EACH ROW EXECUTE FUNCTION sync_family_photo_url();

-- FIX 2: Archived families = families with deletedAt IS NOT NULL
-- The Family SELECT policy only allows members to read their families
-- But archived families (soft-deleted) are filtered OUT because FamilyMember
-- rows still exist — so archived families SHOULD be readable. Policy is fine.
-- The infinite loading is because the app queries deletedAt IS NOT NULL
-- but the Drift cached query might not handle nulls correctly.
-- Add a partial index to speed up archived family queries:
CREATE INDEX IF NOT EXISTS "Family_deletedAt_notnull_idx" 
ON public."Family" ("deletedAt") 
WHERE "deletedAt" IS NOT NULL;

-- FIX 3: Family SELECT policy also needs to allow createdBy user to read
-- their own newly-created family before FamilyMember row is committed
DROP POLICY IF EXISTS "Family members can read family data" ON public."Family";

CREATE POLICY "Family members can read family data"
ON public."Family"
FOR SELECT
USING (
  id IN (
    SELECT "familyId" FROM "FamilyMember" 
    WHERE "userId" = (auth.uid())::text
  )
  OR "privacyMode" = 'public'
  OR "createdBy" = (auth.uid())::text
);
