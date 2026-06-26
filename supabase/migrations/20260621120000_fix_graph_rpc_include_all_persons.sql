-- ============================================================
-- Migration: fix_graph_rpc_include_all_persons
-- Version:  20260621120000
-- Source:   External audit — Bug 3
-- ============================================================
--
-- ROOT CAUSE:
-- The get_family_graph RPC used a recursive CTE (graph_traversal)
-- that starts from the anchor person and only traverses relationship
-- chains. Any member added WITHOUT a relationship link was completely
-- invisible to the function — the graph appeared empty even though
-- members existed in the Person table.
--
-- SOLUTION:
-- Replace the unique_members CTE with an all_family_members CTE that
-- LEFT JOINs graph_traversal with ALL non-deleted persons in the
-- family. This ensures every member appears in the result, with their
-- degree set to 999 if they're not connected to the anchor.
--
-- The edges query is unchanged — it still only includes edges between
-- members that are in the result set (which is now ALL members).
-- ============================================================

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
    -- Start from the anchor person
    SELECT
      p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, 0 AS degree, true AS is_anchor,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM "Person" p
    WHERE p.id = p_member_id
      AND p."deletedAt" IS NULL

    UNION ALL

    -- Traverse relationships to find connected members
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
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
  ),
  -- v39 BUG-3 FIX: Include ALL non-deleted persons in the family,
  -- not just those connected via relationships. LEFT JOIN with
  -- graph_traversal so unconnected members get degree=999.
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
      AND r."isActive" = true
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

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_family_graph(text, integer, boolean) TO authenticated;

COMMENT ON FUNCTION public.get_family_graph(text, integer, boolean) IS
  'Returns the family graph as JSONB with nodes (all family members) and edges (active relationships). Members not connected to the anchor via relationships are included with degree=999.';
