-- =============================================================================
-- ML spec item #5 — Learned closeness weights storage
-- =============================================================================
-- Stores the trained logistic regression weights that replace the hardcoded
-- weights in pulse/closeness.ts. Singleton (id='current') — re-running the
-- trainer overwrites.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."LearnedClosenessWeights" (
  "id" TEXT PRIMARY KEY DEFAULT 'current',
  "weights" JSONB NOT NULL DEFAULT '{"graphDistance":0.30,"generationDistance":0.15,"relationshipSemantic":0.35,"auraRoleMatch":0.10,"sharedConnections":0.10}',
  "bias" REAL NOT NULL DEFAULT 0,
  "trainSamples" INTEGER NOT NULL DEFAULT 0,
  "validationSamples" INTEGER NOT NULL DEFAULT 0,
  "trainAccuracy" REAL NOT NULL DEFAULT 0,
  "validationAccuracy" REAL NOT NULL DEFAULT 0,
  "fixedBaselineAccuracy" REAL NOT NULL DEFAULT 0,
  "beatsFixed" BOOLEAN NOT NULL DEFAULT false,
  "trainedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: anyone can read (the weights are not sensitive — they're aggregate
-- statistics). Only service_role can write (training is a server-side job).
ALTER TABLE public."LearnedClosenessWeights" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "learned_closeness_weights_select" ON public."LearnedClosenessWeights";
CREATE POLICY "learned_closeness_weights_select" ON public."LearnedClosenessWeights"
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "learned_closeness_weights_insert" ON public."LearnedClosenessWeights";
CREATE POLICY "learned_closeness_weights_insert" ON public."LearnedClosenessWeights"
  FOR INSERT TO service_role WITH CHECK (true);

DROP POLICY IF EXISTS "learned_closeness_weights_update" ON public."LearnedClosenessWeights";
CREATE POLICY "learned_closeness_weights_update" ON public."LearnedClosenessWeights"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public."LearnedClosenessWeights" IS 'ML spec item #5: Trained logistic regression weights that replace the hardcoded weights in pulse/closeness.ts. Singleton row (id=current).';
