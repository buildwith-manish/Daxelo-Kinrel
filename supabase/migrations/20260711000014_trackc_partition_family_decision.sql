-- =============================================================================
-- Track C v2.0 — Hash-Partition FamilyDecision on familyId (32 partitions)
-- =============================================================================
-- Implements Section 5.1 of the FINAL v2.0 spec. ADR-004.
--
-- NOTE on FKs to partitioned tables:
--   Postgres requires FKs pointing to a partitioned table to include the
--   partition key. So we use composite FKs: ("decisionId","familyId") →
--   FamilyDecision("id","familyId"). All referring tables already have
--   both columns.
--
-- Idempotent: if FamilyDecision is already partitioned, this is a no-op.
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid
    WHERE c.relname = 'FamilyDecision'
  ) THEN
    RAISE NOTICE 'FamilyDecision is already partitioned. Skipping.';
  ELSE
    -- ── Drop inbound FKs ────────────────────────────────────────────────
    ALTER TABLE public."DecisionVote"    DROP CONSTRAINT IF EXISTS "DecisionVote_decisionId_fkey";
    ALTER TABLE public."DecisionMemory"  DROP CONSTRAINT IF EXISTS "DecisionMemory_decisionId_fkey";
    ALTER TABLE public."DecisionImpact"  DROP CONSTRAINT IF EXISTS "DecisionImpact_decisionId_fkey";
    ALTER TABLE public."AIInsight"       DROP CONSTRAINT IF EXISTS "AIInsight_decisionId_fkey";
    ALTER TABLE public."SmartReminder"   DROP CONSTRAINT IF EXISTS "SmartReminder_decisionId_fkey";
    ALTER TABLE public."MeetingArtifact" DROP CONSTRAINT IF EXISTS "MeetingArtifact_decisionId_fkey";

    -- ── Rename old ──────────────────────────────────────────────────────
    ALTER TABLE public."FamilyDecision" RENAME TO "FamilyDecision_old";

    -- ── Create new partitioned table ────────────────────────────────────
    EXECUTE $f$
      CREATE TABLE public."FamilyDecision" (
        "id"                    TEXT NOT NULL,
        "familyId"              TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "createdById"           TEXT NOT NULL,
        "title"                 TEXT NOT NULL,
        "description"           TEXT,
        "type"                  TEXT NOT NULL CHECK ("type" IN ('simple_vote','consensus','elder_council','constitution_amend')),
        "status"                TEXT NOT NULL DEFAULT 'open' CHECK ("status" IN ('open','resolved','expired','cancelled')),
        "outcome"               TEXT,
        "options"               JSONB NOT NULL DEFAULT '[]'::JSONB,
        "eligibleUserIds"       JSONB NOT NULL DEFAULT '[]'::JSONB,
        "quorumPct"             INTEGER NOT NULL DEFAULT 50 CHECK ("quorumPct" >= 1 AND "quorumPct" <= 100),
        "showVotesLive"         BOOLEAN NOT NULL DEFAULT FALSE,
        "deadlineAt"            TIMESTAMPTZ NOT NULL,
        "resolvedAt"            TIMESTAMPTZ,
        "resolutionNote"        TEXT,
        "lifecycleState"        TEXT CHECK ("lifecycleState" IN ('planned','started','in_progress','completed','cancelled','expired','archived') OR "lifecycleState" IS NULL),
        "lifecycleUpdatedAt"    TIMESTAMPTZ,
        "aiSummaryCached"       JSONB,
        "aiProsConsCached"      JSONB,
        "constitutionVersionId" TEXT,
        "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        "updatedAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY ("id", "familyId"),
        CHECK ("deadlineAt" > "createdAt")
      ) PARTITION BY HASH ("familyId")
    $f$;

    -- ── 32 hash partitions ──────────────────────────────────────────────
    FOR i IN 0..31 LOOP
      EXECUTE format(
        'CREATE TABLE public."FamilyDecision_p%02s" PARTITION OF public."FamilyDecision" FOR VALUES WITH (MODULUS 32, REMAINDER %s)',
        i, i
      );
    END LOOP;

    -- ── Indexes on partitioned parent ───────────────────────────────────
    CREATE INDEX IF NOT EXISTS "FamilyDecision_familyId_status_idx"    ON public."FamilyDecision"("familyId", "status");
    CREATE INDEX IF NOT EXISTS "FamilyDecision_status_deadlineAt_idx"  ON public."FamilyDecision"("status", "deadlineAt");
    CREATE INDEX IF NOT EXISTS "FamilyDecision_familyId_updatedAt_idx" ON public."FamilyDecision"("familyId", "updatedAt");

    -- ── Copy data ───────────────────────────────────────────────────────
    EXECUTE 'INSERT INTO public."FamilyDecision" SELECT * FROM public."FamilyDecision_old"';

    -- ── Drop old ────────────────────────────────────────────────────────
    DROP TABLE public."FamilyDecision_old";

    -- ── Recreate inbound FKs as COMPOSITE (includes partition key) ──────
    ALTER TABLE public."DecisionVote"
      ADD CONSTRAINT "DecisionVote_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    ALTER TABLE public."DecisionMemory"
      ADD CONSTRAINT "DecisionMemory_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    ALTER TABLE public."DecisionImpact"
      ADD CONSTRAINT "DecisionImpact_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    ALTER TABLE public."AIInsight"
      ADD CONSTRAINT "AIInsight_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    ALTER TABLE public."SmartReminder"
      ADD CONSTRAINT "SmartReminder_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE CASCADE ON UPDATE CASCADE;

    -- MeetingArtifact.decisionId is SET NULL on delete — non-composite acceptable for nullable FK,
    -- but we still use composite for consistency. MeetingArtifact has familyId.
    ALTER TABLE public."MeetingArtifact"
      ADD CONSTRAINT "MeetingArtifact_decisionId_fkey"
      FOREIGN KEY ("decisionId", "familyId") REFERENCES public."FamilyDecision"("id", "familyId") ON DELETE SET NULL ON UPDATE CASCADE;

    -- ── Recreate monotonic updatedAt trigger ────────────────────────────
    DROP TRIGGER IF EXISTS trg_trackc_decision_updated_at ON public."FamilyDecision";
    CREATE TRIGGER trg_trackc_decision_updated_at
      BEFORE UPDATE ON public."FamilyDecision"
      FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

    GRANT SELECT ON public."FamilyDecision" TO anon, authenticated;

    RAISE NOTICE 'FamilyDecision successfully partitioned into 32 hash partitions.';
  END IF;
END $$;

COMMENT ON TABLE public."FamilyDecision" IS 'Track C v2.0: Family governance decision. Hash-partitioned into 32 partitions on familyId. ADR-004. Composite PK (id, familyId) supports composite FKs.';
