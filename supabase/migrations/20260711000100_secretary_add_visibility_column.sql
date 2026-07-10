-- =============================================================================
-- Track C v2.0 — AURA Secretary: Add visibility column to MeetingArtifact
-- =============================================================================
-- Adds a `visibility` column to control per-artifact access:
--   'family'           = visible to all family members once published (default)
--   'participants_only' = visible only to participants + admins, even after publish
--
-- Defaults to 'family' for all existing rows (backward-compatible).
-- =============================================================================

ALTER TABLE "MeetingArtifact"
  ADD COLUMN IF NOT EXISTS "visibility" TEXT NOT NULL DEFAULT 'family';
