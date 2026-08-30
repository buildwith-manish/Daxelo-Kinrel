-- =============================================================================
-- Daxelo-Kinrel — v4.0 Database Hardening
-- =============================================================================
-- Adds a CHECK constraint on the Relationship table to ensure only
-- fundamental edge types are stored: parent, spouse, adoptive_parent,
-- step_parent.
--
-- All derived relationships (father, mother, grandfather, uncle, cousin,
-- etc.) must be computed at runtime by the Deterministic Kinship Engine.
--
-- IMPORTANT: This migration is NON-BLOCKING. It:
-- 1. First migrates existing derived edges to their fundamental equivalents
-- 2. Then adds the CHECK constraint
-- 3. Does NOT delete any data — only normalizes
-- =============================================================================

-- ─── 1. Migrate existing derived edges to fundamental types ────────────────
-- Map: father/mother → parent, husband/wife → spouse, etc.

UPDATE "Relationship" SET "relationshipKey" = 'parent'
WHERE "relationshipKey" IN ('father', 'mother', 'parent');

UPDATE "Relationship" SET "relationshipKey" = 'spouse'
WHERE "relationshipKey" IN ('husband', 'wife', 'spouse');

UPDATE "Relationship" SET "relationshipKey" = 'adoptive_parent'
WHERE "relationshipKey" IN ('adoptive_father', 'adoptive_mother', 'adoptive_parent');

UPDATE "Relationship" SET "relationshipKey" = 'step_parent'
WHERE "relationshipKey" IN ('step_father', 'step_mother', 'stepfather', 'stepmother', 'step_parent');

-- Update relationshipType column too
UPDATE "Relationship" SET "relationshipType" = 'parent'
WHERE "relationshipType" IN ('father', 'mother');

UPDATE "Relationship" SET "relationshipType" = 'spouse'
WHERE "relationshipType" IN ('husband', 'wife');

UPDATE "Relationship" SET "relationshipType" = 'adoptive_parent'
WHERE "relationshipType" IN ('adoptive_father', 'adoptive_mother');

UPDATE "Relationship" SET "relationshipType" = 'step_parent'
WHERE "relationshipType" IN ('step_father', 'step_mother', 'stepfather', 'stepmother');

-- ─── 2. Add CHECK constraint ──────────────────────────────────────────────
-- Only allow the 4 fundamental edge types in relationshipKey.

DO $$
BEGIN
    -- Drop existing constraint if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'relationship_fundamental_edge_check'
        AND table_name = 'Relationship'
    ) THEN
        ALTER TABLE "Relationship" DROP CONSTRAINT relationship_fundamental_edge_check;
    END IF;

    -- Add the new constraint
    ALTER TABLE "Relationship" ADD CONSTRAINT relationship_fundamental_edge_check
        CHECK (
            "relationshipKey" IN ('parent', 'spouse', 'adoptive_parent', 'step_parent')
        );
END $$;

-- ─── 3. Add comment ──────────────────────────────────────────────────────
COMMENT ON CONSTRAINT relationship_fundamental_edge_check ON "Relationship" IS
    'v4.0: Only fundamental edge types allowed. All derived relationships (father, grandfather, uncle, cousin, etc.) must be computed at runtime by the Deterministic Kinship Engine.';

-- ─── 4. Drop RelationshipPathCache if it exists ──────────────────────────
-- The v4.0 spec says: "Never store derived relationships." This table
-- permanently caches derived paths and terms, violating the core principle.
-- The DeterministicKinshipEngine uses session-only in-memory cache.

DROP TABLE IF EXISTS "RelationshipPathCache" CASCADE;

-- ─── 5. Verify ───────────────────────────────────────────────────────────
SELECT
    'Fundamental edge constraint added' AS status,
    (SELECT COUNT(*) FROM "Relationship"
     WHERE "relationshipKey" IN ('parent', 'spouse', 'adoptive_parent', 'step_parent'))
    AS fundamental_edges,
    (SELECT COUNT(*) FROM "Relationship"
     WHERE "relationshipKey" NOT IN ('parent', 'spouse', 'adoptive_parent', 'step_parent'))
    AS non_fundamental_edges_remaining;
