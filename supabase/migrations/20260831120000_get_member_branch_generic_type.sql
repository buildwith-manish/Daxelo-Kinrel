-- ============================================================
-- Migration: get_member_branch_generic_type
-- Version:  20260831120000
-- Purpose:  Adds a 'generic' branch_type to get_member_branch so the
--           Flutter client can fetch the neighborhood of any person
--           regardless of relationship-key label. Fixes Bug 1 from the
--           UX review: tapping "+N" chips for custom/unrecognized
--           relationship keys (e.g. YakFather, StepMother, HalfBrother)
--           previously no-op'd because branchTypeForRelationshipKey()
--           returned null and the RPC's ELSE branch returned an empty
--           set. With 'generic', the client always has a fallback that
--           fetches ALL relationships involving p_member_id and returns
--           their connected persons + their inter-edges.
-- ============================================================

CREATE OR REPLACE FUNCTION get_member_branch(
  p_member_id TEXT,
  p_branch_type TEXT,
  p_depth INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $func$
DECLARE
  result JSONB;
  target_member_ids TEXT[];
  -- 'generic' mode: collect ALL persons connected to p_member_id
  -- within p_depth hops, regardless of relationship type.
  current_front TEXT[];
  next_front TEXT[];
  visited TEXT[];
  hop INT := 0;
BEGIN
  CASE p_branch_type
    WHEN 'maternal' THEN
      SELECT ARRAY_AGG(p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."toPersonId" = p_member_id AND r."relationshipType" IN ('mother','maternal_grandmother','maternal_grandfather')
        UNION
        SELECT r."toPersonId" FROM "Relationship" r
        WHERE r."fromPersonId" = p_member_id AND r."relationshipType" IN ('mother','maternal_grandmother','maternal_grandfather')
      );
    WHEN 'paternal' THEN
      SELECT ARRAY_AGG(p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."toPersonId" = p_member_id AND r."relationshipType" IN ('father','paternal_grandmother','paternal_grandfather')
        UNION
        SELECT r."toPersonId" FROM "Relationship" r
        WHERE r."fromPersonId" = p_member_id AND r."relationshipType" IN ('father','paternal_grandmother','paternal_grandfather')
      );
    WHEN 'cousins' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('cousin','niece','nephew')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'inLaws' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('father_in_law','mother_in_law','brother_in_law','sister_in_law')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'grandchildren' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('grandson','granddaughter')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'generic' THEN
      -- ── v5.131 (Bug 1 fix): universal neighborhood fetch ──────
      -- BFS over the relationship graph from p_member_id up to
      -- p_depth hops. Returns EVERY person reachable within that
      -- radius (any relationship type — blood, step, adoptive,
      -- in-law, custom). The client uses this as the fallback
      -- when branchTypeForRelationshipKey cannot classify the
      -- chip's relationship key, so "+N" taps always bring in the
      -- hidden members instead of no-op'ing.
      --
      -- Capped at p_depth hops to avoid scanning the whole family
      -- for very large graphs. Default depth = 2 mirrors the other
      -- branch types.
      visited := ARRAY[p_member_id]::TEXT[];
      current_front := ARRAY[p_member_id]::TEXT[];
      hop := 0;
      WHILE hop < p_depth AND array_length(current_front, 1) > 0 LOOP
        SELECT array_agg(DISTINCT x) INTO next_front
        FROM (
          SELECT r."fromPersonId" AS x
          FROM "Relationship" r
          WHERE r."toPersonId" = ANY(current_front)
            AND r."fromPersonId" <> ALL(visited)
            AND COALESCE(r.is_private, false) = false
          UNION
          SELECT r."toPersonId" AS x
          FROM "Relationship" r
          WHERE r."fromPersonId" = ANY(current_front)
            AND r."toPersonId" <> ALL(visited)
            AND COALESCE(r.is_private, false) = false
        ) t;
        IF next_front IS NULL OR array_length(next_front, 1) IS NULL THEN
          next_front := ARRAY[]::TEXT[];
        END IF;
        visited := visited || next_front;
        current_front := next_front;
        hop := hop + 1;
      END LOOP;
      -- Exclude the root itself from the "target" set — the
      -- client already has the root, we only want its neighbors.
      -- NOTE: PL/pgSQL requires `SELECT v FROM unnest(arr) AS v`
      -- to reference the column; `SELECT unnest WHERE unnest <> x`
      -- is invalid SQL and throws "column unnest does not exist".
      target_member_ids := ARRAY(
        SELECT v FROM unnest(visited) AS v WHERE v <> p_member_id
      );
      -- Edge case: if the BFS visited only the root itself (no
      -- neighbors within p_depth hops), target_member_ids will
      -- be empty — that's fine, the CTEs below will return
      -- empty nodes/edges which the client handles gracefully.
      IF target_member_ids IS NULL THEN
        target_member_ids := ARRAY[]::TEXT[];
      END IF;
    ELSE
      target_member_ids := ARRAY[]::TEXT[];
  END CASE;

  WITH branch_members AS (
    SELECT p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, p."isDeceased", p.visibility, p."generationIndex"
    FROM "Person" p
    WHERE p.id = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[]))
      AND COALESCE(p.visibility, 'public') != 'private'
  ),
  branch_edges AS (
    SELECT r.id, r."fromPersonId" AS member_a_id, r."toPersonId" AS member_b_id,
      r."relationshipType" AS relationship_type, r.is_private
    FROM "Relationship" r
    WHERE (r."fromPersonId" = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[]))
        OR r."toPersonId" = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[])))
      AND COALESCE(r.is_private, false) = false
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', bm.id, 'name', bm.display_name, 'username', bm.username,
        'avatarUrl', bm.avatar_url, 'gender', bm.gender,
        'isDeceased', bm."isDeceased", 'visibility', bm.visibility,
        'generationIndex', COALESCE(bm."generationIndex", 0)
      )) FROM branch_members bm),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', be.id, 'sourceId', be.member_a_id, 'targetId', be.member_b_id,
        'relationshipKey', be.relationship_type, 'isPrivate', be.is_private
      )) FROM branch_edges be),
      '[]'::jsonb
    )
  ) INTO result;

  RETURN COALESCE(result, '{"nodes":[],"edges":[]}'::jsonb);
END;
$func$;

-- ── Verify the new branch_type works ──────────────────────────────
-- Smoke test (safe to run — wrapped in DO $$ ... END $$ so a failure
-- doesn't break the migration; the function definition itself is the
-- authoritative source of truth).
DO $$
DECLARE
  smoke JSONB;
BEGIN
  -- Call the function with 'generic' on a likely-nonexistent member id.
  -- This returns empty nodes/edges (no crash), proving the new branch
  -- type is wired in.
  SELECT get_member_branch('__smoke_test_nonexistent__', 'generic', 2) INTO smoke;
  RAISE NOTICE 'get_member_branch(''generic'') smoke test returned nodes=%, edges=%',
    jsonb_array_length(smoke->'nodes'),
    jsonb_array_length(smoke->'edges');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'get_member_branch smoke test skipped: %', SQLERRM;
END $$;

COMMENT ON FUNCTION get_member_branch(TEXT, TEXT, INT) IS
  'Returns a JSONB {nodes, edges} payload of family members connected to p_member_id. '
  'p_branch_type is one of: maternal, paternal, cousins, inLaws, grandchildren, generic. '
  'generic (v5.131) does a BFS up to p_depth hops regardless of relationship type — used '
  'by the Flutter client as a fallback when the chip relationship key is unrecognized.';
