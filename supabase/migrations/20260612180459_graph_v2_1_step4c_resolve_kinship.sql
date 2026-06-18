-- ============================================================
-- Migration: graph_v2_1_step4c_resolve_kinship
-- Version:  20260612180459
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

CREATE OR REPLACE FUNCTION resolve_kinship(
  p_member_a_id TEXT,
  p_member_b_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $func$
DECLARE
  result JSONB;
  rel_type TEXT;
BEGIN
  SELECT r."relationshipType" INTO rel_type
  FROM "Relationship" r
  WHERE (r."fromPersonId" = p_member_a_id AND r."toPersonId" = p_member_b_id)
     OR (r."fromPersonId" = p_member_b_id AND r."toPersonId" = p_member_a_id)
  LIMIT 1;

  IF rel_type IS NOT NULL THEN
    result := jsonb_build_object(
      'relationshipType', rel_type,
      'displayLabel', rel_type,
      'degreeOfSeparation', 1,
      'isMatrilateral', rel_type LIKE 'maternal%' OR rel_type LIKE 'mother%',
      'isPatrilateral', rel_type LIKE 'paternal%' OR rel_type LIKE 'father%',
      'isByMarriage', rel_type LIKE '%in_law%' OR rel_type LIKE '%spouse%'
    );
  ELSE
    result := jsonb_build_object(
      'relationshipType', 'unknown',
      'displayLabel', 'Unknown relationship',
      'degreeOfSeparation', -1,
      'isMatrilateral', false,
      'isPatrilateral', false,
      'isByMarriage', false
    );
  END IF;

  RETURN result;
END;
$func$;
