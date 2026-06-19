-- ============================================================
-- Migration: graph_v2_1_step4a_get_member_branch
-- Version:  20260612180434
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

CREATE OR REPLACE FUNCTION get_member_branch(
  p_member_id TEXT,
  p_branch_type TEXT,
  p_depth INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $func$
DECLARE
  result JSONB;
  target_member_ids TEXT[];
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
    ELSE
      target_member_ids := ARRAY[]::TEXT[];
  END CASE;

  WITH branch_members AS (
    SELECT p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, p."isDeceased", p.visibility
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
        'isDeceased', bm."isDeceased", 'visibility', bm.visibility
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
