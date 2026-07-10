-- =============================================================================
-- Track C v2.0 — Hash-Partition LearningSignal on familyId (16 partitions)
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid
    WHERE c.relname = 'LearningSignal'
  ) THEN
    RAISE NOTICE 'LearningSignal is already partitioned. Skipping.';
  ELSE
    ALTER TABLE public."LearningSignal" RENAME TO "LearningSignal_old";

    EXECUTE $f$
      CREATE TABLE public."LearningSignal" (
        "id"          TEXT NOT NULL,
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
        "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY ("id", "familyId")
      ) PARTITION BY HASH ("familyId")
    $f$;

    FOR i IN 0..15 LOOP
      EXECUTE format(
        'CREATE TABLE public."LearningSignal_p%02s" PARTITION OF public."LearningSignal" FOR VALUES WITH (MODULUS 16, REMAINDER %s)',
        i, i
      );
    END LOOP;

    CREATE INDEX IF NOT EXISTS "LearningSignal_familyId_signalType_occurredAt_idx" ON public."LearningSignal"("familyId", "signalType", "occurredAt");
    CREATE INDEX IF NOT EXISTS "LearningSignal_familyId_occurredAt_idx"            ON public."LearningSignal"("familyId", "occurredAt");

    EXECUTE 'INSERT INTO public."LearningSignal" SELECT * FROM public."LearningSignal_old"';
    DROP TABLE public."LearningSignal_old";

    GRANT SELECT ON public."LearningSignal" TO anon, authenticated;
    RAISE NOTICE 'LearningSignal successfully partitioned into 16 hash partitions.';
  END IF;
END $$;

COMMENT ON TABLE public."LearningSignal" IS 'Track C v2.0: Learning signal stream. Hash-partitioned into 16 partitions on familyId. ADR-004.';
