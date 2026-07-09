-- Rollback for 20260711000001_trackc_create_constitution.sql
-- Reverse order of creation. Drop triggers first, then tables.

DROP TRIGGER IF EXISTS trg_trackc_clause_updated_at ON public."ConstitutionClause";
DROP TRIGGER IF EXISTS trg_trackc_article_updated_at ON public."ConstitutionArticle";
DROP TRIGGER IF EXISTS trg_trackc_version_updated_at ON public."ConstitutionVersion";
DROP TRIGGER IF EXISTS trg_trackc_constitution_updated_at ON public."FamilyConstitution";

DROP TABLE IF EXISTS public."ConstitutionClause";
DROP TABLE IF EXISTS public."ConstitutionArticle";
DROP TABLE IF EXISTS public."ConstitutionVersion";
DROP TABLE IF EXISTS public."FamilyConstitution";

-- NOTE: fn_trackc_monotonic_updated_at() is shared across all Track C tables.
-- It is dropped in the final rollback (migration 21 rollback).
