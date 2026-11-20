-- ============================================================
-- Migration: story_audience_thumbnail
-- Task 2a — adds the two columns stories.service.ts has been waiting for
-- (see the "TODO ... by Agent-0" comments there):
--   • Story.audience      — PUBLIC | FAMILY_ONLY. NOT NULL DEFAULT 'PUBLIC',
--     which is exactly the behaviour every existing story has today (all
--     family stories are visible to whoever queries the family), so no
--     existing row changes meaning. Stored as text + CHECK (matching the
--     other visibility columns in this schema) rather than reusing the
--     SparqAudience enum, because stories have no circle audience.
--   • Story.thumbnailUrl  — nullable Cloudinary thumbnail URL.
--
-- Additive and idempotent: ADD COLUMN IF NOT EXISTS, constraint added only
-- if missing. No RLS / policy changes (column-level only). No function is
-- created, so SECURITY DEFINER / search_path do not apply here.
--
-- NOT applied to any database from the sandbox — review/test against a
-- staging Supabase project before trusting it in prod.
-- Deploy order: migration -> server (task 2b uses the columns) -> app.
-- ============================================================

ALTER TABLE "Story"
  ADD COLUMN IF NOT EXISTS "audience"     text NOT NULL DEFAULT 'PUBLIC',
  ADD COLUMN IF NOT EXISTS "thumbnailUrl" text;

-- Domain check (idempotent: only add when absent).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'Story_audience_check'
      AND conrelid = '"Story"'::regclass
  ) THEN
    ALTER TABLE "Story"
      ADD CONSTRAINT "Story_audience_check"
      CHECK ("audience" IN ('PUBLIC', 'FAMILY_ONLY'));
  END IF;
END
$$;

-- Backfill report: the NOT NULL DEFAULT already stamps every pre-existing
-- row 'PUBLIC'; this UPDATE pins the invariant for any partially-restored
-- row and reports how many rows were touched.
DO $$
DECLARE
  fixed integer;
BEGIN
  UPDATE "Story"
    SET "audience" = 'PUBLIC'
    WHERE "audience" IS NULL OR "audience" NOT IN ('PUBLIC', 'FAMILY_ONLY');
  GET DIAGNOSTICS fixed = ROW_COUNT;
  RAISE NOTICE 'story_audience_thumbnail: % Story row(s) normalised to audience=PUBLIC', fixed;
END
$$;
