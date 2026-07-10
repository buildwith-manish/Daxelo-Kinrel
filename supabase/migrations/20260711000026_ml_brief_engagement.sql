-- =============================================================================
-- ML spec item #5 — PULSE brief item engagement tracking
-- =============================================================================
-- Records when a user opens, taps, or dismisses a brief item. This signal is
-- the prerequisite for learning personalized closeness weights (item #5).
--
-- Without this signal, the closeness formula in pulse/closeness.ts uses
-- hardcoded weights (0.30/0.15/0.35/0.10/0.10) that are reasonable guesses
-- but not learned from anything. Once enough engagement data accumulates,
-- we can train a logistic regression mapping the 5 closeness signals to
-- engagement probability and replace the fixed weights with learned ones.
--
-- Design:
--   - One row per (user, brief, brief_item) engagement event. We don't
--     aggregate because we need the per-item signal scores at training time
--     (they're embedded in the row for reproducibility — even if the
--     closeness.ts formula changes later, we can re-train from historical
--     signal snapshots).
--   - The 5 signal scores are stored as a JSON object so we don't need a
--     schema migration when the signal names change.
--   - `engaged` is a boolean: did the user open/tap the item? `dismissed`
--     is also tracked because dismissals are a negative signal.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."BriefEngagement" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  "briefDate" DATE NOT NULL,
  -- The brief item's identifier within the brief (itemType + a stable hash
  -- of the target entity ID). We don't use the BriefItem row ID because
  -- briefs are regenerated daily and old BriefItem rows are pruned.
  "itemKey" TEXT NOT NULL,
  "itemType" TEXT NOT NULL,
  "targetPersonId" TEXT,
  -- The 5 closeness signal scores at the time the item was shown, snapshotted
  -- for training reproducibility.
  "signalScores" TEXT NOT NULL,
  -- What the user did: 'opened' | 'tapped' | 'dismissed' | 'snoozed' | 'skipped'
  "engagementType" TEXT NOT NULL,
  -- Convenience booleans derived from engagementType for fast aggregation
  "engaged" BOOLEAN NOT NULL DEFAULT false,
  "dismissed" BOOLEAN NOT NULL DEFAULT false,
  "engagedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_brief_engagement_user_date"
  ON public."BriefEngagement" ("userId", "briefDate" DESC);
CREATE INDEX IF NOT EXISTS "idx_brief_engagement_family_date"
  ON public."BriefEngagement" ("familyId", "briefDate" DESC);
CREATE INDEX IF NOT EXISTS "idx_brief_engagement_engaged"
  ON public."BriefEngagement" ("engaged", "dismissed");

-- RLS: users can read their OWN engagements only. service_role can read all
-- + write all (engagements are recorded server-side via the brief API).
ALTER TABLE public."BriefEngagement" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "brief_engagement_select_own" ON public."BriefEngagement";
CREATE POLICY "brief_engagement_select_own" ON public."BriefEngagement"
  FOR SELECT USING (
    auth.uid()::text = "userId"
    OR current_setting('role', true) = 'service_role'
  );

DROP POLICY IF EXISTS "brief_engagement_insert" ON public."BriefEngagement";
CREATE POLICY "brief_engagement_insert" ON public."BriefEngagement"
  FOR INSERT TO service_role WITH CHECK (true);

DROP POLICY IF EXISTS "brief_engagement_update" ON public."BriefEngagement";
CREATE POLICY "brief_engagement_update" ON public."BriefEngagement"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "brief_engagement_delete" ON public."BriefEngagement";
CREATE POLICY IF EXISTS "brief_engagement_delete" ON public."BriefEngagement"
  FOR DELETE TO service_role USING (true);

COMMENT ON TABLE public."BriefEngagement" IS 'ML spec item #5 prerequisite: Per-user brief item engagement tracking. Records open/tap/dismiss events with snapshotted closeness signal scores for training learned weights.';
