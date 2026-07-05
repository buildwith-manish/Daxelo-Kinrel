-- ============================================================
-- Migration: fix_relationship_isactive_defaults
-- Version:  20260701080000
--
-- FIXES:
--   1. Backfill all NULL isActive values to true
--   2. Set column DEFAULT to true so future INSERTs never have NULL
--   3. Fix get_viewer_family_graph RPC to use COALESCE(isActive, true)
--   4. Fix get_family_graph RPC to use COALESCE(isActive, true)
--
-- This is the DEFINITIVE fix for "LINKS 0" — the graph RPCs were
-- filtering by isActive = true, which excluded rows where isActive
-- was NULL (the default before this migration).
-- ============================================================

-- ── Step 1: Backfill NULL → true ─────────────────────────────
UPDATE "Relationship" SET "isActive" = true WHERE "isActive" IS NULL;

-- ── Step 2: Set column default ───────────────────────────────
ALTER TABLE "Relationship" ALTER COLUMN "isActive" SET DEFAULT true;

-- ── Step 3: Fix get_viewer_family_graph RPC ──────────────────
-- Uses COALESCE(r."isActive", true) = true so NULL is treated as active
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

-- ── Step 4: Fix get_family_graph RPC ─────────────────────────
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

-- ── Step 5: Verify ───────────────────────────────────────────
-- This query shows the isActive distribution after the fix.
-- Run it in the SQL editor to confirm:
--   SELECT 
--     count(*) FILTER (WHERE "isActive" IS NULL) as null_count,  -- should be 0
--     count(*) FILTER (WHERE "isActive" = true) as true_count,
--     count(*) FILTER (WHERE "isActive" = false) as false_count,
--     count(*) as total
--   FROM "Relationship";
