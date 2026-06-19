-- ============================================================
-- Migration: add_communitymember_status_column
-- Version:  20260617163901
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 8: CommunityMember — add status field (Agent-03 req #2)
-- Enables proper pending/approval flow for private communities
-- ============================================================

ALTER TABLE "CommunityMember" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'active';

CREATE INDEX IF NOT EXISTS "CommunityMember_status_idx" ON "CommunityMember"("status");
CREATE INDEX IF NOT EXISTS "CommunityMember_communityId_status_idx" ON "CommunityMember"("communityId", "status");

-- Update community member view policy to only show active members publicly
-- (pending/banned members should not be visible to everyone)
DROP POLICY IF EXISTS "Anyone can view community members" ON "CommunityMember";

CREATE POLICY "Anyone can view active community members"
  ON "CommunityMember" FOR SELECT
  USING (
    status = 'active'
    OR "userId" = auth.uid()::text  -- users can always see their own membership
    OR "communityId" IN (           -- admins can see all members
      SELECT "communityId" FROM "CommunityMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'moderator')
    )
  );
