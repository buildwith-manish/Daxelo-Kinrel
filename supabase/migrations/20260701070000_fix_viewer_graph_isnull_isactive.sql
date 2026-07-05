-- ============================================================
-- Migration: fix_viewer_graph_isnull_isactive
-- Version:  20260701070000
-- 
-- FIX: The get_viewer_family_graph RPC filtered by r."isActive" = true,
-- which excluded freshly-created relationships that have isActive = NULL
-- (the column defaults to NULL, not false). This caused "LINKS 0" in the
-- graph even when relationships existed in the database.
--
-- The fix uses COALESCE(r."isActive", true) = true so NULL is treated
-- as active — matching the client-side behavior in family_graph_provider.dart
-- which coerces null → true.
-- ============================================================

CREATE OR REPLACE FUNCTION get_viewer_family_graph(
  p_family_id  TEXT,
  p_viewer_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_result JSONB;
  v_viewer_linked TEXT;
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
        'familyId', p."familyId"
      )), '[]'::jsonb)
      FROM "Person" p
      WHERE p."familyId" = p_family_id AND p."deletedAt" IS NULL
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
        -- v73 FIX: Changed from r."isActive" = true to
        -- COALESCE(r."isActive", true) = true so that NULL isActive
        -- values (the default for newly-created rows) are treated as
        -- active. Previously, freshly-created relationships with
        -- isActive = NULL were silently excluded, causing "LINKS 0".
        AND COALESCE(r."isActive", true) = true
    ),
    'totalCount', (
      SELECT count(*) FROM "Person"
      WHERE "familyId" = p_family_id AND "deletedAt" IS NULL
    ),
    'isTruncated', false
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_viewer_family_graph(text, text) TO authenticated, anon;

-- Also fix the get_family_graph RPC with the same isActive fix
CREATE OR REPLACE FUNCTION public.get_family_graph(
  p_member_id text,
  p_max_degree integer DEFAULT 6,
  p_include_hidden boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  v_family_id text;
BEGIN
  -- Resolve the family ID from the anchor person
  SELECT "familyId" INTO v_family_id
  FROM "Person"
  WHERE id = p_member_id AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_family_id IS NULL THEN
    RETURN jsonb_build_object('nodes', '[]'::jsonb, 'edges', '[]'::jsonb, 'isTruncated', false, 'totalCount', 0);
  END IF;

  WITH RECURSIVE graph_traversal AS (
    SELECT
      p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, 0 AS degree, true AS is_anchor,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM "Person" p
    WHERE p.id = p_member_id
      AND p."deletedAt" IS NULL

    UNION ALL

    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM graph_traversal gt
    JOIN "Relationship" r ON (r."fromPersonId" = gt.id OR r."toPersonId" = gt.id)
    JOIN "Person" p ON (
      (p.id = r."fromPersonId" AND r."toPersonId" = gt.id)
      OR (p.id = r."toPersonId" AND r."fromPersonId" = gt.id)
    )
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND p."deletedAt" IS NULL
      -- v73 FIX: COALESCE isActive NULL → true
      AND COALESCE(r."isActive", true) = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
  ),
  all_family_members AS (
    SELECT DISTINCT ON (p.id)
      p.id,
      p.name AS display_name,
      p.username,
      p."photoUrl" AS avatar_url,
      p.gender,
      COALESCE(gt.degree, 999) AS degree,
      COALESCE(gt.is_anchor, (p.id = p_member_id)) AS is_anchor,
      p."isDeceased",
      p.visibility,
      p."generationIndex"
    FROM "Person" p
    LEFT JOIN graph_traversal gt ON p.id = gt.id
    WHERE p."familyId" = v_family_id
      AND p."deletedAt" IS NULL
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
    ORDER BY p.id
  ),
  visible_edges AS (
    SELECT
      r.id,
      r."fromPersonId" AS source_id,
      r."toPersonId" AS target_id,
      COALESCE(
        NULLIF(r."relationshipKey", ''),
        NULLIF(r."relationshipType", 'custom'),
        r."relationshipType",
        'unknown'
      ) AS relationship_key,
      r.is_private
    FROM "Relationship" r
    WHERE r."fromPersonId" IN (SELECT id FROM all_family_members)
      AND r."toPersonId" IN (SELECT id FROM all_family_members)
      -- v73 FIX: COALESCE isActive NULL → true
      AND COALESCE(r."isActive", true) = true
      AND (p_include_hidden = true OR COALESCE(r.is_private, false) = false)
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', afm.id,
        'name', afm.display_name,
        'username', afm.username,
        'avatarUrl', afm.avatar_url,
        'gender', afm.gender,
        'generationIndex', COALESCE(afm."generationIndex", -afm.degree),
        'isAnchor', afm.is_anchor,
        'isDeceased', afm."isDeceased",
        'visibility', afm.visibility
      )) FROM all_family_members afm),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ve.id,
        'sourceId', ve.source_id,
        'targetId', ve.target_id,
        'relationshipKey', ve.relationship_key,
        'isPrivate', ve.is_private
      )) FROM visible_edges ve),
      '[]'::jsonb
    ),
    'isTruncated', (SELECT COUNT(*) > 5000 FROM all_family_members),
    'totalCount', (SELECT COUNT(*) FROM all_family_members)
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_family_graph(text, integer, boolean) TO authenticated;

COMMENT ON FUNCTION public.get_family_graph(text, integer, boolean) IS
  'Returns the family graph as JSONB with nodes (all family members) and edges (active relationships). v73: isActive NULL treated as true.';
