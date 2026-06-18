-- ============================================================
-- Migration: fix_rls_auth_initplan_perf
-- Version:  20260617164610
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Rewrites every RLS policy in the public schema so that auth.<fn>() calls
-- (uid/jwt/role/email) are wrapped in a scalar subquery: (select auth.uid())
-- instead of auth.uid(). This lets Postgres evaluate the call once per query
-- instead of once per row, fixing the auth_rls_initplan performance warning
-- across all affected tables/policies.
DO $$
DECLARE
  pol record;
  new_qual text;
  new_check text;
  roles_list text;
  sql_stmt text;
  changed_count int := 0;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
  LOOP
    new_qual := pol.qual;
    new_check := pol.with_check;

    IF new_qual IS NOT NULL THEN
      new_qual := regexp_replace(new_qual, '(auth\.(uid|jwt|role|email))\(\)', '(select \1())', 'g');
    END IF;
    IF new_check IS NOT NULL THEN
      new_check := regexp_replace(new_check, '(auth\.(uid|jwt|role|email))\(\)', '(select \1())', 'g');
    END IF;

    IF (pol.qual IS DISTINCT FROM new_qual) OR (pol.with_check IS DISTINCT FROM new_check) THEN
      roles_list := array_to_string(pol.roles, ', ');

      EXECUTE format('DROP POLICY %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);

      sql_stmt := format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
                          pol.policyname, pol.schemaname, pol.tablename,
                          pol.permissive, pol.cmd, roles_list);

      IF new_qual IS NOT NULL THEN
        sql_stmt := sql_stmt || format(' USING (%s)', new_qual);
      END IF;
      IF new_check IS NOT NULL THEN
        sql_stmt := sql_stmt || format(' WITH CHECK (%s)', new_check);
      END IF;

      EXECUTE sql_stmt;
      changed_count := changed_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Rewrote % policies', changed_count;
END $$;
