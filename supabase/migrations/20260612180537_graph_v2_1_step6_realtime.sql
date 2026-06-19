-- ============================================================
-- Migration: graph_v2_1_step6_realtime
-- Version:  20260612180537
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
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
