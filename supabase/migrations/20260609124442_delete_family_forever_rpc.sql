-- ============================================================
-- Migration: delete_family_forever_rpc
-- Version:  20260609124442
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ── 1. Ensure indexes exist for fast cascades ────────────────

CREATE INDEX IF NOT EXISTS "FamilyMember_familyId_idx"
  ON "FamilyMember" ("familyId");

CREATE INDEX IF NOT EXISTS "Person_familyId_idx"
  ON "Person" ("familyId");

CREATE INDEX IF NOT EXISTS "Relationship_fromPersonId_idx"
  ON "Relationship" ("fromPersonId");

CREATE INDEX IF NOT EXISTS "Relationship_toPersonId_idx"
  ON "Relationship" ("toPersonId");

-- ── 2. Drop old versions if any ─────────────────────────────

DROP FUNCTION IF EXISTS delete_family_forever(text);
DROP FUNCTION IF EXISTS delete_family_forever(uuid);

-- ── 3. Create the fast RPC ───────────────────────────────────

CREATE OR REPLACE FUNCTION delete_family_forever(p_family_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  text;
  v_allowed  boolean := false;
BEGIN
  v_user_id := auth.uid()::text;

  SELECT (
    EXISTS (
      SELECT 1 FROM "FamilyMember"
       WHERE "familyId" = p_family_id
         AND "userId"   = v_user_id
         AND role IN ('owner', 'admin')
    )
    OR
    EXISTS (
      SELECT 1 FROM "Family"
       WHERE id          = p_family_id
         AND "createdBy" = v_user_id
    )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Not authorized to permanently delete this family';
  END IF;

  DELETE FROM "Family" WHERE id = p_family_id;
END;
$$;

-- ── 4. Grant execute to authenticated users ──────────────────

GRANT EXECUTE ON FUNCTION delete_family_forever(text) TO authenticated;

-- ── 5. Reload PostgREST schema cache ────────────────────────

NOTIFY pgrst, 'reload schema';
