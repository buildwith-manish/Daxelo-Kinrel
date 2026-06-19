-- ============================================================
-- Migration: add_family_invite_social_columns
-- Version:  20260609105752
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Add missing FamilyInvite columns from social system migration
ALTER TABLE "FamilyInvite" ADD COLUMN IF NOT EXISTS "creatorId" TEXT;
ALTER TABLE "FamilyInvite" ADD COLUMN IF NOT EXISTS "active" BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS "FamilyInvite_creatorId_idx" ON "FamilyInvite"("creatorId");

ALTER TABLE "FamilyInvite"
  DROP CONSTRAINT IF EXISTS "FamilyInvite_creatorId_fkey";

ALTER TABLE "FamilyInvite"
  ADD CONSTRAINT "FamilyInvite_creatorId_fkey"
  FOREIGN KEY ("creatorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
