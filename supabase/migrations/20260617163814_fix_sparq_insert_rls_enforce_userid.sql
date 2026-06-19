-- ============================================================
-- Migration: fix_sparq_insert_rls_enforce_userid
-- Version:  20260617163814
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 4: Sparq INSERT policy — enforce userId = auth.uid()
-- Old policy only checked auth.uid() IS NOT NULL, meaning any
-- authenticated user could insert a Sparq with any userId.
-- ============================================================

DROP POLICY IF EXISTS "Users can create sparqs" ON "Sparq";

CREATE POLICY "Users can create sparqs"
  ON "Sparq" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);
