-- =============================================================================
-- Track C v2.0 — Search embedding storage (for semantic search rerank)
-- =============================================================================
-- Stores dense vector embeddings (one per SearchIndex row) so the search
-- service can rerank keyword-matched results by cosine similarity to the
-- query embedding.
--
-- Storage decision: separate table with embeddings stored as JSON-serialized
-- arrays in a TEXT column. This avoids the pgvector extension dependency
-- (we can't assume it's installed on the target Supabase project, and
-- installing it requires the Supabase dashboard which we can't reach
-- programmatically). The cosine similarity is computed in the NestJS
-- service after fetching — fine for the small N (≤100 results per query)
-- we deal with.
--
-- If pgvector IS available in a future deployment, this table can be
-- migrated to a `vector(384)` column + GIN index without changing the
-- service interface — just swap the storage format and push the cosine
-- computation into SQL.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."SearchEmbedding" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "entityType" TEXT NOT NULL,
  "entityId" TEXT NOT NULL,
  -- Embedding stored as a JSON-serialized array of 384 floats
  -- (all-MiniLM-L6-v2 produces 384-dim vectors).
  "embedding" TEXT NOT NULL,
  -- Model identifier so we can invalidate embeddings when we upgrade models
  "modelId" TEXT NOT NULL DEFAULT 'all-MiniLM-L6-v2',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One embedding per (family, entityType, entityId) — same uniqueness as
  -- SearchIndex itself.
  CONSTRAINT "search_embedding_unique" UNIQUE ("familyId", "entityType", "entityId")
);

-- Indexes — same access pattern as SearchIndex (family-scoped lookups)
CREATE INDEX IF NOT EXISTS "idx_search_embedding_family"
  ON public."SearchEmbedding" ("familyId");
CREATE INDEX IF NOT EXISTS "idx_search_embedding_lookup"
  ON public."SearchEmbedding" ("familyId", "entityType", "entityId");

-- RLS: family members can read; only service_role can write (embeddings are
-- generated server-side by the search service).
ALTER TABLE public."SearchEmbedding" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "trackc_search_embedding_select" ON public."SearchEmbedding";
CREATE POLICY "trackc_search_embedding_select" ON public."SearchEmbedding"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_search_embedding_insert" ON public."SearchEmbedding";
CREATE POLICY "trackc_search_embedding_insert" ON public."SearchEmbedding"
  FOR INSERT TO service_role WITH CHECK (true);

DROP POLICY IF EXISTS "trackc_search_embedding_update" ON public."SearchEmbedding";
CREATE POLICY "trackc_search_embedding_update" ON public."SearchEmbedding"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "trackc_search_embedding_delete" ON public."SearchEmbedding";
CREATE POLICY "trackc_search_embedding_delete" ON public."SearchEmbedding"
  FOR DELETE TO service_role USING (true);

COMMENT ON TABLE public."SearchEmbedding" IS 'Track C v2.0: Stores dense vector embeddings (384-dim all-MiniLM-L6-v2) for SearchIndex rows, used by the semantic rerank pass in search.service.ts.';
