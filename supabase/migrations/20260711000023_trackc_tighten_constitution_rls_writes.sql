-- =============================================================================
-- Track C v2.0 — Tighten RLS write policies on constitution tables
-- =============================================================================
-- Addresses audit item #3 from Kinrel-TrackC-Improvement-Prompt-v2.md
--
-- Problem: The original migration 20260711000018_trackc_rls_all_tables.sql
-- scoped INSERT/UPDATE/DELETE policies on FamilyConstitution,
-- ConstitutionVersion, ConstitutionArticle, and ConstitutionClause to ANY
-- active family member (fn_trackc_user_family_ids()). The NestJS service
-- layer enforces admin-only writes, but per ADR-008 the database is supposed
-- to be the backstop. As written, a client with a valid JWT could INSERT
-- directly into ConstitutionArticle from the Supabase client SDK and skip
-- the admin check entirely.
--
-- Fix: Drop the four permissive INSERT/UPDATE/DELETE policies on each of the
-- four constitution tables and recreate them scoped to service_role only.
-- This matches the pattern already used for SearchIndex and
-- FamilyAnalyticsSnapshot in migration 18. SELECT policies are left intact.
--
-- After this migration:
--   - Direct client INSERT/UPDATE/DELETE on constitution tables → RLS rejects
--   - service_role writes (NestJS API, pg-boss workers) → still succeed
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- FamilyConstitution — tighten INSERT/UPDATE to service_role only
-- ────────────────────────────────────────────────────────────────────────────

-- Drop the permissive member-scoped write policies
DROP POLICY IF EXISTS "trackc_constitution_insert" ON public."FamilyConstitution";
DROP POLICY IF EXISTS "trackc_constitution_update" ON public."FamilyConstitution";

-- Recreate as service_role-only. service_role bypasses RLS entirely, so the
-- USING/WITH CHECK expressions are effectively always-true for it; we use a
-- trivially-true check so anon/authenticated roles (which do NOT bypass RLS)
-- are denied. This mirrors the pattern used elsewhere in this migration set
-- for tables that must only be written via the NestJS API.
CREATE POLICY "trackc_constitution_insert" ON public."FamilyConstitution"
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "trackc_constitution_update" ON public."FamilyConstitution"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

-- (DELETE was never allowed on this table from clients — the original
-- migration didn't create a DELETE policy. We add one now for service_role
-- so the NestJS service can perform admin-initiated deletes if needed.)
DROP POLICY IF EXISTS "trackc_constitution_delete" ON public."FamilyConstitution";
CREATE POLICY "trackc_constitution_delete" ON public."FamilyConstitution"
  FOR DELETE TO service_role USING (true);

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionVersion — tighten INSERT/UPDATE to service_role only
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "trackc_version_insert" ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_version_update" ON public."ConstitutionVersion";

CREATE POLICY "trackc_version_insert" ON public."ConstitutionVersion"
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "trackc_version_update" ON public."ConstitutionVersion"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "trackc_version_delete" ON public."ConstitutionVersion";
CREATE POLICY "trackc_version_delete" ON public."ConstitutionVersion"
  FOR DELETE TO service_role USING (true);

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionArticle — tighten INSERT/UPDATE/DELETE to service_role only
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "trackc_article_insert" ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_update" ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_delete" ON public."ConstitutionArticle";

CREATE POLICY "trackc_article_insert" ON public."ConstitutionArticle"
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "trackc_article_update" ON public."ConstitutionArticle"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "trackc_article_delete" ON public."ConstitutionArticle"
  FOR DELETE TO service_role USING (true);

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionClause — tighten INSERT/UPDATE/DELETE to service_role only
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "trackc_clause_insert" ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_update" ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_delete" ON public."ConstitutionClause";

CREATE POLICY "trackc_clause_insert" ON public."ConstitutionClause"
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "trackc_clause_update" ON public."ConstitutionClause"
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "trackc_clause_delete" ON public."ConstitutionClause"
  FOR DELETE TO service_role USING (true);

-- ────────────────────────────────────────────────────────────────────────────
-- Verification comment
-- ────────────────────────────────────────────────────────────────────────────
-- After applying this migration, an authenticated (non-service) Supabase
-- client should receive a 42501 (insufficient_privilege) error when
-- attempting INSERT/UPDATE/DELETE on any of the four constitution tables.
-- The NestJS admin endpoints (which use the service_role key server-side)
-- continue to work as before.
