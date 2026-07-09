-- =============================================================================
-- Track C v2.0 — AURA Search
-- Migration 12: Generated tsvector column + GIN index
-- =============================================================================
-- Implements Section 5.9 of the FINAL v2.0 spec.
-- Postgres GENERATED ALWAYS AS ... STORED column — automatically maintained.
-- =============================================================================

ALTER TABLE public."SearchIndex"
  ADD COLUMN IF NOT EXISTS search_tsvector tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english', coalesce("title",'') || ' ' || coalesce("body",''))
  ) STORED;

CREATE INDEX IF NOT EXISTS "search_index_tsvector_gin"
  ON public."SearchIndex" USING GIN (search_tsvector);

COMMENT ON COLUMN public."SearchIndex".search_tsvector IS 'Track C v2.0: Generated tsvector for full-text search. Auto-maintained by Postgres.';
