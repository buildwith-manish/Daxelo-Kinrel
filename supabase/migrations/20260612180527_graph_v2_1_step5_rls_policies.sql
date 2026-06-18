-- ============================================================
-- Migration: graph_v2_1_step5_rls_policies
-- Version:  20260612180527
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


ALTER TABLE graph_state_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;

-- graph_state_cache policies (keyed on member_id = Person.id = text, auth.uid() = uuid; cast for safety)
CREATE POLICY "Users can read their own graph cache"
  ON graph_state_cache FOR SELECT
  USING (member_id = auth.uid()::text);

CREATE POLICY "Users can insert their own graph cache"
  ON graph_state_cache FOR INSERT
  WITH CHECK (member_id = auth.uid()::text);

CREATE POLICY "Users can update their own graph cache"
  ON graph_state_cache FOR UPDATE
  USING (member_id = auth.uid()::text);

CREATE POLICY "Users can delete their own graph cache"
  ON graph_state_cache FOR DELETE
  USING (member_id = auth.uid()::text);

-- blocks policies
CREATE POLICY "Users can read blocks involving them"
  ON blocks FOR SELECT
  USING (blocker_id = auth.uid()::text OR blocked_id = auth.uid()::text);

CREATE POLICY "Users can block others"
  ON blocks FOR INSERT
  WITH CHECK (blocker_id = auth.uid()::text);

CREATE POLICY "Users can unblock those they blocked"
  ON blocks FOR DELETE
  USING (blocker_id = auth.uid()::text);

-- permissions policies
CREATE POLICY "Users can read permissions involving them"
  ON permissions FOR SELECT
  USING (grantor_id = auth.uid()::text OR grantee_id = auth.uid()::text);

CREATE POLICY "Users can grant permissions as grantor"
  ON permissions FOR INSERT
  WITH CHECK (grantor_id = auth.uid()::text);

CREATE POLICY "Grantor can revoke their permissions"
  ON permissions FOR DELETE
  USING (grantor_id = auth.uid()::text);
