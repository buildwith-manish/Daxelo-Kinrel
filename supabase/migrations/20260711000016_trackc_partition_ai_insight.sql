-- =============================================================================
-- Track C v2.0 — Hash-Partition AIInsight on familyId (16 partitions)
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid
    WHERE c.relname = 'AIInsight'
  ) THEN
    RAISE NOTICE 'AIInsight is already partitioned. Skipping.';
  ELSE
    -- Drop inbound FK from SmartReminder
    ALTER TABLE public."SmartReminder" DROP CONSTRAINT IF EXISTS "SmartReminder_insightId_fkey";
    -- Drop outbound FK to FamilyDecision (will recreate as composite)
    ALTER TABLE public."AIInsight" DROP CONSTRAINT IF EXISTS "AIInsight_decisionId_fkey";
    DROP TRIGGER IF EXISTS trg_trackc_ai_insight_updated_at ON public."AIInsight";

    ALTER TABLE public."AIInsight" RENAME TO "AIInsight_old";

    EXECUTE $f$
      CREATE TABLE public."AIInsight" (
        "id"              TEXT NOT NULL,
        "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "decisionId"      TEXT,
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
        "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY ("id", "familyId")
      ) PARTITION BY HASH ("familyId")
    $f$;

    FOR i IN 0..15 LOOP
      EXECUTE format(
        'CREATE TABLE public."AIInsight_p%02s" PARTITION OF public."AIInsight" FOR VALUES WITH (MODULUS 16, REMAINDER %s)',
        i, i
      );
    END LOOP;

    CREATE INDEX IF NOT EXISTS "AIInsight_familyId_kind_status_idx" ON public."AIInsight"("familyId", "kind", "status");
    CREATE INDEX IF NOT EXISTS "AIInsight_decisionId_kind_idx"      ON public."AIInsight"("decisionId", "kind") WHERE "decisionId" IS NOT NULL;
    CREATE INDEX IF NOT EXISTS "AIInsight_status_createdAt_idx"     ON public."AIInsight"("status", "createdAt");
    CREATE INDEX IF NOT EXISTS "AIInsight_familyId_createdAt_idx"   ON public."AIInsight"("familyId", "createdAt");

    EXECUTE 'INSERT INTO public."AIInsight" SELECT * FROM public."AIInsight_old"';
    DROP TABLE public."AIInsight_old";

    -- Composite FK to FamilyDecision (partitioned)
    ALTER TABLE public."AIInsight"
      ADD CONSTRAINT "AIInsight_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    -- Recreate SmartReminder FK (still single-column; SmartReminder has familyId, but FK uses just insightId)
    ALTER TABLE public."SmartReminder"
      ADD CONSTRAINT "SmartReminder_insightId_fkey"
      FOREIGN KEY ("insightId") REFERENCES public."AIInsight"("id") ON DELETE SET NULL;

    DROP TRIGGER IF EXISTS trg_trackc_ai_insight_updated_at ON public."AIInsight";
    CREATE TRIGGER trg_trackc_ai_insight_updated_at
      BEFORE UPDATE ON public."AIInsight"
      FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

    GRANT SELECT ON public."AIInsight" TO anon, authenticated;
    RAISE NOTICE 'AIInsight successfully partitioned into 16 hash partitions.';
  END IF;
END $$;

COMMENT ON TABLE public."AIInsight" IS 'Track C v2.0: AI insight. Hash-partitioned into 16 partitions on familyId. ADR-003 + ADR-004.';
