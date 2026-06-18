-- ============================================================
-- Migration: graph_v2_1_step4d_check_permissions
-- Version:  20260612180513
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

CREATE OR REPLACE FUNCTION check_permissions(
  p_viewer_id TEXT,
  p_target_ids TEXT[],
  p_permission_types TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $func$
DECLARE
  result JSONB;
BEGIN
  WITH permission_checks AS (
    SELECT
      t.id AS target_id,
      ptype.permission_type,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM permissions p2
          WHERE p2.grantor_id = t.id
            AND p2.grantee_id = p_viewer_id
            AND p2.permission_type = ANY(p_permission_types)
        ) THEN true
        WHEN COALESCE((SELECT visibility FROM "Person" WHERE id = t.id), 'public') = 'public'
          AND 'view_profile' = ANY(p_permission_types) THEN true
        WHEN t.id = p_viewer_id THEN true
        WHEN EXISTS (
          SELECT 1 FROM "FamilyMember" fm1
          JOIN "FamilyMember" fm2 ON fm1."familyId" = fm2."familyId"
          WHERE fm1."userId" = p_viewer_id AND fm2."userId" = t.id
        ) THEN true
        WHEN NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE b.blocker_id = t.id AND b.blocked_id = p_viewer_id
        )
        AND COALESCE((SELECT visibility FROM "Person" WHERE id = t.id), 'public') != 'private' THEN true
        ELSE false
      END AS has_permission
    FROM unnest(p_target_ids) AS t(id)
    CROSS JOIN unnest(p_permission_types) AS ptype(permission_type)
  )
  SELECT jsonb_object_agg(
    pc.target_id,
    jsonb_agg(pc.permission_type) FILTER (WHERE pc.has_permission)
  ) INTO result
  FROM permission_checks pc
  GROUP BY pc.target_id;

  RETURN COALESCE(result, '{}'::jsonb);
END;
$func$;
