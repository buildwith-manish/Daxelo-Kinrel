-- =============================================================================
-- Track C v2.0 — AURA Timeline
-- Migration 03: AURATimelineEvent (append-only event log)
-- =============================================================================
-- Implements Section 5.4 of the FINAL v2.0 spec.
--
-- DESIGN:
--   * Append-only — enforced by DB trigger (migration 04).
--   * familyId-partitioned later (migration 16).
--   * Corrections are NEW rows with kind='correction' and parentEventId pointing
--     to the event being corrected. The original event is NEVER mutated.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."AURATimelineEvent" (
  "id"                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
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
  "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "AURATimelineEvent_familyId_occurredAt_idx"      ON public."AURATimelineEvent"("familyId", "occurredAt");
CREATE INDEX IF NOT EXISTS "AURATimelineEvent_familyId_kind_occurredAt_idx" ON public."AURATimelineEvent"("familyId", "kind", "occurredAt");
CREATE INDEX IF NOT EXISTS "AURATimelineEvent_targetEntity_idx"             ON public."AURATimelineEvent"("targetEntityType", "targetEntityId") WHERE "targetEntityType" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "AURATimelineEvent_parentEventId_idx"            ON public."AURATimelineEvent"("parentEventId") WHERE "parentEventId" IS NOT NULL;

-- Self-referential FK for corrections (added after table creation)
ALTER TABLE public."AURATimelineEvent"
  ADD CONSTRAINT "AURATimelineEvent_parentEventId_fk"
  FOREIGN KEY ("parentEventId") REFERENCES public."AURATimelineEvent"("id") ON DELETE SET NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."AURATimelineEvent" TO anon, authenticated;

COMMENT ON TABLE public."AURATimelineEvent" IS 'Track C v2.0: AURA Timeline — append-only event log. UPDATE and DELETE forbidden (enforced by trigger). Corrections are new rows with kind=correction.';
