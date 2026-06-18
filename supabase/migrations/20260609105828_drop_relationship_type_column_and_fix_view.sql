-- ============================================================
-- Migration: drop_relationship_type_column_and_fix_view
-- Version:  20260609105828
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Drop the view that references the old "type" column, then drop the column, then recreate view
DROP VIEW IF EXISTS "relationships";

ALTER TABLE "Relationship" DROP COLUMN IF EXISTS "type";

-- Recreate relationships view without legacy "type" column
CREATE VIEW "relationships" AS
  SELECT id, "familyId", "fromPersonId", "toPersonId",
         "relationshipKey", "relationshipType", direction,
         "isActive", label, "verifiedAt", "createdAt", "updatedAt"
  FROM "Relationship";
