-- ============================================================
-- Migration: graph_v2_1_step2_new_tables
-- Version:  20260612180311
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- graph_state_cache
CREATE TABLE IF NOT EXISTS graph_state_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id TEXT NOT NULL REFERENCES "Family"(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES "Person"(id) ON DELETE CASCADE,
  graph_data JSONB NOT NULL,
  node_count INTEGER NOT NULL DEFAULT 0,
  disclosure_level INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '30 minutes'),
  UNIQUE(family_id, member_id, disclosure_level)
);

CREATE INDEX IF NOT EXISTS idx_graph_cache_family_member
  ON graph_state_cache(family_id, member_id, disclosure_level);

CREATE INDEX IF NOT EXISTS idx_graph_cache_expires
  ON graph_state_cache(expires_at);

-- blocks
CREATE TABLE IF NOT EXISTS blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id TEXT NOT NULL REFERENCES "Person"(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES "Person"(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(blocker_id, blocked_id),
  CHECK (blocker_id != blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

-- permissions
CREATE TABLE IF NOT EXISTS permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grantor_id TEXT NOT NULL REFERENCES "Person"(id) ON DELETE CASCADE,
  grantee_id TEXT NOT NULL REFERENCES "Person"(id) ON DELETE CASCADE,
  permission_type TEXT NOT NULL CHECK (permission_type IN (
    'view_profile', 'view_relationship', 'expand_branch', 'edit_relationship', 'admin'
  )),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grantor_id, grantee_id, permission_type)
);

CREATE INDEX IF NOT EXISTS idx_permissions_grantee ON permissions(grantee_id);
CREATE INDEX IF NOT EXISTS idx_permissions_grantor ON permissions(grantor_id);
