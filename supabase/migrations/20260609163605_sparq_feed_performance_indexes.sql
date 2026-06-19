-- ============================================================
-- Migration: sparq_feed_performance_indexes
-- Version:  20260609163605
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- 1. Best index for the feed query: userId + expiresAt + audience
--    Covers: WHERE userId IN (...) AND expiresAt > now AND audience IN (...)
CREATE INDEX IF NOT EXISTS "Sparq_userId_expiresAt_audience_idx"
  ON public."Sparq" ("userId", "expiresAt", "audience");

-- 2. Best index for the SparqView subquery: viewerId + sparqId
--    Covers: WHERE viewerId = $userId (already checked, sparqId for join)
--    The existing viewerId_idx is single column; this covers the join better
CREATE INDEX IF NOT EXISTS "SparqView_viewerId_sparqId_idx"
  ON public."SparqView" ("viewerId", "sparqId");

-- 3. Index for Follow: followerId + status (feed needs ACCEPTED follows only)
--    Already exists as Follow_followerId_status_idx — good, nothing to add.

-- 4. Index for FamilyMember: userId is already indexed.
--    Add a partial index for faster "get all families of a user"
--    (already covered by FamilyMember_userId_familyId_idx)
