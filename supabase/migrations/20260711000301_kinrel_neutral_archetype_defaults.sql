-- =============================================================================
-- Global-launch fix: Kinrel archetype / inner-pattern column defaults
-- =============================================================================
-- BACKGROUND:
--   The Kinrel archetype system has 6 archetypes. Two of them — `banyan`
--   and `lotus` — were named after religiously/culturally loaded symbols
--   (the Banyan is India's national tree and a sacred fig species in
--   Hinduism/Buddhism; the Lotus is a Dharmic symbol of purity and
--   enlightenment). For the global launch, the display names were
--   renamed to religion-neutral alternatives:
--
--     banyan  →  "The Deep Root"  (dense, deeply-rooted, multi-generational)
--     lotus   →  "The Radiant"    (balanced center, mid clustering)
--
--   The visual pattern for the lotus archetype was also switched from
--   literal flower petals (`lotus` InnerPattern) to abstract radiating
--   segments (new `radiant` InnerPattern).
--
--   The internal archetype KEYS (`banyan`, `lotus`) are UNCHANGED so
--   existing DB rows still parse correctly — only the user-facing
--   display name (looked up from the key at render time) changed.
--   No data migration is needed for the display name because it is
--   computed from the key, not stored.
--
-- WHAT THIS MIGRATION DOES:
--   This migration ONLY changes the COLUMN DEFAULTS for two columns on
--   the FamilyKinrel table:
--     - archetypeKey:      default 'lotus'  →  'forest'
--     - innerPatternType:  default 'lotus'  →  'diamond'
--
--   It does NOT touch any existing rows. Existing rows keep whatever
--   archetypeKey / innerPatternType they already have. The new defaults
--   only apply to future INSERTs that omit these columns (which is rare
--   — the Kinrel compute pipeline always sets both columns explicitly).
--
--   The old default ('lotus') was the most culturally-loaded archetype
--   / pattern. If a bug or manual INSERT ever created a row without
--   specifying these columns, the family would have silently been
--   defaulted to a Dharmic religious archetype. The new defaults
--   ('forest' archetype + 'diamond' pattern) are the most generic,
--   nature/geometric-based options with no cultural coding.
--
--   This mirrors the app-level fallback fixes in:
--     - server/src/kinrel-intelligence/archetype-classifier.service.ts
--       (getDefinition: ARCHETYPES[4] → ARCHETYPES[5])
--     - server/src/kinrel-intelligence/kinrel-query.service.ts
--       (_safeGetDefinition: 'lotus' → 'forest')
--     - Daxelo-Kinrel-App/lib/features/kinrel_intelligence/data/kinrel_model.dart
--       (KinrelInnerPattern.fromString default: lotus → diamond)
--       (ArchetypeType.fromString default: lotus → forest)
-- =============================================================================

-- ── 1. FamilyKinrel.archetypeKey: default 'lotus' → 'forest' ───────────────
-- 'forest' is the most generic archetype (nature-based, no cultural coding).
-- It is also the conceptual fallback in the classifier (weight 1, no
-- thresholds — matches when no other archetype's thresholds are met).
ALTER TABLE public."FamilyKinrel"
  ALTER COLUMN "archetypeKey" SET DEFAULT 'forest';

-- ── 2. FamilyKinrel.innerPatternType: default 'lotus' → 'diamond' ──────────
-- 'diamond' is the most neutral geometric pattern (used by the forest
-- archetype). The 'lotus' pattern (literal flower petals) is still a
-- valid value for backward compatibility — old rows with
-- innerPatternType='lotus' parse without crashing and render via
-- _drawLotus until the next recompute writes 'radiant'.
ALTER TABLE public."FamilyKinrel"
  ALTER COLUMN "innerPatternType" SET DEFAULT 'diamond';

-- ── 3. Verify the new defaults are in place ────────────────────────────────
-- (Informational query — runs at migration time, output captured in logs.)
DO $$
DECLARE
  arch_default text;
  pat_default text;
BEGIN
  SELECT column_default INTO arch_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'FamilyKinrel'
    AND column_name = 'archetypeKey';

  SELECT column_default INTO pat_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'FamilyKinrel'
    AND column_name = 'innerPatternType';

  RAISE NOTICE 'FamilyKinrel.archetypeKey default = %', arch_default;
  RAISE NOTICE 'FamilyKinrel.innerPatternType default = %', pat_default;

  IF arch_default IS NULL OR arch_default NOT LIKE '%forest%' THEN
    RAISE WARNING 'archetypeKey default did not update as expected: %', arch_default;
  END IF;
  IF pat_default IS NULL OR pat_default NOT LIKE '%diamond%' THEN
    RAISE WARNING 'innerPatternType default did not update as expected: %', pat_default;
  END IF;
END $$;
