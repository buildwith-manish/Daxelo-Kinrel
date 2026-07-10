-- =============================================================================
-- Track C v2.0 — AURA Secretary
-- Migration 10: MeetingArtifact
-- =============================================================================
-- Implements Section 5.8 of the FINAL v2.0 spec.
-- Structured (no free-text blob) — auditable, translatable, versionable.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."MeetingArtifact" (
  "id"                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"          TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "decisionId"        TEXT REFERENCES public."FamilyDecision"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "title"             TEXT NOT NULL,
  "heldAt"            TIMESTAMPTZ NOT NULL,
  "participants"      JSONB NOT NULL DEFAULT '[]'::JSONB,
  "agenda"            JSONB NOT NULL DEFAULT '[]'::JSONB,
  "discussionPoints"  JSONB NOT NULL DEFAULT '[]'::JSONB,
  "decisions"         JSONB NOT NULL DEFAULT '[]'::JSONB,
  "actionItems"       JSONB NOT NULL DEFAULT '[]'::JSONB,
  "draftMinutesMd"    TEXT NOT NULL DEFAULT '',
  "finalMinutesMd"    TEXT,
  "status"            TEXT NOT NULL DEFAULT 'draft' CHECK ("status" IN ('draft','reviewed','published')),
  "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "MeetingArtifact_familyId_heldAt_idx" ON public."MeetingArtifact"("familyId", "heldAt");
CREATE INDEX IF NOT EXISTS "MeetingArtifact_decisionId_idx"        ON public."MeetingArtifact"("decisionId") WHERE "decisionId" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "MeetingArtifact_status_idx"            ON public."MeetingArtifact"("familyId", "status");

DROP TRIGGER IF EXISTS trg_trackc_meeting_artifact_updated_at ON public."MeetingArtifact";
CREATE TRIGGER trg_trackc_meeting_artifact_updated_at
  BEFORE UPDATE ON public."MeetingArtifact"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

GRANT SELECT ON public."MeetingArtifact" TO anon, authenticated;
COMMENT ON TABLE public."MeetingArtifact" IS 'Track C v2.0: AURA Secretary structured meeting artifact. Replaces free-text minutes.';
