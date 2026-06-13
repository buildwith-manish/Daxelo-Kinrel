-- =============================================================================
-- Kinrel Family Graph V2.1 Blueprint — Supabase Migration
-- Created: 2026-06-12
-- Backward Compatible: All changes are additive (nullable columns, new tables/functions)
-- =============================================================================

-- ── 1. Add valid_from / valid_to to relationships (V2 Timeline support) ──────
ALTER TABLE relationships
  ADD COLUMN IF NOT EXISTS valid_from TIMESTAMPTZ DEFAULT now();

ALTER TABLE relationships
  ADD COLUMN IF NOT EXISTS valid_to TIMESTAMPTZ DEFAULT NULL;

-- ── 2. Add location columns to members (V3 Family Map View support) ──────────
ALTER TABLE members
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;

ALTER TABLE members
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

ALTER TABLE members
  ADD COLUMN IF NOT EXISTS location_name TEXT;

-- ── 3. Add visibility column to members (for PermissionValidator) ─────────────
ALTER TABLE members
  ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public'
  CHECK (visibility IN ('public', 'family_only', 'private'));

-- ── 4. Add is_private column to relationships (for private relationships) ─────
ALTER TABLE relationships
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT false;

-- ── 5. Create graph_state_cache table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS graph_state_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  graph_data JSONB NOT NULL,
  node_count INTEGER NOT NULL DEFAULT 0,
  disclosure_level INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '30 minutes'),
  UNIQUE(family_id, member_id, disclosure_level)
);

-- Index for cache lookups
CREATE INDEX IF NOT EXISTS idx_graph_cache_family_member
  ON graph_state_cache(family_id, member_id, disclosure_level);

CREATE INDEX IF NOT EXISTS idx_graph_cache_expires
  ON graph_state_cache(expires_at);

-- ── 6. Create blocks table (for BlockedMemberGuard) ──────────────────────────
CREATE TABLE IF NOT EXISTS blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(blocker_id, blocked_id),
  CHECK (blocker_id != blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

-- ── 7. Create permissions table (for PermissionValidator) ─────────────────────
CREATE TABLE IF NOT EXISTS permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grantor_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  grantee_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  permission_type TEXT NOT NULL CHECK (permission_type IN (
    'view_profile', 'view_relationship', 'expand_branch', 'edit_relationship', 'admin'
  )),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grantor_id, grantee_id, permission_type)
);

CREATE INDEX IF NOT EXISTS idx_permissions_grantee ON permissions(grantee_id);
CREATE INDEX IF NOT EXISTS idx_permissions_grantor ON permissions(grantor_id);

