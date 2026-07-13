-- 20260713120000_add_date_of_birth_to_viewer_graph.sql
--
-- P3.3: Birthday glow on near-birthday nodes.
--
-- Adds "dateOfBirth" to the get_viewer_family_graph RPC's node payload
-- so the client can compute isNearBirthday without a second round-trip.
-- The Person table already has a "dateOfBirth" TIMESTAMPTZ column
-- (added in 20260611145602_kinrel_v5_master_fix_section_0_1_2.sql);
-- this migration only changes the RPC's SELECT to include it.
--
-- The client-side isNearBirthday helper treats null/empty dateOfBirth
-- as "no birthday" — so existing Person rows without dateOfBirth
-- simply don't get a birthday glow. No data backfill is required.
--
-- Safe to apply on production: CREATE OR REPLACE is idempotent and the
-- only behavioral change is one extra JSONB key per node.

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
        'familyId', p."familyId",
        -- P3.3: include dateOfBirth so the client can compute
        -- isNearBirthday without a second round-trip. Null is fine —
        -- the client treats null dateOfBirth as "no birthday glow".
        'dateOfBirth', p."dateOfBirth"
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
