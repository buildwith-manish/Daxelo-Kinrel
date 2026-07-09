-- =============================================================================
-- Daxelo-Kinrel — AURA bugfix migration
-- =============================================================================
-- Addresses:
--   Bug 1: Add languageTag column to "Relationship" so AURA can derive the
--          family's linguistic fingerprint from a dedicated field instead
--          of inferring it from the (mostly English) relationshipType string.
--          Without this, every English-term family's languageDistribution
--          collapses to {en: 1.0} and the AURA colour palette silently
--          produces Steel Blue for everyone.
--
--   Bug 9: Add languageDistribution column to "FamilyAuraHistory" so each
--          historical snapshot records which languages dominated the family
--          at that point in time. Previously snapshots stored colours but
--          not the raw language map, making it impossible to answer
--          "which language dominated our family in 2025?".
--
-- Both columns are nullable / have defaults so existing rows are unaffected.
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- Bug 1: Relationship.languageTag (nullable TEXT)
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."Relationship"
  ADD COLUMN IF NOT EXISTS "languageTag" TEXT;

COMMENT ON COLUMN public."Relationship"."languageTag" IS
  'AURA: ISO-639-1 language tag the user chose for this relationship in the app UI (e.g. "hi" for Hindi, "ta" for Tamil). Used by computeLanguageDistribution() to derive the family''s linguistic fingerprint. When null, the type→language lookup table is used as a fallback.';

-- ────────────────────────────────────────────────────────────────────────────
-- Bug 9: FamilyAuraHistory.languageDistribution (JSONB, default empty object)
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."FamilyAuraHistory"
  ADD COLUMN IF NOT EXISTS "languageDistribution" JSONB NOT NULL DEFAULT '{}'::JSONB;

COMMENT ON COLUMN public."FamilyAuraHistory"."languageDistribution" IS
  'AURA: snapshot of the family''s language distribution at this point in time. JSONB map of ISO-639-1 code → ratio (sums to 1.0). Stored so the AURA Timeline can show which languages dominated the family historically.';
