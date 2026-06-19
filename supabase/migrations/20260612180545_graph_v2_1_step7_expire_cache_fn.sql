-- ============================================================
-- Migration: graph_v2_1_step7_expire_cache_fn
-- Version:  20260612180545
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


CREATE OR REPLACE FUNCTION expire_graph_cache()
RETURNS void
LANGUAGE plpgsql
AS $func$
BEGIN
  DELETE FROM graph_state_cache WHERE expires_at < now();
END;
$func$;
