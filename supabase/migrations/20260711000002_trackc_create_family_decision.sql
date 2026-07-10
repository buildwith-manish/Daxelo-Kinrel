-- =============================================================================
-- Track C v2.0 — AURA Governance Engine
-- Migration 02: FamilyDecision + DecisionVote
-- =============================================================================
-- Implements Section 5.3 of the FINAL v2.0 spec.
--
-- NOTES:
--   * Hash-partitioned later in migration 15 (trackc_partition_family_decision.sql).
--     We create it as a normal table here; the partitioning migration handles
--     the migration-to-partitioned-table pattern (create partitioned copy,
--     copy data, drop old, rename).
--   * lifecycleState is NULL until the decision is resolved.
--   * status drives the active state machine (open → resolved|expired|cancelled).
--   * lifecycleState drives the post-resolution state machine
--     (planned → started → in_progress → completed → cancelled → expired → archived).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."FamilyDecision" (
  "id"                    TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
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

  -- Unified lifecycle (FINAL v2.0: merged from draft's split fields)
  "lifecycleState"        TEXT CHECK ("lifecycleState" IN ('planned','started','in_progress','completed','cancelled','expired','archived') OR "lifecycleState" IS NULL),
  "lifecycleUpdatedAt"    TIMESTAMPTZ,

  -- AI enrichment (denormalized for fast read; canonical in AIInsight)
  "aiSummaryCached"       JSONB,
  "aiProsConsCached"      JSONB,

  "constitutionVersionId" TEXT,

  "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "FamilyDecision_deadline_future" CHECK ("deadlineAt" > "createdAt")
);

CREATE INDEX IF NOT EXISTS "FamilyDecision_familyId_status_idx"        ON public."FamilyDecision"("familyId", "status");
CREATE INDEX IF NOT EXISTS "FamilyDecision_status_deadlineAt_idx"      ON public."FamilyDecision"("status", "deadlineAt");
CREATE INDEX IF NOT EXISTS "FamilyDecision_familyId_updatedAt_idx"     ON public."FamilyDecision"("familyId", "updatedAt");
CREATE INDEX IF NOT EXISTS "FamilyDecision_lifecycleState_idx"         ON public."FamilyDecision"("lifecycleState") WHERE "lifecycleState" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "FamilyDecision_constitutionVersionId_idx"  ON public."FamilyDecision"("constitutionVersionId") WHERE "constitutionVersionId" IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "DecisionVote"
-- Append-only vote records. One row per (decisionId, userId).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."DecisionVote" (
  "id"          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "decisionId"  TEXT NOT NULL REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"    TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userId"      TEXT NOT NULL,
  "option"      TEXT NOT NULL,
  "votedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "DecisionVote_decision_user_unique" UNIQUE ("decisionId", "userId")
);

CREATE INDEX IF NOT EXISTS "DecisionVote_decisionId_idx" ON public."DecisionVote"("decisionId");
CREATE INDEX IF NOT EXISTS "DecisionVote_familyId_idx"  ON public."DecisionVote"("familyId");
CREATE INDEX IF NOT EXISTS "DecisionVote_userId_idx"    ON public."DecisionVote"("userId");

-- ────────────────────────────────────────────────────────────────────────────
-- TRIGGER: monotonic updatedAt on FamilyDecision
-- ────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_trackc_decision_updated_at ON public."FamilyDecision";
CREATE TRIGGER trg_trackc_decision_updated_at
  BEFORE UPDATE ON public."FamilyDecision"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."FamilyDecision" TO anon, authenticated;
GRANT SELECT ON public."DecisionVote"   TO anon, authenticated;

COMMENT ON TABLE public."FamilyDecision" IS 'Track C v2.0: Family governance decision. Status drives active lifecycle; lifecycleState drives post-resolution state.';
COMMENT ON TABLE public."DecisionVote"   IS 'Track C v2.0: Append-only vote records. UNIQUE(decisionId, userId) prevents double-voting.';
