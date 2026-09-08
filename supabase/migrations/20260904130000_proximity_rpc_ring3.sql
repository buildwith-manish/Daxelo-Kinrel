-- 20260904130000_proximity_rpc_ring3.sql (v2 — fixed recursive CTE)
--
-- v5.152 (FIX 1): Add Ring 3 (BFS depth 3) to the proximity RPC so
-- it returns up to 50 nodes by default instead of stopping at 22.
--
-- The original v5.144 RPC used separate UNION arms for each ring.
-- That works for 2 rings but breaks at 3+ because Postgres requires
-- the recursive reference to only appear in the recursive term.
-- This version uses a single recursive arm with a depth cap.

CREATE OR REPLACE FUNCTION get_viewer_family_graph(
  p_family_id  TEXT,
  p_viewer_id  TEXT,
  p_max_nodes  INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_result JSONB;
  v_viewer_linked TEXT;
  v_total_count INT;
BEGIN
  SELECT "linkedUserId" INTO v_viewer_linked
  FROM "Person"
  WHERE id = p_viewer_id
    AND "familyId" = p_family_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_viewer_linked IS NULL THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Viewer not found in family'
    );
  END IF;

  IF v_viewer_linked != auth.uid()::text THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Access denied: viewer not linked to authenticated user'
    );
  END IF;

  SELECT count(*) INTO v_total_count
  FROM "Person"
  WHERE "familyId" = p_family_id AND "deletedAt" IS NULL;

  -- v5.152: Single recursive arm with depth cap = 3 (4 rings total).
  -- This is the standard recursive BFS pattern — one seed row + one
  -- recursive arm that joins to the previous depth.
  WITH RECURSIVE proximity_bfs AS (
    -- Seed: the viewer at depth 0
    SELECT
      p.id, 0 AS bfs_depth
    FROM "Person" p
    WHERE p.id = p_viewer_id
      AND p."familyId" = p_family_id
      AND p."deletedAt" IS NULL

    UNION ALL

    -- Recursive: for each node at depth N, find its neighbors at depth N+1
    -- v5.152: Cap at depth 3 (4 rings: 0, 1, 2, 3)
    SELECT
      neighbor.id, bfs.bfs_depth + 1 AS bfs_depth
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
    SELECT DISTINCT ON (id)
      id, bfs_depth
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
          'id', p.id,
          'name', p.name,
          'username', p.username,
          'avatarUrl', p."photoUrl",
          'gender', p.gender,
          'isAnchor', p."isAnchor",
          'isDeceased', p."isDeceased",
          'visibility', p.visibility,
          'generationIndex', p."generationIndex",
          'isViewer', (p.id = p_viewer_id),
          'familyId', p."familyId",
          'dateOfBirth', p."dateOfBirth",
          'bfsDepth', pc.bfs_depth
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
            ELSE r."labelAtoB"
          END,
          'labelAtoB', r."labelAtoB",
          'labelBtoA', r."labelBtoA",
          'isPrivate', COALESCE(r.is_private, false),
          'isActive', COALESCE(r."isActive", true)
        ))
        FROM "Relationship" r
        WHERE r."familyId" = p_family_id
          AND COALESCE(r."isActive", true) = true
          AND r."fromPersonId" IN (SELECT id FROM proximity_capped)
          AND r."toPersonId" IN (SELECT id FROM proximity_capped)
      ), '[]'::jsonb),
      'totalCount', v_total_count,
      'isTruncated', (SELECT count(*) FROM proximity_dedup) > p_max_nodes,
      'proximityCount', (SELECT count(*) FROM proximity_capped),
      'maxNodes', p_max_nodes
    ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_viewer_family_graph(text, text, int) TO authenticated, anon;
