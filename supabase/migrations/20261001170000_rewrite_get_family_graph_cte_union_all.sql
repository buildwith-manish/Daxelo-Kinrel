-- 20261001170000_rewrite_get_family_graph_cte_union_all.sql
--
-- PHASE 2 Item 18: Rewrite get_family_graph recursive CTE OR-join as UNION ALL
--
-- The current CTE uses:
--   JOIN "Relationship" r ON (r."fromPersonId" = gt.id OR r."toPersonId" = gt.id)
--
-- OR joins in a recursive CTE prevent Postgres from picking a single composite
-- index — it has to do a BitmapOr over both Relationship(familyId, fromPersonId)
-- and Relationship(familyId, toPersonId). Rewriting as UNION ALL of two SELECTs
-- (one per direction) lets each SELECT use a single index.
--
-- CORRECTNESS ANALYSIS:
-- A self-referential relationship (fromPersonId == toPersonId) would match
-- BOTH branches of the UNION ALL, producing duplicate rows. However, the
-- existing `unique_members` CTE already uses `SELECT DISTINCT ON (id)` to
-- deduplicate persons by ID, so duplicates from the UNION ALL are safely
-- eliminated. The `visible_edges` CTE filters by r.id and joins to
-- unique_members, so duplicate edges are also eliminated by the DISTINCT.
--
-- The rewrite is behavior-preserving: identical output structure (nodes/edges
-- keys, same field names, same isTruncated/totalCount fields).

CREATE OR REPLACE FUNCTION get_family_graph(
  p_member_id text,
  p_max_degree int DEFAULT 4,
  p_include_hidden boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  result JSONB;
BEGIN
  WITH RECURSIVE graph_traversal AS (
    SELECT
      p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, 0 AS degree, true AS is_anchor,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM "Person" p
    WHERE p.id = p_member_id

    UNION ALL

    -- Branch 1: relationships where the current node is the FROM person
    -- (uses Relationship(familyId, fromPersonId) composite index)
    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM graph_traversal gt
    JOIN "Relationship" r ON r."fromPersonId" = gt.id
    JOIN "Person" p ON p.id = r."toPersonId"
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')

    UNION ALL

    -- Branch 2: relationships where the current node is the TO person
    -- (uses Relationship(familyId, toPersonId) composite index)
    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM graph_traversal gt
    JOIN "Relationship" r ON r."toPersonId" = gt.id
    JOIN "Person" p ON p.id = r."fromPersonId"
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
  ),
  unique_members AS (
    SELECT DISTINCT ON (id)
      id, display_name, username, avatar_url, gender,
      MIN(degree) OVER (PARTITION BY id) AS degree,
      is_anchor, "isDeceased", visibility, "generationIndex"
    FROM graph_traversal
  ),
  visible_edges AS (
    SELECT
      r.id,
      r."fromPersonId" AS member_a_id,
      r."toPersonId" AS member_b_id,
      COALESCE(r."relationshipType", r."relationshipKey", 'unknown') AS relationship_type,
      r.is_private
    FROM "Relationship" r
    WHERE r."fromPersonId" IN (SELECT id FROM unique_members)
      AND r."toPersonId" IN (SELECT id FROM unique_members)
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(r.is_private, false) = false)
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', um.id,
        'name', um.display_name,
        'username', um.username,
        'avatarUrl', um.avatar_url,
        'gender', um.gender,
        'generationIndex', COALESCE(um."generationIndex", -um.degree),
        'isAnchor', um.is_anchor,
        'isDeceased', um."isDeceased",
        'visibility', um.visibility
      )) FROM unique_members um),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ve.id,
        'sourceId', ve.member_a_id,
        'targetId', ve.member_b_id,
        'relationshipKey', ve.relationship_type,
        'isPrivate', ve.is_private
      )) FROM visible_edges ve),
      '[]'::jsonb
    ),
    'isTruncated', (SELECT COUNT(*) > 5000 FROM unique_members),
    'totalCount', (SELECT COUNT(*) FROM unique_members)
  ) INTO result;

  RETURN result;
END;
$$;
