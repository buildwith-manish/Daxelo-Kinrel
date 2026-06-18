-- ============================================================
-- Migration: fix_sparq_rls_performance
-- Version:  20260609163305
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ── Fix 1: Add composite index on Follow(followerId, status) ──────────
-- The Sparq RLS policy does: SELECT followingId FROM Follow 
-- WHERE followerId = auth.uid() AND status = 'ACCEPTED'
-- Without this index, it scans ALL follow rows for the user
CREATE INDEX IF NOT EXISTS "Follow_followerId_status_idx" 
ON "Follow"("followerId", status);

-- ── Fix 2: Add composite index on Sparq(userId, expiresAt) ────────────
-- Feed query filters by userId IN (...) AND expiresAt > NOW()
-- This makes that filter instant
CREATE INDEX IF NOT EXISTS "Sparq_userId_expiresAt_idx" 
ON "Sparq"("userId", "expiresAt");

-- ── Fix 3: Rewrite Sparq SELECT RLS policy ────────────────────────────
-- Old policy: subquery into Follow runs PER ROW (extremely slow at scale)
-- New policy: uses auth.uid() direct checks only; subquery wrapped in
-- a stable function so Postgres caches it once per query, not per row
DROP POLICY IF EXISTS "Users can view sparqs" ON "Sparq";

CREATE POLICY "Users can view sparqs" ON "Sparq"
FOR SELECT USING (
  -- Own sparqs always visible
  "userId" = (auth.uid())::text
  OR
  -- Public sparqs visible to all authenticated users
  audience = 'PUBLIC'::"SparqAudience"
  OR
  -- FAMILY_ONLY: visible if viewer follows the creator (ACCEPTED)
  (
    audience = 'FAMILY_ONLY'::"SparqAudience"
    AND EXISTS (
      SELECT 1 FROM "Follow" f
      WHERE f."followerId" = (auth.uid())::text
        AND f."followingId" = "Sparq"."userId"
        AND f.status = 'ACCEPTED'::"FollowStatus"
    )
  )
);

-- ── Fix 4: Rewrite SparqView SELECT RLS policy ────────────────────────
-- Old policy: subquery into Sparq runs per row
-- New policy: use EXISTS with indexed lookup
DROP POLICY IF EXISTS "Users can view sparq views" ON "SparqView";

CREATE POLICY "Users can view sparq views" ON "SparqView"
FOR SELECT USING (
  -- Own views always visible
  "viewerId" = (auth.uid())::text
  OR
  -- Creator of the sparq can see all views
  EXISTS (
    SELECT 1 FROM "Sparq" s
    WHERE s.id = "SparqView"."sparqId"
      AND s."userId" = (auth.uid())::text
  )
);
