-- Rollback for 14-17 (partitioning migrations)
-- Reverses partitioning by swapping back to non-partitioned tables.
-- WARNING: This is a destructive operation if the partitions contain data.
-- Run only during a maintenance window.
--
-- Each block is idempotent: if the table is NOT partitioned, it is skipped.

DO $$
BEGIN
  -- ── FamilyDecision ────────────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname = 'FamilyDecision'
  ) THEN
    ALTER TABLE public."DecisionVote"    DROP CONSTRAINT IF EXISTS "DecisionVote_decisionId_fkey";
    ALTER TABLE public."DecisionMemory"  DROP CONSTRAINT IF EXISTS "DecisionMemory_decisionId_fkey";
    ALTER TABLE public."DecisionImpact"  DROP CONSTRAINT IF EXISTS "DecisionImpact_decisionId_fkey";
    ALTER TABLE public."AIInsight"       DROP CONSTRAINT IF EXISTS "AIInsight_decisionId_fkey";
    ALTER TABLE public."SmartReminder"   DROP CONSTRAINT IF EXISTS "SmartReminder_decisionId_fkey";
    ALTER TABLE public."MeetingArtifact" DROP CONSTRAINT IF EXISTS "MeetingArtifact_decisionId_fkey";

    ALTER TABLE public."FamilyDecision" RENAME TO "FamilyDecision_part";
    EXECUTE $f$
      CREATE TABLE public."FamilyDecision" AS SELECT * FROM public."FamilyDecision_part" WITH NO DATA;
      ALTER TABLE public."FamilyDecision" ADD PRIMARY KEY ("id");
    $f$;
    INSERT INTO public."FamilyDecision" SELECT * FROM public."FamilyDecision_part";
    DROP TABLE public."FamilyDecision_part";

    -- Restore single-column FKs
    ALTER TABLE public."DecisionVote"    ADD CONSTRAINT "DecisionVote_decisionId_fkey"    FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."DecisionMemory"  ADD CONSTRAINT "DecisionMemory_decisionId_fkey"  FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."DecisionImpact"  ADD CONSTRAINT "DecisionImpact_decisionId_fkey"  FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."AIInsight"       ADD CONSTRAINT "AIInsight_decisionId_fkey"       FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."SmartReminder"   ADD CONSTRAINT "SmartReminder_decisionId_fkey"   FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."MeetingArtifact" ADD CONSTRAINT "MeetingArtifact_decisionId_fkey" FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE SET NULL ON UPDATE CASCADE;

    RAISE NOTICE 'FamilyDecision reverted to non-partitioned.';
  END IF;

  -- ── AURATimelineEvent ─────────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname = 'AURATimelineEvent'
  ) THEN
    ALTER TABLE public."AURATimelineEvent" DROP CONSTRAINT IF EXISTS "AURATimelineEvent_parentEventId_fk";
    DROP TRIGGER IF EXISTS timeline_no_update ON public."AURATimelineEvent";
    DROP TRIGGER IF EXISTS timeline_no_delete ON public."AURATimelineEvent";

    ALTER TABLE public."AURATimelineEvent" RENAME TO "AURATimelineEvent_part";
    EXECUTE $f$
      CREATE TABLE public."AURATimelineEvent" AS SELECT * FROM public."AURATimelineEvent_part" WITH NO DATA;
      ALTER TABLE public."AURATimelineEvent" ADD PRIMARY KEY ("id");
    $f$;
    INSERT INTO public."AURATimelineEvent" SELECT * FROM public."AURATimelineEvent_part";
    DROP TABLE public."AURATimelineEvent_part";

    ALTER TABLE public."AURATimelineEvent"
      ADD CONSTRAINT "AURATimelineEvent_parentEventId_fk"
      FOREIGN KEY ("parentEventId") REFERENCES public."AURATimelineEvent"("id") ON DELETE SET NULL;

    CREATE TRIGGER timeline_no_update BEFORE UPDATE ON public."AURATimelineEvent" FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();
    CREATE TRIGGER timeline_no_delete BEFORE DELETE ON public."AURATimelineEvent" FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();

    RAISE NOTICE 'AURATimelineEvent reverted to non-partitioned.';
  END IF;

  -- ── AIInsight ─────────────────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname = 'AIInsight'
  ) THEN
    ALTER TABLE public."SmartReminder" DROP CONSTRAINT IF EXISTS "SmartReminder_insightId_fkey";
    ALTER TABLE public."AIInsight" DROP CONSTRAINT IF EXISTS "AIInsight_decisionId_fkey";

    ALTER TABLE public."AIInsight" RENAME TO "AIInsight_part";
    EXECUTE $f$
      CREATE TABLE public."AIInsight" AS SELECT * FROM public."AIInsight_part" WITH NO DATA;
      ALTER TABLE public."AIInsight" ADD PRIMARY KEY ("id");
    $f$;
    INSERT INTO public."AIInsight" SELECT * FROM public."AIInsight_part";
    DROP TABLE public."AIInsight_part";

    ALTER TABLE public."AIInsight" ADD CONSTRAINT "AIInsight_decisionId_fkey" FOREIGN KEY ("decisionId") REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    ALTER TABLE public."SmartReminder" ADD CONSTRAINT "SmartReminder_insightId_fkey" FOREIGN KEY ("insightId") REFERENCES public."AIInsight"("id") ON DELETE SET NULL;

    RAISE NOTICE 'AIInsight reverted to non-partitioned.';
  END IF;

  -- ── LearningSignal ────────────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname = 'LearningSignal'
  ) THEN
    ALTER TABLE public."LearningSignal" RENAME TO "LearningSignal_part";
    EXECUTE $f$
      CREATE TABLE public."LearningSignal" AS SELECT * FROM public."LearningSignal_part" WITH NO DATA;
      ALTER TABLE public."LearningSignal" ADD PRIMARY KEY ("id");
    $f$;
    INSERT INTO public."LearningSignal" SELECT * FROM public."LearningSignal_part";
    DROP TABLE public."LearningSignal_part";

    RAISE NOTICE 'LearningSignal reverted to non-partitioned.';
  END IF;
END $$;
