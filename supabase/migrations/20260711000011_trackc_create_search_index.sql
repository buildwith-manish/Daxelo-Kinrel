-- =============================================================================
-- Track C v2.0 — AURA Search
-- Migration 11: SearchIndex
-- =============================================================================
-- Implements Section 5.9 of the FINAL v2.0 spec.
-- search_tsvector is added in migration 12 (separate because generated columns
-- + GIN indexes are operationally distinct from base table creation).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."SearchIndex" (
  "id"            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"      TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "entityType"    TEXT NOT NULL CHECK ("entityType" IN (
                    'constitution_article','constitution_clause','decision',
                    'memory','timeline_event','meeting_artifact'
                  )),
  "entityId"      TEXT NOT NULL,
  "title"         TEXT NOT NULL DEFAULT '',
  "body"          TEXT NOT NULL DEFAULT '',
  "keywords"      JSONB NOT NULL DEFAULT '[]'::JSONB,
  "boostedScore"  NUMERIC(8,4) NOT NULL DEFAULT 1.0,
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "SearchIndex_family_entity_unique" UNIQUE ("familyId", "entityType", "entityId")
);

CREATE INDEX IF NOT EXISTS "SearchIndex_familyId_entityType_idx" ON public."SearchIndex"("familyId", "entityType");
CREATE INDEX IF NOT EXISTS "SearchIndex_familyId_entityId_idx"   ON public."SearchIndex"("familyId", "entityId");
CREATE INDEX IF NOT EXISTS "SearchIndex_boostedScore_idx"        ON public."SearchIndex"("familyId", "boostedScore" DESC);

DROP TRIGGER IF EXISTS trg_trackc_search_index_updated_at ON public."SearchIndex";
CREATE TRIGGER trg_trackc_search_index_updated_at
  BEFORE UPDATE ON public."SearchIndex"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

GRANT SELECT ON public."SearchIndex" TO anon, authenticated;
COMMENT ON TABLE public."SearchIndex" IS 'Track C v2.0: AURA Search universal index. Mirrored to Drift on client for offline search.';
