-- ============================================================
-- Migration: security_force_rls_fix_storage_drop_legacy_views
-- Generated: 2026-06-18T01:49:27.298541+00:00
-- Project:  Daxelo-Kinrel (promxswvsnvilplmrtsj)
-- Author:   Super Z audit
--
-- Three fixes identified in the migration audit:
--   F1. FORCE ROW LEVEL SECURITY on all 83 public-schema tables
--   F2. Drop legacy lowercase views `invitations` and `relationships`
--   F3. Tighten storage.objects policies (ownership check + role)
--
-- All operations are idempotent. Safe to re-run.
-- ============================================================

-- ============================================================
-- F1. FORCE ROW LEVEL SECURITY on all public-schema tables
-- ============================================================
-- RLS was enabled on every table but `relforcerowsecurity` was false,
-- meaning the table OWNER (postgres / service_role) bypassed RLS.
-- Forcing RLS means the owner is also subject to policies, which is
-- what Supabase's security advisor recommends.
-- ============================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relkind = 'r'
  LOOP
    EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', r.table_name);
  END LOOP;
END $$;

-- ============================================================
-- F2. Drop legacy lowercase views
-- ============================================================
-- `invitations` and `relationships` were 1:1 aliases of the PascalCase
-- "Invitation" and "Relationship" tables, created during the initial
-- production_sync_2025_03_04 migration. Nothing in the DB depends on
-- them. They cause naming confusion with the actual tables.
-- ============================================================
DROP VIEW IF EXISTS public.invitations;
DROP VIEW IF EXISTS public.relationships;

-- ============================================================
-- F3. Tighten storage.objects policies
-- ============================================================
-- The avatars bucket had three issues:
--   1. INSERT policy applied to role `public` (includes anon). Should
--      be `authenticated` only.
--   2. DELETE policy only checked `auth.uid() IS NOT NULL` — any
--      authenticated user could delete ANY avatar. Missing `owner =
--      auth.uid()` ownership check.
--   3. UPDATE policy had the same missing ownership check as DELETE.
--
-- All auth.uid() calls are wrapped in (select auth.uid()) per the
-- initplan performance fix already applied to public-schema policies.
-- ============================================================
DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (select auth.uid()) IS NOT NULL
  );

DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  );

DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  );
