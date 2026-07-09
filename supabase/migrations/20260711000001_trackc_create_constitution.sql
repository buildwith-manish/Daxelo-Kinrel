-- =============================================================================
-- Track C v2.0 — AURA Governance Engine
-- Migration 01: Family Constitution (FamilyConstitution, ConstitutionArticle,
--               ConstitutionClause, ConstitutionVersion)
-- =============================================================================
-- Implements Section 5.2 of the FINAL v2.0 spec.
-- All identifiers are double-quoted to preserve camelCase (Postgres folds
-- unquoted identifiers to lowercase by default).
--
-- Conventions:
--   * All family-scoped tables use TEXT "familyId" FK to public."Family"("id")
--   * All timestamps are TIMESTAMPTZ with default NOW()
--   * "updated_at" trigger ensures monotonic clock (Section 7.2)
--   * RLS added in migration 19 (trackc_rls_all_tables.sql)
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyConstitution"
-- One row per family. Holds the current published pointer + draft pointer.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyConstitution" (
  "id"                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"            TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "title"               TEXT NOT NULL DEFAULT 'Family Constitution',
  "preamble"            TEXT,
  "currentVersionId"    TEXT,
  "draftVersionId"      TEXT,
  "status"              TEXT NOT NULL DEFAULT 'draft' CHECK ("status" IN ('draft','in_review','published','archived')),
  "createdAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "FamilyConstitution_familyId_unique" UNIQUE ("familyId")
);

CREATE INDEX IF NOT EXISTS "FamilyConstitution_familyId_idx" ON public."FamilyConstitution"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "ConstitutionVersion"
-- Immutable once published. Each amendment creates a new version.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."ConstitutionVersion" (
  "id"                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "constitutionId"      TEXT NOT NULL REFERENCES public."FamilyConstitution"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"            TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "versionNumber"       INTEGER NOT NULL,
  "status"              TEXT NOT NULL DEFAULT 'draft' CHECK ("status" IN ('draft','in_review','published','superseded')),
  "publishedAt"         TIMESTAMPTZ,
  "publishedById"       TEXT,
  "amendmentDecisionId" TEXT,
  "changeSummary"       TEXT,
  "articleCount"        INTEGER NOT NULL DEFAULT 0,
  "clauseCount"         INTEGER NOT NULL DEFAULT 0,
  "createdAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "ConstitutionVersion_constitution_version_unique" UNIQUE ("constitutionId", "versionNumber")
);

CREATE INDEX IF NOT EXISTS "ConstitutionVersion_familyId_idx" ON public."ConstitutionVersion"("familyId");
CREATE INDEX IF NOT EXISTS "ConstitutionVersion_constitutionId_idx" ON public."ConstitutionVersion"("constitutionId");
CREATE INDEX IF NOT EXISTS "ConstitutionVersion_status_idx" ON public."ConstitutionVersion"("status");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "ConstitutionArticle"
-- Belongs to a version. Ordered within the version.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."ConstitutionArticle" (
  "id"             TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "versionId"      TEXT NOT NULL REFERENCES public."ConstitutionVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"       TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "orderIndex"     INTEGER NOT NULL DEFAULT 0,
  "title"          TEXT NOT NULL,
  "intent"         TEXT,
  "createdAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "ConstitutionArticle_versionId_idx" ON public."ConstitutionArticle"("versionId");
CREATE INDEX IF NOT EXISTS "ConstitutionArticle_familyId_idx" ON public."ConstitutionArticle"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "ConstitutionClause"
-- Belongs to an article. Atomic rule text.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."ConstitutionClause" (
  "id"             TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "articleId"      TEXT NOT NULL REFERENCES public."ConstitutionArticle"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "versionId"      TEXT NOT NULL REFERENCES public."ConstitutionVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"       TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "orderIndex"     INTEGER NOT NULL DEFAULT 0,
  "text"           TEXT NOT NULL,
  "intent"         TEXT,
  "createdAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "ConstitutionClause_articleId_idx" ON public."ConstitutionClause"("articleId");
CREATE INDEX IF NOT EXISTS "ConstitutionClause_versionId_idx" ON public."ConstitutionClause"("versionId");
CREATE INDEX IF NOT EXISTS "ConstitutionClause_familyId_idx" ON public."ConstitutionClause"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- FK WIRING: ConstitutionVersion pointers back to constitution + amendment decision
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."FamilyConstitution"
  ADD CONSTRAINT "FamilyConstitution_currentVersionId_fk"
  FOREIGN KEY ("currentVersionId") REFERENCES public."ConstitutionVersion"("id") ON DELETE SET NULL;

ALTER TABLE public."FamilyConstitution"
  ADD CONSTRAINT "FamilyConstitution_draftVersionId_fk"
  FOREIGN KEY ("draftVersionId") REFERENCES public."ConstitutionVersion"("id") ON DELETE SET NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- TRIGGER: monotonic updatedAt (Section 7.2)
-- Ensures updatedAt strictly increases on every UPDATE, preventing
-- microsecond collisions from skipping rows in the delta sync feed.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trackc_monotonic_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Guarantee NEW."updatedAt" > OLD."updatedAt" by at least 1 microsecond.
  -- If the application supplied a value, accept it only if it strictly exceeds OLD.
  IF NEW."updatedAt" <= OLD."updatedAt" THEN
    NEW."updatedAt" := OLD."updatedAt" + INTERVAL '1 microsecond';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_trackc_constitution_updated_at ON public."FamilyConstitution";
CREATE TRIGGER trg_trackc_constitution_updated_at
  BEFORE UPDATE ON public."FamilyConstitution"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

DROP TRIGGER IF EXISTS trg_trackc_version_updated_at ON public."ConstitutionVersion";
CREATE TRIGGER trg_trackc_version_updated_at
  BEFORE UPDATE ON public."ConstitutionVersion"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

DROP TRIGGER IF EXISTS trg_trackc_article_updated_at ON public."ConstitutionArticle";
CREATE TRIGGER trg_trackc_article_updated_at
  BEFORE UPDATE ON public."ConstitutionArticle"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

DROP TRIGGER IF EXISTS trg_trackc_clause_updated_at ON public."ConstitutionClause";
CREATE TRIGGER trg_trackc_clause_updated_at
  BEFORE UPDATE ON public."ConstitutionClause"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS (RLS added later in migration 19)
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."FamilyConstitution"  TO anon, authenticated;
GRANT SELECT ON public."ConstitutionVersion" TO anon, authenticated;
GRANT SELECT ON public."ConstitutionArticle" TO anon, authenticated;
GRANT SELECT ON public."ConstitutionClause"  TO anon, authenticated;

COMMENT ON TABLE public."FamilyConstitution"  IS 'Track C v2.0: Family constitution root. One row per family.';
COMMENT ON TABLE public."ConstitutionVersion" IS 'Track C v2.0: Immutable published constitution versions.';
COMMENT ON TABLE public."ConstitutionArticle" IS 'Track C v2.0: Article within a constitution version.';
COMMENT ON TABLE public."ConstitutionClause"  IS 'Track C v2.0: Atomic clause within an article.';
