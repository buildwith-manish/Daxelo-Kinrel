-- =============================================================================
-- ML spec item #7 — Per-user engagement profile (generalizes Track C's
-- reminderActionRate to be usable app-wide).
-- =============================================================================
-- Tracks which hours-of-day and days-of-week a user actually opens/acts on
-- notifications. Used by notifications.scheduler.ts to send non-Track-C
-- reminders (e.g. birthdays) at the user's typical engagement hour instead
-- of a fixed 8 AM IST for everyone.
--
-- The underlying data-collection pattern already exists in Track C
-- (aura-learning/learning.signal-ingestor.ts records `reminder_action`
-- signals per family). This table is the per-user generalization — the
-- scheduler reads it directly without going through the family-scoped
-- FamilyBehaviorProfile.
--
-- Design notes:
--   - One row per user (no family scoping — engagement timing is a personal
--     pattern, not family-specific).
--   - Hours are stored as a 24-element array (index 0 = midnight, 23 = 11pm)
--     of counts. Days-of-week is a 7-element array (index 0 = Sunday).
--   - We store raw counts (not normalized probabilities) so we can compute
--     a meaningful "best hour" even with small samples. Normalization
--     happens at read time.
--   - A `lastUpdatedAt` timestamp lets the scheduler fall back to the
--     default hour if the profile is stale (no engagement in 30+ days).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."UserEngagementProfile" (
  "userId" TEXT PRIMARY KEY,
  -- 24-element JSON array of integer counts. Index 0 = 00:00-00:59, ..., 23 = 23:00-23:59.
  -- Stored in the user's LOCAL timezone (recorded at signal-ingest time).
  "hourHistogram" TEXT NOT NULL DEFAULT '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]',
  -- 7-element JSON array of integer counts. Index 0 = Sunday, 6 = Saturday.
  "weekdayHistogram" TEXT NOT NULL DEFAULT '[0,0,0,0,0,0,0]',
  -- Total number of engagement signals recorded. Used to compute confidence
  -- (we won't shift a user's send time based on <10 samples).
  "totalSamples" INTEGER NOT NULL DEFAULT 0,
  -- Most-recent signal timestamp. Used to detect stale profiles.
  "lastEngagedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_user_engagement_updated"
  ON public."UserEngagementProfile" ("updatedAt");

-- RLS: users can read their OWN profile only. service_role can read all +
-- write all (signals are recorded server-side when notifications are opened).
ALTER TABLE public."UserEngagementProfile" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_engagement_select_own" ON public."UserEngagementProfile";
CREATE POLICY "user_engagement_select_own" ON public."UserEngagementProfile"
  FOR SELECT USING (
    auth.uid()::text = "userId"
    OR current_setting('role', true) = 'service_role'
  );

DROP POLICY IF EXISTS "user_engagement_insert" ON public."UserEngagementProfile";
CREATE POLICY "user_engagement_insert" ON public."UserEngagementProfile"
  FOR INSERT TO service_role WITH CHECK (true);

DROP POLICY IF EXISTS "user_engagement_update" ON public."UserEngagementProfile";
CREATE POLICY "user_engagement_update" ON public."UserEngagementProfile"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "user_engagement_delete" ON public."UserEngagementProfile";
CREATE POLICY "user_engagement_delete" ON public."UserEngagementProfile"
  FOR DELETE TO service_role USING (true);

COMMENT ON TABLE public."UserEngagementProfile" IS 'ML spec item #7: Per-user notification engagement timing profile. Used by notifications.scheduler.ts to send reminders at the user''s typical engagement hour instead of a fixed time for everyone.';
