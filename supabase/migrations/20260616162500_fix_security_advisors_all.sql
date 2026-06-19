-- ============================================================
-- Migration: fix_security_advisors_all
-- Version:  20260616162500
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 1: Lock search_path on all 5 RPC functions
-- ============================================================

ALTER FUNCTION public.get_member_branch(p_member_id text, p_branch_type text, p_depth integer)
  SET search_path = public, pg_catalog;

ALTER FUNCTION public.search_members(p_query text, p_filters jsonb, p_limit integer, p_offset integer)
  SET search_path = public, pg_catalog;

ALTER FUNCTION public.resolve_kinship(p_member_a_id text, p_member_b_id text)
  SET search_path = public, pg_catalog;

ALTER FUNCTION public.check_permissions(p_viewer_id text, p_target_ids text[], p_permission_types text[])
  SET search_path = public, pg_catalog;

ALTER FUNCTION public.expire_graph_cache()
  SET search_path = public, pg_catalog;

-- ============================================================
-- FIX 2: Revoke anon/authenticated EXECUTE from internal
-- trigger-only functions (not meant as public RPCs)
-- ============================================================

REVOKE EXECUTE ON FUNCTION public._fn_after_family_insert() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_handle_new_auth_user() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_sync_member_count() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_sync_member_count_on_update() FROM anon, authenticated;

-- ============================================================
-- FIX 3: Tighten IncidentSubscriber INSERT policy
-- Column is "userId" (camelCase)
-- ============================================================

DROP POLICY IF EXISTS "Anyone can subscribe to incidents" ON public."IncidentSubscriber";

CREATE POLICY "Authenticated users can subscribe to incidents"
  ON public."IncidentSubscriber"
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid()::text = "userId");
