-- =============================================================================
-- Track C v2.0 — AURA Learning Engine
-- Migration 07: FamilyBehaviorProfile (materialized, versioned)
-- =============================================================================
-- Implements Section 5.6 of the FINAL v2.0 spec.
-- ADR-002: Materialized statistical profile (not a trained ML model) — sub-50ms
-- inference reads, fully auditable, sample-size aware via confidenceScore.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."FamilyBehaviorProfile" (
  "id"                          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"                    TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "version"                     INTEGER NOT NULL DEFAULT 1,
  "computedAt"                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Reminder preferences (learned)
  "preferredReminderLeadHours"  JSONB NOT NULL DEFAULT '{"decision":24,"meeting":48,"event":72}'::JSONB,
  "reminderActionRate"          JSONB NOT NULL DEFAULT '{"6h":0.0,"12h":0.0,"24h":0.0}'::JSONB,

  -- Scheduling preferences (learned)
  "preferredWeekdayDistribution" JSONB NOT NULL DEFAULT '{"mon":0.14,"tue":0.14,"wed":0.14,"thu":0.14,"fri":0.14,"sat":0.15,"sun":0.15}'::JSONB,
  "preferredTimeOfDayBuckets"   JSONB NOT NULL DEFAULT '{"morning":0.25,"afternoon":0.25,"evening":0.25,"night":0.25}'::JSONB,

  -- Elder inclusion
  "elderAutoIncludeThreshold"   NUMERIC(4,3) NOT NULL DEFAULT 0.600,

  -- AI suggestion acceptance
  "insightAcceptRateByKind"     JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- Decision patterns
  "averageDecisionDurationHours" NUMERIC(10,2),
  "typicalQuorumMet"            BOOLEAN,

  "sampleSize"                  INTEGER NOT NULL DEFAULT 0,
  "confidenceScore"             NUMERIC(4,3) NOT NULL DEFAULT 0.000,

  "createdAt"                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "FamilyBehaviorProfile_familyId_unique" UNIQUE ("familyId")
);

CREATE INDEX IF NOT EXISTS "FamilyBehaviorProfile_familyId_idx"      ON public."FamilyBehaviorProfile"("familyId");
CREATE INDEX IF NOT EXISTS "FamilyBehaviorProfile_version_idx"       ON public."FamilyBehaviorProfile"("familyId", "version");

DROP TRIGGER IF EXISTS trg_trackc_behavior_profile_updated_at ON public."FamilyBehaviorProfile";
CREATE TRIGGER trg_trackc_behavior_profile_updated_at
  BEFORE UPDATE ON public."FamilyBehaviorProfile"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- HISTORY TABLE: FamilyBehaviorProfileHistory
-- Retains previous profile versions for 90 days (Section 9.5).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyBehaviorProfileHistory" (
  "id"            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"      TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "version"       INTEGER NOT NULL,
  "snapshot"      JSONB NOT NULL,
  "computedAt"    TIMESTAMPTZ NOT NULL,
  "archivedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "FamilyBehaviorProfileHistory_familyId_idx" ON public."FamilyBehaviorProfileHistory"("familyId", "version");

GRANT SELECT ON public."FamilyBehaviorProfile"        TO anon, authenticated;
GRANT SELECT ON public."FamilyBehaviorProfileHistory" TO anon, authenticated;

COMMENT ON TABLE public."FamilyBehaviorProfile"        IS 'Track C v2.0: AURA Learning Engine materialized per-family profile. Sub-50ms inference. ADR-002.';
COMMENT ON TABLE public."FamilyBehaviorProfileHistory" IS 'Track C v2.0: Retained profile versions (90-day purge).';
