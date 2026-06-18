-- ============================================================
-- Migration: fix_security_advisor_warnings
-- Version:  20260617164625
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- 1. Avatars bucket is public, so the public storage URL endpoint already serves
--    objects without needing an RLS SELECT policy. The existing broad SELECT
--    policy lets anyone list every file in the bucket via the storage API.
--    Drop it; uploads/updates/deletes (which require ownership of auth.uid())
--    are untouched.
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;

-- 2. Internal trigger functions should not be directly callable via PostgREST
--    RPC by anon/authenticated. Triggers still fire fine without EXECUTE grants
--    since the trigger mechanism doesn't check caller EXECUTE privilege.
REVOKE EXECUTE ON FUNCTION public._fn_after_family_insert() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_handle_new_auth_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_sync_member_count() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._fn_sync_member_count_on_update() FROM PUBLIC, anon, authenticated;

-- 3. Pin a fixed search_path on the updated_at trigger function so it can't be
--    hijacked by a malicious search_path at call time.
ALTER FUNCTION public.set_updated_at() SET search_path = '';

-- 4. Move pg_trgm out of the public schema into a dedicated extensions schema,
--    per Supabase's database linter recommendation.
CREATE SCHEMA IF NOT EXISTS extensions;
ALTER EXTENSION pg_trgm SET SCHEMA extensions;
