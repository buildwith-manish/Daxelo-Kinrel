-- ============================================================
-- Migration: create_fast_path_rpc_functions
-- Version:  20260609111046
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ================================================================
-- delete_family_forever(family_id)
-- Single-transaction hard delete. Verifies caller is owner/creator,
-- then cascades everything in one server-side call.
-- Flutter: supabase.rpc('delete_family_forever', {'family_id': id})
-- ================================================================
CREATE OR REPLACE FUNCTION public.delete_family_forever(p_family_id TEXT)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_uid TEXT := (auth.uid())::text;
  v_is_authorized BOOLEAN;
BEGIN
  -- 1. Auth guard: must be creator or owner/admin
  SELECT EXISTS (
    SELECT 1 FROM "Family"
    WHERE id = p_family_id
      AND (
        "createdBy" = v_uid
        OR id IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = v_uid AND role IN ('owner', 'admin')
        )
      )
  ) INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  -- 2. Hard delete — FK CASCADE handles all child rows automatically
  DELETE FROM "Family" WHERE id = p_family_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_family_forever(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_family_forever(text) TO authenticated;


-- ================================================================
-- add_family_member(family_id, user_id, role)
-- Atomically adds a member and bumps memberCount in one call.
-- Flutter: supabase.rpc('add_family_member', {...})
-- ================================================================
CREATE OR REPLACE FUNCTION public.add_family_member(
  p_family_id  TEXT,
  p_user_id    TEXT,
  p_role       TEXT DEFAULT 'member'
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_uid       TEXT := (auth.uid())::text;
  v_authorized BOOLEAN;
  v_new_id    TEXT;
BEGIN
  -- 1. Auth guard: caller must be creator, owner, or admin
  --    OR caller is adding themselves (self-join via invite)
  SELECT EXISTS (
    SELECT 1 FROM "Family"
    WHERE id = p_family_id
      AND (
        "createdBy" = v_uid
        OR id IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = v_uid AND role IN ('owner','admin')
        )
      )
  ) OR v_uid = p_user_id
  INTO v_authorized;

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  -- 2. Upsert member (ignore duplicate)
  INSERT INTO "FamilyMember"("familyId", "userId", role, "joinedAt")
    VALUES (p_family_id, p_user_id, p_role, NOW())
    ON CONFLICT ("familyId", "userId") DO NOTHING
  RETURNING id INTO v_new_id;

  -- 3. Bump memberCount atomically
  IF v_new_id IS NOT NULL THEN
    UPDATE "Family"
      SET "memberCount" = "memberCount" + 1,
          "lastActivityAt" = NOW()
    WHERE id = p_family_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_new_id,
    'already_member', v_new_id IS NULL
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_family_member(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.add_family_member(text, text, text) TO authenticated;


-- ================================================================
-- restore_family(family_id)
-- Clears deletedAt in one call.
-- Flutter: supabase.rpc('restore_family', {'family_id': id})
-- ================================================================
CREATE OR REPLACE FUNCTION public.restore_family(p_family_id TEXT)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_uid TEXT := (auth.uid())::text;
  v_authorized BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM "Family"
    WHERE id = p_family_id
      AND (
        "createdBy" = v_uid
        OR id IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = v_uid AND role IN ('owner', 'admin')
        )
      )
  ) INTO v_authorized;

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  UPDATE "Family"
    SET "deletedAt" = NULL,
        "updatedAt" = NOW()
  WHERE id = p_family_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.restore_family(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.restore_family(text) TO authenticated;
