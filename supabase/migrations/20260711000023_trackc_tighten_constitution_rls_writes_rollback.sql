-- Rollback for 20260711000023_trackc_tighten_constitution_rls_writes.sql
--
-- Restores the permissive (any-active-member) INSERT/UPDATE/DELETE policies
-- on the four constitution tables, matching the original state from
-- migration 20260711000018_trackc_rls_all_tables.sql.
--
-- ⚠️ Rolling back re-opens the security gap described in the forward
-- migration. Only run this if you have a concrete reason to allow direct
-- client writes to constitution tables (e.g. a temporary debugging need)
-- and re-apply the forward migration as soon as possible.

-- ────────────────────────────────────────────────────────────────────────────
-- FamilyConstitution — restore member-scoped write policies
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "trackc_constitution_insert" ON public."FamilyConstitution";
DROP POLICY IF EXISTS "trackc_constitution_update" ON public."FamilyConstitution";
DROP POLICY IF EXISTS "trackc_constitution_delete" ON public."FamilyConstitution";

CREATE POLICY "trackc_constitution_insert" ON public."FamilyConstitution"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_constitution_update" ON public."FamilyConstitution"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- (Original migration 18 did not have a DELETE policy on FamilyConstitution.
-- We do not restore one — leaving the table DELETE-denied for non-service
-- roles matches the original behavior.)

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionVersion — restore member-scoped write policies
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "trackc_version_insert" ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_version_update" ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_version_delete" ON public."ConstitutionVersion";

CREATE POLICY "trackc_version_insert" ON public."ConstitutionVersion"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_version_update" ON public."ConstitutionVersion"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionArticle — restore member-scoped write policies
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "trackc_article_insert" ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_update" ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_delete" ON public."ConstitutionArticle";

CREATE POLICY "trackc_article_insert" ON public."ConstitutionArticle"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_article_update" ON public."ConstitutionArticle"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_article_delete" ON public."ConstitutionArticle"
  FOR DELETE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- ────────────────────────────────────────────────────────────────────────────
-- ConstitutionClause — restore member-scoped write policies
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "trackc_clause_insert" ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_update" ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_delete" ON public."ConstitutionClause";

CREATE POLICY "trackc_clause_insert" ON public."ConstitutionClause"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_clause_update" ON public."ConstitutionClause"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_clause_delete" ON public."ConstitutionClause"
  FOR DELETE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));
