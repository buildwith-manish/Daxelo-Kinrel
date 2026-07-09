-- =============================================================================
-- Track C v2.0 — Hash-Partition AURATimelineEvent on familyId (32 partitions)
-- =============================================================================
-- Implements Section 5.1 of the FINAL v2.0 spec. ADR-004.
-- Self-referential FK (parentEventId) becomes composite (parentEventId, familyId).
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid
    WHERE c.relname = 'AURATimelineEvent'
  ) THEN
    RAISE NOTICE 'AURATimelineEvent is already partitioned. Skipping.';
  ELSE
    ALTER TABLE public."AURATimelineEvent" DROP CONSTRAINT IF EXISTS "AURATimelineEvent_parentEventId_fk";
    DROP TRIGGER IF EXISTS timeline_no_update ON public."AURATimelineEvent";
    DROP TRIGGER IF EXISTS timeline_no_delete ON public."AURATimelineEvent";

    ALTER TABLE public."AURATimelineEvent" RENAME TO "AURATimelineEvent_old";

    EXECUTE $f$
      CREATE TABLE public."AURATimelineEvent" (
        "id"                TEXT NOT NULL,
        "familyId"          TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "kind"              TEXT NOT NULL CHECK ("kind" IN (
                              'constitution_created','constitution_amended','constitution_version_published',
                              'decision_created','decision_voted','decision_resolved','decision_expired',
                              'decision_lifecycle_changed',
                              'member_joined','member_left','role_changed',
                              'meeting_artifact_published','learning_profile_reset','correction'
                            )),
        "actorId"           TEXT,
        "targetEntityType"  TEXT,
        "targetEntityId"    TEXT,
        "title"             TEXT NOT NULL,
        "description"       TEXT,
        "payload"           JSONB NOT NULL DEFAULT '{}'::JSONB,
        "parentEventId"     TEXT,
        "occurredAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY ("id", "familyId")
      ) PARTITION BY HASH ("familyId")
    $f$;

    FOR i IN 0..31 LOOP
      EXECUTE format(
        'CREATE TABLE public."AURATimelineEvent_p%02s" PARTITION OF public."AURATimelineEvent" FOR VALUES WITH (MODULUS 32, REMAINDER %s)',
        i, i
      );
    END LOOP;

    CREATE INDEX IF NOT EXISTS "AURATimelineEvent_familyId_occurredAt_idx"      ON public."AURATimelineEvent"("familyId", "occurredAt");
    CREATE INDEX IF NOT EXISTS "AURATimelineEvent_familyId_kind_occurredAt_idx" ON public."AURATimelineEvent"("familyId", "kind", "occurredAt");
    CREATE INDEX IF NOT EXISTS "AURATimelineEvent_targetEntity_idx"             ON public."AURATimelineEvent"("targetEntityType", "targetEntityId") WHERE "targetEntityType" IS NOT NULL;

    EXECUTE 'INSERT INTO public."AURATimelineEvent" SELECT * FROM public."AURATimelineEvent_old"';
    DROP TABLE public."AURATimelineEvent_old";

    -- Composite self-FK for corrections
    ALTER TABLE public."AURATimelineEvent"
      ADD CONSTRAINT "AURATimelineEvent_parentEventId_fk"
      FOREIGN KEY ("parentEventId", "familyId") REFERENCES public."AURATimelineEvent"("id", "familyId") ON DELETE SET NULL;

    -- Re-arm append-only triggers
    CREATE TRIGGER timeline_no_update
      BEFORE UPDATE ON public."AURATimelineEvent"
      FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();

    CREATE TRIGGER timeline_no_delete
      BEFORE DELETE ON public."AURATimelineEvent"
      FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();

    GRANT SELECT ON public."AURATimelineEvent" TO anon, authenticated;
    RAISE NOTICE 'AURATimelineEvent successfully partitioned into 32 hash partitions.';
  END IF;
END $$;

COMMENT ON TABLE public."AURATimelineEvent" IS 'Track C v2.0: AURA Timeline — append-only, hash-partitioned into 32 partitions on familyId. ADR-001 + ADR-004.';
