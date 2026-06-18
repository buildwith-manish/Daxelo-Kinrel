-- ============================================================
-- Migration: graph_v2_1_step3_rpc_get_family_graph
-- Version:  20260612180330
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


CREATE OR REPLACE FUNCTION get_family_graph(
  p_member_id TEXT,
  p_max_degree INT DEFAULT 3,
  p_include_hidden BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
BEGIN
  WITH RECURSIVE graph_traversal AS (
    SELECT
      p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, 0 AS degree, true AS is_anchor,
      p."isDeceased", p.visibility
    FROM "Person" p
    WHERE p.id = p_member_id

    UNION ALL

    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility
    FROM graph_traversal gt
    JOIN "Relationship" r ON (r."fromPersonId" = gt.id OR r."toPersonId" = gt.id)
    JOIN "Person" p ON (
      (p.id = r."fromPersonId" AND r."toPersonId" = gt.id)
      OR (p.id = r."toPersonId" AND r."fromPersonId" = gt.id)
    )
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
  ),
  unique_members AS (
    SELECT DISTINCT ON (id)
      id, display_name, username, avatar_url, gender,
      MIN(degree) OVER (PARTITION BY id) AS degree,
      is_anchor, "isDeceased", visibility
    FROM graph_traversal
  ),
  visible_edges AS (
    SELECT r.id, r."fromPersonId" AS member_a_id, r."toPersonId" AS member_b_id,
      r."relationshipType" AS relationship_type, r.is_private
    FROM "Relationship" r
    WHERE r."fromPersonId" IN (SELECT id FROM unique_members)
      AND r."toPersonId" IN (SELECT id FROM unique_members)
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(r.is_private, false) = false)
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', um.id, 'name', um.display_name, 'username', um.username,
        'avatarUrl', um.avatar_url, 'gender', um.gender,
        'generationIndex', -um.degree, 'isAnchor', um.is_anchor,
        'isDeceased', um."isDeceased", 'visibility', um.visibility
      )) FROM unique_members um),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ve.id, 'sourceId', ve.member_a_id, 'targetId', ve.member_b_id,
        'relationshipKey', ve.relationship_type, 'isPrivate', ve.is_private
      )) FROM visible_edges ve),
      '[]'::jsonb
    ),
    'isTruncated', (SELECT COUNT(*) > 5000 FROM unique_members),
    'totalCount', (SELECT COUNT(*) FROM unique_members)
  ) INTO result;

  RETURN result;
END;
$$;
