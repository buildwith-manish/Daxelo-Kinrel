-- ============================================================
-- Migration: graph_v2_1_step6_realtime
-- Version:  20260612180537
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
--
-- ⚠️  FLAGGED FOR REVIEW (v2.2 — 2026-09-07):
-- This migration adds Person + Relationship to the supabase_realtime
-- publication for postgres_changes (WAL-decode). As of migration
-- 20260907160000_graph_v2_2_broadcast_triggers.sql, Person + Relationship
-- are REMOVED from the publication and use trigger-based Broadcast instead.
--
-- This file is NOT deleted (kept for audit/history). On a fresh DB:
--   1. This migration runs first → adds Person/Relationship to publication
--   2. The v2.2 migration runs later → removes them from publication
-- The net effect is correct (Person/Relationship NOT in publication).
--
-- To clean up: this file could be deleted in a future PR once the v2.2
-- migration is confirmed stable in production. For now, it's kept for
-- rollback safety (if v2.2 is reverted, this migration re-adds them).
-- ============================================================


DO $$
DECLARE
  tbl TEXT;
  tables_to_add TEXT[] := ARRAY['"Relationship"', '"Person"', 'permissions', 'blocks'];
BEGIN
  FOREACH tbl IN ARRAY tables_to_add LOOP
    BEGIN
      EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE ' || tbl;
    EXCEPTION WHEN others THEN
      -- already in publication or other non-fatal error, skip
      NULL;
    END;
  END LOOP;
END;
$$;
