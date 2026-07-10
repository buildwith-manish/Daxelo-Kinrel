-- =============================================================================
-- Track C v2.0 — AURA Learning Engine
-- Migration 06: LearningSignal (lightweight event stream)
-- =============================================================================
-- Implements Section 5.6 of the FINAL v2.0 spec.
--
-- DESIGN:
--   * Pseudonymous — payload stores shapes/counts/durations, NEVER raw text or PII.
--   * Hash-partitioned later (migration 18).
--   * 365-day rolling retention (purge job in pg-boss).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."LearningSignal" (
  "id"          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"    TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "signalType"  TEXT NOT NULL CHECK ("signalType" IN (
                  'insight_accepted','insight_dismissed','reminder_acted',
                  'reminder_snoozed','reminder_dismissed','event_scheduled',
                  'elder_participated','quorum_met','deadline_extended',
                  'vote_pattern','search_performed'
                )),
  "targetType"  TEXT CHECK ("targetType" IN ('AIInsight','FamilyDecision','SmartReminder','FamilyEvent') OR "targetType" IS NULL),
  "targetId"    TEXT,
  "payload"     JSONB NOT NULL DEFAULT '{}'::JSONB,
  "occurredAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "LearningSignal_familyId_signalType_occurredAt_idx" ON public."LearningSignal"("familyId", "signalType", "occurredAt");
CREATE INDEX IF NOT EXISTS "LearningSignal_familyId_occurredAt_idx"            ON public."LearningSignal"("familyId", "occurredAt");

GRANT SELECT ON public."LearningSignal" TO anon, authenticated;
COMMENT ON TABLE public."LearningSignal" IS 'Track C v2.0: AURA Learning Engine signal stream. Pseudonymous (no raw text). 365-day rolling retention.';
