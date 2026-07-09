-- =============================================================================
-- Track C v2.0 — AURA Intelligence
-- Migration 05: AIInsight (consolidated insights with kind discriminator)
-- =============================================================================
-- Implements Section 5.5 of the FINAL v2.0 spec.
-- ADR-003: Single AIInsight table with kind discriminator replaces the draft's
-- AISuggestion + AIAnalysis tables.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."AIInsight" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "decisionId"      TEXT REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "kind"            TEXT NOT NULL CHECK ("kind" IN (
                      'decision_analysis','duplicate_detection','summary','pros_cons',
                      'smart_reminder','action_items','draft_minutes','search_synonym'
                    )),
  "status"          TEXT NOT NULL DEFAULT 'pending' CHECK ("status" IN ('pending','presented','accepted','dismissed','stale')),
  "payload"         JSONB NOT NULL DEFAULT '{}'::JSONB,
  "modelId"         TEXT NOT NULL,
  "tokensIn"        INTEGER NOT NULL DEFAULT 0,
  "tokensOut"       INTEGER NOT NULL DEFAULT 0,
  "costUsd"         NUMERIC(10,6),
  "presentedAt"     TIMESTAMPTZ,
  "acceptedAt"      TIMESTAMPTZ,
  "dismissedAt"     TIMESTAMPTZ,
  "dismissedReason" TEXT CHECK ("dismissedReason" IN ('not_relevant','already_known','too_prescriptive','other') OR "dismissedReason" IS NULL),
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "AIInsight_familyId_kind_status_idx" ON public."AIInsight"("familyId", "kind", "status");
CREATE INDEX IF NOT EXISTS "AIInsight_decisionId_kind_idx"      ON public."AIInsight"("decisionId", "kind") WHERE "decisionId" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "AIInsight_status_createdAt_idx"     ON public."AIInsight"("status", "createdAt");
CREATE INDEX IF NOT EXISTS "AIInsight_familyId_createdAt_idx"   ON public."AIInsight"("familyId", "createdAt");

-- Monotonic updatedAt trigger
DROP TRIGGER IF EXISTS trg_trackc_ai_insight_updated_at ON public."AIInsight";
CREATE TRIGGER trg_trackc_ai_insight_updated_at
  BEFORE UPDATE ON public."AIInsight"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

GRANT SELECT ON public."AIInsight" TO anon, authenticated;
COMMENT ON TABLE public."AIInsight" IS 'Track C v2.0: Consolidated AI insight table. kind discriminator replaces draft AISuggestion+AIAnalysis. ADR-003.';
