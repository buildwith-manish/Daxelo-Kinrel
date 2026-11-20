-- ============================================================
-- Migration: shareablelink_userid_reconcile
-- Task 3a — ShareableLink.userId (creator / owner).
--
-- The column, FK and index were ALREADY added to production by
-- 20260617163842_fix_shareablelink_rls_scope_to_owner.sql (applied via the
-- SQL editor, backfilled into the repo later). What was missing was the
-- Prisma model (server/prisma/schema.prisma), which task 3a now updates.
-- This migration therefore changes nothing on a database that has the
-- 20260617 migration; it only guarantees the same column / FK / index
-- exist (idempotent) and reports legacy rows. Names match what Prisma
-- expects: ShareableLink_userId_fkey, ShareableLink_userId_idx,
-- ON DELETE SET NULL ON UPDATE CASCADE.
--
-- NO BACKFILL: nothing on ShareableLink or any related table records who
-- created a link (only familyId / personId, no relation to a creator), so
-- the right userId cannot be derived safely. Existing rows stay NULL
-- rather than being guessed (e.g. from the family owner). Note the
-- service has not been writing userId yet either (task 3b), so links
-- created since 2026-06-17 are expected to be NULL too.
--
-- No function is created, so SECURITY DEFINER / search_path do not apply.
-- NOT applied to any database from the sandbox — review/test against a
-- staging Supabase project before trusting it in prod.
-- ============================================================

ALTER TABLE "ShareableLink"
  ADD COLUMN IF NOT EXISTS "userId" text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ShareableLink_userId_fkey'
      AND conrelid = '"ShareableLink"'::regclass
  ) THEN
    ALTER TABLE "ShareableLink"
      ADD CONSTRAINT "ShareableLink_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS "ShareableLink_userId_idx"
  ON "ShareableLink" ("userId");

-- Report only (no data change).
DO $$
DECLARE
  total_rows integer;
  null_rows  integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE "userId" IS NULL)
    INTO total_rows, null_rows
    FROM "ShareableLink";
  RAISE NOTICE 'shareablelink_userid_reconcile: % of % ShareableLink row(s) have no userId (left NULL, not backfilled)',
    null_rows, total_rows;
END
$$;
