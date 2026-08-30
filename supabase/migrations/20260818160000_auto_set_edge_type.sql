-- =============================================================================
-- Daxelo Kinrel — v5.51: Auto-set edgeType from relationshipKey
-- =============================================================================
-- The edgeType column is an enum (PARENT, SPOUSE, ADOPTIVE_PARENT, STEP_PARENT)
-- that defaults to PARENT. When the Flutter app inserts a relationship with
-- relationshipKey='spouse', the edgeType should be SPOUSE, not PARENT.
--
-- This trigger automatically sets edgeType based on relationshipKey BEFORE
-- INSERT or UPDATE, so the Flutter client doesn't need to send the enum
-- value (which can cause type cast issues with PostgREST).
-- =============================================================================

CREATE OR REPLACE FUNCTION set_edge_type_from_relationship_key()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."relationshipKey" IS NOT NULL THEN
    NEW."edgeType" := CASE
      WHEN NEW."relationshipKey" IN ('spouse', 'husband', 'wife') THEN 'SPOUSE'::"EdgeType"
      WHEN NEW."relationshipKey" IN ('adoptive_parent', 'adoptive_father', 'adoptive_mother') THEN 'ADOPTIVE_PARENT'::"EdgeType"
      WHEN NEW."relationshipKey" IN ('step_parent', 'step_father', 'step_mother') THEN 'STEP_PARENT'::"EdgeType"
      ELSE 'PARENT'::"EdgeType"
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_edge_type ON "Relationship";
CREATE TRIGGER trg_set_edge_type
  BEFORE INSERT OR UPDATE ON "Relationship"
  FOR EACH ROW
  EXECUTE FUNCTION set_edge_type_from_relationship_key();
