-- =============================================================================
-- Track C v2.0 — Seed global defaults
-- =============================================================================
-- Implements migration 19 of Appendix B (seed_global_defaults.sql).
-- Seeds the FamilyBehaviorProfile defaults table (Section 9.4) and the
-- global insight accept-rate defaults used by the Learning Engine when
-- a family has zero signals (confidenceScore < 0.4).
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: GlobalLearningDefaults
-- Single-row table holding global defaults for the Learning Engine.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."GlobalLearningDefaults" (
  "id"                          TEXT PRIMARY KEY DEFAULT 'global',
  "preferredReminderLeadHours"  JSONB NOT NULL DEFAULT '{"decision":24,"meeting":48,"event":72}'::JSONB,
  "reminderActionRate"          JSONB NOT NULL DEFAULT '{"6h":0.42,"12h":0.55,"24h":0.71}'::JSONB,
  "preferredWeekdayDistribution" JSONB NOT NULL DEFAULT '{"mon":0.14,"tue":0.14,"wed":0.14,"thu":0.14,"fri":0.14,"sat":0.15,"sun":0.15}'::JSONB,
  "preferredTimeOfDayBuckets"   JSONB NOT NULL DEFAULT '{"morning":0.20,"afternoon":0.25,"evening":0.40,"night":0.15}'::JSONB,
  "elderAutoIncludeThreshold"   NUMERIC(4,3) NOT NULL DEFAULT 0.600,
  "insightAcceptRateByKind"     JSONB NOT NULL DEFAULT '{
    "decision_analysis":0.45,
    "duplicate_detection":0.55,
    "summary":0.70,
    "pros_cons":0.50,
    "smart_reminder":0.65,
    "action_items":0.60,
    "draft_minutes":0.40,
    "search_synonym":0.30
  }'::JSONB,
  "averageDecisionDurationHours" NUMERIC(10,2) NOT NULL DEFAULT 72.0,
  "minSignalsForPersonalization" INTEGER NOT NULL DEFAULT 30,
  "lowConfidenceThreshold"       NUMERIC(4,3) NOT NULL DEFAULT 0.400,
  "highConfidenceThreshold"      NUMERIC(4,3) NOT NULL DEFAULT 0.700,
  "updatedAt"                    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public."GlobalLearningDefaults" ("id") VALUES ('global')
ON CONFLICT ("id") DO NOTHING;

GRANT SELECT ON public."GlobalLearningDefaults" TO anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: AICostBudget (per-family daily token budget tracking)
-- Section 8.3: 50,000 tokens/day default per family.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."AICostBudget" (
  "id"             TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"       TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "dateUtc"        DATE NOT NULL,
  "tokensUsed"     INTEGER NOT NULL DEFAULT 0,
  "costUsd"        NUMERIC(10,4) NOT NULL DEFAULT 0,
  "budgetTokens"   INTEGER NOT NULL DEFAULT 50000,
  "circuitOpen"    BOOLEAN NOT NULL DEFAULT FALSE,
  "circuitOpenedAt" TIMESTAMPTZ,
  CONSTRAINT "AICostBudget_family_date_unique" UNIQUE ("familyId", "dateUtc")
);

CREATE INDEX IF NOT EXISTS "AICostBudget_family_date_idx" ON public."AICostBudget"("familyId", "dateUtc");

GRANT SELECT ON public."AICostBudget" TO anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: SyncWatermark (per-device per-family watermark)
-- Section 7.2: each device maintains a per-family sync_watermark.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."SyncWatermark" (
  "id"         TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"     TEXT NOT NULL,
  "familyId"   TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "deviceId"   TEXT NOT NULL,
  "watermark"  TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01T00:00:00Z',
  "updatedAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "SyncWatermark_user_family_device_unique" UNIQUE ("userId", "familyId", "deviceId")
);

CREATE INDEX IF NOT EXISTS "SyncWatermark_user_family_idx" ON public."SyncWatermark"("userId", "familyId");

GRANT SELECT, INSERT, UPDATE ON public."SyncWatermark" TO authenticated;

COMMENT ON TABLE public."GlobalLearningDefaults" IS 'Track C v2.0: Single-row table of global Learning Engine defaults (used when family confidenceScore < 0.4).';
COMMENT ON TABLE public."AICostBudget"           IS 'Track C v2.0: Per-family daily AI token budget tracking. 50,000 tokens/day default. Section 8.3.';
COMMENT ON TABLE public."SyncWatermark"          IS 'Track C v2.0: Per-device per-family delta sync watermark. Section 7.2.';
