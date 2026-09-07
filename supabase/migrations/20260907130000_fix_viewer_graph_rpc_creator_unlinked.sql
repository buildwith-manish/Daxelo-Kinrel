-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907130000_fix_viewer_graph_rpc_creator_unlinked
--
-- PURPOSE
-- Fix get_viewer_family_graph RPC so that a family creator who has
-- linkedUserId=NULL on their anchor Person (because they're already
-- linked in another family — respects Person.linkedUserId UNIQUE
-- constraint) can still view their newly created family's graph.
--
-- BACKGROUND
-- The v5.177 trigger `_fn_after_family_insert_create_anchor_person`
-- creates the creator's Person with:
--   - linkedUserId = creator UUID (if user has no other linked Person)
--   - linkedUserId = NULL (if user already has a linked Person elsewhere)
--
-- The second case caused get_viewer_family_graph to return 0 nodes
-- with error "Viewer not found in family" — because the RPC's early
-- exit check required linkedUserId to be non-null.
--
-- FIX
-- Add a fallback check: if the viewer's linkedUserId is NULL, check
-- if the viewer is the family's anchor AND the Family.createdBy
-- matches auth.uid(). If so, they're the family creator — allow
-- the graph to render (they created this family, so they can view it).
--
-- This mirrors the Flutter app's viewerPersonIdProvider logic which
-- falls back to the anchor person when linkedUserId lookup fails.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_viewer_family_graph(
  p_family_id text,
  p_viewer_id text,
  p_max_nodes integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result JSONB;
  v_viewer_linked TEXT;
  v_total_count INT;
  v_is_creator boolean;
  v_family_created_by text;
BEGIN
  SELECT "linkedUserId" INTO v_viewer_linked
  FROM "Person"
  WHERE id = p_viewer_id
    AND "familyId" = p_family_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  -- v5.177.1: If linkedUserId is NULL, the viewer might be a family
  -- creator whose Person was created without linkedUserId (because they
  -- already have a linked Person in another family). Check if they're
  -- the Family.createdBy — if so, allow access.
  IF v_viewer_linked IS NULL THEN
    -- Check if this viewer is the family creator
    SELECT "createdBy" INTO v_family_created_by
    FROM "Family"
    WHERE id = p_family_id;

    v_is_creator := (
      v_family_created_by IS NOT NULL
      AND v_family_created_by = auth.uid()::text
    );

    IF NOT v_is_creator THEN
      -- Not the creator, and no linkedUserId → can't verify access
      RETURN jsonb_build_object(
        'nodes', '[]'::jsonb, 'edges', '[]'::jsonb, 'allEdges', '[]'::jsonb,
        'isTruncated', false, 'totalCount', 0,
        'error', 'Viewer not found in family'
      );
    END IF;
    -- Else: fall through — creator is allowed to view even without linkedUserId
  ELSIF v_viewer_linked != auth.uid()::text THEN
    -- linkedUserId is set but doesn't match the current auth user
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb, 'allEdges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Access denied: viewer not linked to authenticated user'
    );
  END IF;

  SELECT count(*) INTO v_total_count
  FROM "Person"
  WHERE "familyId" = p_family_id AND "deletedAt" IS NULL;

  WITH RECURSIVE proximity_bfs AS (
    SELECT p.id, 0 AS bfs_depth
    FROM "Person" p
    WHERE p.id = p_viewer_id
      AND p."familyId" = p_family_id
      AND p."deletedAt" IS NULL
    UNION ALL
    SELECT neighbor.id, bfs.bfs_depth + 1 AS bfs_depth
    FROM proximity_bfs bfs
    JOIN "Relationship" r ON (
      (r."fromPersonId" = bfs.id AND r."toPersonId" != bfs.id)
      OR (r."toPersonId" = bfs.id AND r."fromPersonId" != bfs.id)
    )
    JOIN "Person" neighbor ON (
      (neighbor.id = r."fromPersonId" AND r."toPersonId" = bfs.id)
      OR (neighbor.id = r."toPersonId" AND r."fromPersonId" = bfs.id)
    )
    WHERE bfs.bfs_depth < 3
      AND neighbor."familyId" = p_family_id
      AND neighbor."deletedAt" IS NULL
      AND r."familyId" = p_family_id
      AND r."isActive" = true
  ),
  proximity_dedup AS (
    SELECT DISTINCT ON (id) id, bfs_depth
    FROM proximity_bfs
    ORDER BY id, bfs_depth ASC
  ),
  proximity_capped AS (
    SELECT id, bfs_depth
    FROM proximity_dedup
    ORDER BY bfs_depth ASC, id ASC
    LIMIT GREATEST(p_max_nodes, 1)
  )
  SELECT
    jsonb_build_object(
      'nodes', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'username', p.username,
          'avatarUrl', p."photoUrl", 'gender', p.gender,
          'isAnchor', p."isAnchor", 'isDeceased', p."isDeceased",
          'visibility', p.visibility, 'generationIndex', p."generationIndex",
          'isViewer', (p.id = p_viewer_id), 'familyId', p."familyId",
          'dateOfBirth', p."dateOfBirth", 'bfsDepth', pc.bfs_depth
        ) ORDER BY pc.bfs_depth ASC, p.name ASC)
        FROM proximity_capped pc
        JOIN "Person" p ON p.id = pc.id
        WHERE p."deletedAt" IS NULL
      ), '[]'::jsonb),

      'edges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id,
          'sourceId', r."fromPersonId",
          'targetId', r."toPersonId",
          'relationshipKey', COALESCE(
            NULLIF(r."relationshipKey", ''),
            NULLIF(r."relationshipType", 'custom'),
            'unknown'
          ),
          'label', CASE
            WHEN r."fromPersonId" = p_viewer_id THEN r."labelAtoB"
            WHEN r."toPersonId" = p_viewer_id THEN r."labelBtoA"
            ELSE COALESCE(r."labelAtoB", r."labelBtoA")
          END,
          'labelAtoB', r."labelAtoB",
          'labelBtoA', r."labelBtoA"
        ))
        FROM "Relationship" r
        WHERE r."familyId" = p_family_id
          AND r."fromPersonId" IN (SELECT id FROM proximity_capped)
          AND r."toPersonId" IN (SELECT id FROM proximity_capped)
          AND r."isActive" = true
      ), '[]'::jsonb),

      'allEdges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id,
          'fromPersonId', r."fromPersonId",
          'toPersonId', r."toPersonId",
          'relationshipKey', COALESCE(
            NULLIF(r."relationshipKey", ''),
            'unknown'
          ),
          'labelAtoB', r."labelAtoB"
        ))
        FROM "Relationship" r
        WHERE r."familyId" = p_family_id
          AND r."isActive" = true
      ), '[]'::jsonb),

      'isTruncated', (SELECT count(*) FROM proximity_dedup) > GREATEST(p_max_nodes, 1),
      'totalCount', v_total_count,
      'proximityCount', (SELECT count(*) FROM proximity_capped)
    ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- Verify the update
COMMENT ON FUNCTION public.get_viewer_family_graph(text, text, integer) IS
'v5.177.1: Allows family creators with linkedUserId=NULL on their anchor Person (because they have a linked Person in another family) to view their newly created family graph — checks Family.createdBy = auth.uid() as fallback.';
