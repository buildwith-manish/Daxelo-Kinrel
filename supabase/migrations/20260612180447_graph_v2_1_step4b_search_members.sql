-- ============================================================
-- Migration: graph_v2_1_step4b_search_members
-- Version:  20260612180447
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

CREATE OR REPLACE FUNCTION search_members(
  p_query TEXT,
  p_filters JSONB DEFAULT '{}',
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $func$
DECLARE
  result JSONB;
BEGIN
  WITH search_results AS (
    SELECT p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, p.visibility
    FROM "Person" p
    WHERE (
      p.name ILIKE '%' || p_query || '%'
      OR p.username ILIKE '%' || p_query || '%'
    )
    AND COALESCE(p.visibility, 'public') != 'private'
    ORDER BY
      CASE WHEN p.name ILIKE p_query || '%' THEN 0 ELSE 1 END,
      p.name
    LIMIT p_limit
    OFFSET p_offset
  )
  SELECT jsonb_build_object(
    'results', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', sr.id, 'name', sr.display_name, 'username', sr.username,
        'avatarUrl', sr.avatar_url, 'gender', sr.gender, 'visibility', sr.visibility
      )) FROM search_results sr),
      '[]'::jsonb
    ),
    'total', (SELECT COUNT(*) FROM "Person" p
      WHERE (p.name ILIKE '%' || p_query || '%' OR p.username ILIKE '%' || p_query || '%')
        AND COALESCE(p.visibility, 'public') != 'private')
  ) INTO result;

  RETURN result;
END;
$func$;