-- ── 8. RPC: get_family_graph ─────────────────────────────────────────────────
-- Returns JSONB with nodes + edges within max_degree of the specified member
CREATE OR REPLACE FUNCTION get_family_graph(
  p_member_id UUID,
  p_max_degree INT DEFAULT 3,
  p_include_hidden BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
BEGIN
  -- Build the graph using recursive CTE: traverse relationships outward from p_member_id
  WITH RECURSIVE graph_traversal AS (
    -- Base case: the anchor member
    SELECT
      m.id,
      m.display_name,
      m.username,
      m.avatar_url,
      m.gender,
      0 AS degree,
      true AS is_anchor,
      m.is_deceased,
      m.visibility
    FROM members m
    WHERE m.id = p_member_id

    UNION ALL

    -- Recursive case: traverse relationships
    SELECT
      m.id,
      m.display_name,
      m.username,
      m.avatar_url,
      m.gender,
      gt.degree + 1,
      false AS is_anchor,
      m.is_deceased,
      m.visibility
    FROM graph_traversal gt
    JOIN relationships r ON (
      (r.member_a_id = gt.id OR r.member_b_id = gt.id)
    )
    JOIN members m ON (
      (m.id = r.member_a_id AND r.member_b_id = gt.id)
      OR (m.id = r.member_b_id AND r.member_a_id = gt.id)
    )
    WHERE gt.degree < p_max_degree
      AND m.id != p_member_id
      AND (p_include_hidden = true OR m.visibility != 'private')
  ),
  -- Deduplicate members
  unique_members AS (
    SELECT DISTINCT ON (id)
      id, display_name, username, avatar_url, gender,
      MIN(degree) AS degree, is_anchor, is_deceased, visibility
    FROM graph_traversal
    GROUP BY id, display_name, username, avatar_url, gender, is_anchor, is_deceased, visibility
  ),
  -- Collect edges between visible members
  visible_edges AS (
    SELECT
      r.id,
      r.member_a_id,
      r.member_b_id,
      r.relationship_type,
      r.is_private
    FROM relationships r
    WHERE r.member_a_id IN (SELECT id FROM unique_members)
      AND r.member_b_id IN (SELECT id FROM unique_members)
      AND (p_include_hidden = true OR r.is_private = false)
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', um.id,
        'name', um.display_name,
        'username', um.username,
        'avatarUrl', um.avatar_url,
        'gender', um.gender,
        'generationIndex', -um.degree,
        'isAnchor', um.is_anchor,
        'isDeceased', um.is_deceased,
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

-- ── 9. RPC: get_member_branch ────────────────────────────────────────────────
-- Returns JSONB for a specific branch type and depth (for expand/collapse)
CREATE OR REPLACE FUNCTION get_member_branch(
  p_member_id UUID,
  p_branch_type TEXT,
  p_depth INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
  target_member_ids UUID[];
BEGIN
  -- Determine the starting point based on branch type
  CASE p_branch_type
    WHEN 'maternal' THEN
      -- Mother + maternal ancestors
      SELECT ARRAY_AGG(m.id) INTO target_member_ids
      FROM members m
      WHERE m.id IN (
        SELECT r.member_a_id FROM relationships r
        WHERE r.member_b_id = p_member_id AND r.relationship_type IN ('mother', 'maternal_grandmother', 'maternal_grandfather')
        UNION
        SELECT r.member_b_id FROM relationships r
        WHERE r.member_a_id = p_member_id AND r.relationship_type IN ('mother', 'maternal_grandmother', 'maternal_grandfather')
      );

    WHEN 'paternal' THEN
      SELECT ARRAY_AGG(m.id) INTO target_member_ids
      FROM members m
      WHERE m.id IN (
        SELECT r.member_a_id FROM relationships r
        WHERE r.member_b_id = p_member_id AND r.relationship_type IN ('father', 'paternal_grandmother', 'paternal_grandfather')
        UNION
        SELECT r.member_b_id FROM relationships r
        WHERE r.member_a_id = p_member_id AND r.relationship_type IN ('father', 'paternal_grandmother', 'paternal_grandfather')
      );

    WHEN 'cousins' THEN
      -- Children of aunts/uncles
      SELECT ARRAY_AGG(DISTINCT m.id) INTO target_member_ids
      FROM members m
      WHERE m.id IN (
        SELECT r.member_a_id FROM relationships r
        WHERE r.relationship_type IN ('cousin', 'niece', 'nephew')
        AND (r.member_a_id = p_member_id OR r.member_b_id = p_member_id)
      );

    WHEN 'inLaws' THEN
      -- Spouse's parents and siblings
      SELECT ARRAY_AGG(DISTINCT m.id) INTO target_member_ids
      FROM members m
      WHERE m.id IN (
        SELECT r.member_a_id FROM relationships r
        WHERE r.relationship_type IN ('father_in_law', 'mother_in_law', 'brother_in_law', 'sister_in_law')
        AND (r.member_a_id = p_member_id OR r.member_b_id = p_member_id)
      );

    WHEN 'grandchildren' THEN
      -- Children of children
      SELECT ARRAY_AGG(DISTINCT m.id) INTO target_member_ids
      FROM members m
      WHERE m.id IN (
        SELECT r.member_a_id FROM relationships r
        WHERE r.relationship_type IN ('grandson', 'granddaughter')
        AND (r.member_a_id = p_member_id OR r.member_b_id = p_member_id)
      );

    WHEN 'extended' THEN
      -- All beyond immediate family (2+ degrees)
      target_member_ids := ARRAY[]::UUID[];

    ELSE
      target_member_ids := ARRAY[]::UUID[];
  END CASE;

  -- Build branch graph from target members
  WITH branch_members AS (
    SELECT
      m.id, m.display_name, m.username, m.avatar_url, m.gender,
      m.is_deceased, m.visibility
    FROM members m
    WHERE m.id = ANY(COALESCE(target_member_ids, ARRAY[]::UUID[]))
      AND m.visibility != 'private'
  ),
  branch_edges AS (
    SELECT
      r.id, r.member_a_id, r.member_b_id, r.relationship_type, r.is_private
    FROM relationships r
    WHERE (r.member_a_id = ANY(COALESCE(target_member_ids, ARRAY[]::UUID[]))
        OR r.member_b_id = ANY(COALESCE(target_member_ids, ARRAY[]::UUID[])))
      AND r.is_private = false
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', bm.id, 'name', bm.display_name, 'username', bm.username,
        'avatarUrl', bm.avatar_url, 'gender', bm.gender,
        'isDeceased', bm.is_deceased, 'visibility', bm.visibility
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
$$;

-- ── 10. RPC: search_members ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION search_members(
  p_query TEXT,
  p_filters JSONB DEFAULT '{}',
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
BEGIN
  WITH search_results AS (
    SELECT
      m.id, m.display_name, m.username, m.avatar_url, m.gender, m.visibility
    FROM members m
    WHERE (
      m.display_name ILIKE '%' || p_query || '%'
      OR m.username ILIKE '%' || p_query || '%'
      OR similarity(m.display_name, p_query) > 0.3
    )
    AND m.visibility != 'private'
    ORDER BY similarity(m.display_name, p_query) DESC
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
    'total', (SELECT COUNT(*) FROM members m
      WHERE (m.display_name ILIKE '%' || p_query || '%'
          OR m.username ILIKE '%' || p_query || '%')
        AND m.visibility != 'private')
  ) INTO result;

  RETURN result;
END;
$$;

-- ── 11. RPC: resolve_kinship ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_kinship(
  p_member_a_id UUID,
  p_member_b_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
  rel_type TEXT;
BEGIN
  -- Find direct relationship
  SELECT r.relationship_type INTO rel_type
  FROM relationships r
  WHERE (r.member_a_id = p_member_a_id AND r.member_b_id = p_member_b_id)
     OR (r.member_a_id = p_member_b_id AND r.member_b_id = p_member_a_id)
  LIMIT 1;

  IF rel_type IS NOT NULL THEN
    result := jsonb_build_object(
      'relationshipType', rel_type,
      'displayLabel', rel_type,
      'degreeOfSeparation', 1,
      'isMatrilateral', rel_type LIKE 'maternal%' OR rel_type LIKE 'mother%',
      'isPatrilateral', rel_type LIKE 'paternal%' OR rel_type LIKE 'father%',
      'isByMarriage', rel_type LIKE '%in_law%' OR rel_type LIKE '%spouse%'
    );
  ELSE
    result := jsonb_build_object(
      'relationshipType', 'unknown',
      'displayLabel', 'Unknown relationship',
      'degreeOfSeparation', -1,
      'isMatrilateral', false,
      'isPatrilateral', false,
      'isByMarriage', false
    );
  END IF;

  RETURN result;
END;
$$;

-- ── 12. RPC: check_permissions ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_permissions(
  p_viewer_id UUID,
  p_target_ids UUID[],
  p_permission_types TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  result JSONB;
BEGIN
  WITH permission_checks AS (
    SELECT
      t.id AS target_id,
      p.permission_type,
      CASE
        -- Direct permission grant
        WHEN EXISTS (
          SELECT 1 FROM permissions p2
          WHERE p2.grantor_id = t.id
            AND p2.grantee_id = p_viewer_id
            AND p2.permission_type = ANY(p_permission_types)
        ) THEN true
        -- Target has public visibility
        WHEN t.visibility = 'public'
          AND 'view_profile' = ANY(p_permission_types) THEN true
        -- Viewer is same person as target
        WHEN t.id = p_viewer_id THEN true
        -- Viewer and target are in same family
        WHEN EXISTS (
          SELECT 1 FROM family_members fm1
          JOIN family_members fm2 ON fm1.family_id = fm2.family_id
          WHERE fm1.member_id = p_viewer_id AND fm2.member_id = t.id
        ) THEN true
        -- Not blocked
        WHEN NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE b.blocker_id = t.id AND b.blocked_id = p_viewer_id
        )
        AND t.visibility != 'private' THEN true
        ELSE false
      END AS has_permission
    FROM unnest(p_target_ids) AS t(id)
    JOIN members m ON m.id = t.id
    CROSS JOIN unnest(p_permission_types) AS p(permission_type)
  )
  SELECT jsonb_object_agg(
    pc.target_id::text,
    jsonb_agg(pc.permission_type) FILTER (WHERE pc.has_permission)
  ) INTO result
  FROM permission_checks pc
  GROUP BY pc.target_id;

  RETURN COALESCE(result, '{}'::jsonb);
END;
$$;

-- ── 13. Enable RLS on new tables ────────────────────────────────────────────
ALTER TABLE graph_state_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;

-- RLS policies for graph_state_cache
CREATE POLICY "Users can read their own graph cache"
  ON graph_state_cache FOR SELECT
  USING (member_id = auth.uid());

CREATE POLICY "Users can insert their own graph cache"
  ON graph_state_cache FOR INSERT
  WITH CHECK (member_id = auth.uid());

CREATE POLICY "Users can update their own graph cache"
  ON graph_state_cache FOR UPDATE
  USING (member_id = auth.uid());

CREATE POLICY "Users can delete their own graph cache"
  ON graph_state_cache FOR DELETE
  USING (member_id = auth.uid());

-- RLS policies for blocks
CREATE POLICY "Users can read blocks involving them"
  ON blocks FOR SELECT
  USING (blocker_id = auth.uid() OR blocked_id = auth.uid());

CREATE POLICY "Users can block others"
  ON blocks FOR INSERT
  WITH CHECK (blocker_id = auth.uid());

CREATE POLICY "Users can unblock those they blocked"
  ON blocks FOR DELETE
  USING (blocker_id = auth.uid());

-- RLS policies for permissions
CREATE POLICY "Users can read permissions involving them"
  ON permissions FOR SELECT
  USING (grantor_id = auth.uid() OR grantee_id = auth.uid());

CREATE POLICY "Users can grant permissions as grantor"
  ON permissions FOR INSERT
  WITH CHECK (grantor_id = auth.uid());

CREATE POLICY "Grantor can revoke their permissions"
  ON permissions FOR DELETE
  USING (grantor_id = auth.uid());

-- ── 14. Realtime publication for new tables ──────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE relationships;
ALTER PUBLICATION supabase_realtime ADD TABLE members;
ALTER PUBLICATION supabase_realtime ADD TABLE permissions;
ALTER PUBLICATION supabase_realtime ADD TABLE blocks;

-- ── 15. Auto-expire graph cache ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION expire_graph_cache()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM graph_state_cache WHERE expires_at < now();
END;
$$;

-- ── Complete ──────────────────────────────────────────────────────────────────
