-- 20260713130000_create_paginated_viewer_graph_rpc.sql
--
-- P5.1: Server-side pagination on graph fetch.
--
-- Creates get_viewer_family_graph_paginated — a paginated variant of
-- get_viewer_family_graph that returns the first N nodes (default 200)
-- plus their edges. The client fetches additional pages on demand when
-- the user expands branches or navigates to off-screen nodes.
--
-- Target: first paint < 500ms for a 200-person family.
--
-- The original get_viewer_family_graph RPC remains unchanged for
-- backward compatibility. The paginated RPC is called by the client
-- when the family has > 200 members (detected via a count query).

CREATE OR REPLACE FUNCTION get_viewer_family_graph_paginated(
  p_family_id  TEXT,
  p_viewer_id  TEXT,
  p_limit      INT DEFAULT 200,
  p_offset     INT DEFAULT 0
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
  -- Security: verify the viewer Person exists and is linked to auth.uid()
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

  -- Get total count for pagination metadata.
  SELECT count(*) INTO v_total_count
  FROM "Person"
  WHERE "familyId" = p_family_id AND "deletedAt" IS NULL;

  -- Paginated nodes: ORDER BY "isAnchor" DESC (anchor first), then name
  -- for deterministic ordering.
  SELECT jsonb_build_object(
    'nodes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
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
        'dateOfBirth', p."dateOfBirth"
      )), '[]'::jsonb)
      FROM (
        SELECT * FROM "Person"
        WHERE "familyId" = p_family_id AND "deletedAt" IS NULL
        ORDER BY "isAnchor" DESC, name ASC
        LIMIT p_limit
        OFFSET p_offset
      ) p
    ),
    'edges', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
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
      )), '[]'::jsonb)
      FROM "Relationship" r
      WHERE r."familyId" = p_family_id
        AND COALESCE(r."isActive", true) = true
        -- Only include edges where BOTH endpoints are in the current page.
        AND r."fromPersonId" IN (
          SELECT id FROM "Person"
          WHERE "familyId" = p_family_id AND "deletedAt" IS NULL
          ORDER BY "isAnchor" DESC, name ASC
          LIMIT p_limit OFFSET p_offset
        )
        AND r."toPersonId" IN (
          SELECT id FROM "Person"
          WHERE "familyId" = p_family_id AND "deletedAt" IS NULL
          ORDER BY "isAnchor" DESC, name ASC
          LIMIT p_limit OFFSET p_offset
        )
    ),
    'totalCount', v_total_count,
    'isTruncated', (p_offset + p_limit < v_total_count),
    'limit', p_limit,
    'offset', p_offset
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_viewer_family_graph_paginated(text, text, int, int) TO authenticated, anon;
