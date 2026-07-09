-- =============================================================================
-- Track C v2.0 — Decision Memory + Impact
-- Migration 09: DecisionMemory + DecisionImpact
-- =============================================================================
-- Implements Section 5.8 of the FINAL v2.0 spec.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."DecisionMemory" (
  "id"                            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"                      TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "decisionId"                    TEXT NOT NULL REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "summaryText"                   TEXT NOT NULL,
  "keyTakeaways"                  JSONB NOT NULL DEFAULT '[]'::JSONB,
  "searchKeywords"                JSONB NOT NULL DEFAULT '[]'::JSONB,
  "relatedConstitutionArticleIds" JSONB NOT NULL DEFAULT '[]'::JSONB,
  "relatedMemoryIds"              JSONB NOT NULL DEFAULT '[]'::JSONB,
  "meetingArtifactId"             TEXT,
  "createdAt"                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "DecisionMemory_decisionId_unique" UNIQUE ("decisionId")
);

CREATE INDEX IF NOT EXISTS "DecisionMemory_familyId_createdAt_idx" ON public."DecisionMemory"("familyId", "createdAt");

CREATE TABLE IF NOT EXISTS public."DecisionImpact" (
  "id"            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"      TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "decisionId"    TEXT NOT NULL REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "milestoneText" TEXT NOT NULL,
  "dueDate"       TIMESTAMPTZ,
  "completedAt"   TIMESTAMPTZ,
  "evidenceUrls"  JSONB NOT NULL DEFAULT '[]'::JSONB,
  "notes"         TEXT,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "DecisionImpact_familyId_decisionId_idx" ON public."DecisionImpact"("familyId", "decisionId");

DROP TRIGGER IF EXISTS trg_trackc_decision_memory_updated_at ON public."DecisionMemory";
CREATE TRIGGER trg_trackc_decision_memory_updated_at
  BEFORE UPDATE ON public."DecisionMemory"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

DROP TRIGGER IF EXISTS trg_trackc_decision_impact_updated_at ON public."DecisionImpact";
CREATE TRIGGER trg_trackc_decision_impact_updated_at
  BEFORE UPDATE ON public."DecisionImpact"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

GRANT SELECT ON public."DecisionMemory" TO anon, authenticated;
GRANT SELECT ON public."DecisionImpact"  TO anon, authenticated;

COMMENT ON TABLE public."DecisionMemory" IS 'Track C v2.0: Post-resolution memory of a decision. Searchable forever.';
COMMENT ON TABLE public."DecisionImpact" IS 'Track C v2.0: Tracked impact milestones for a resolved decision.';
