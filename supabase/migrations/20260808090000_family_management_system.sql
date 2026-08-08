-- =============================================================================
-- Daxelo Kinrel — Family Management System (Admin & Creator Controls)
-- =============================================================================
-- Creates a FamilySettings table with granular permission controls for
-- each family, similar to WhatsApp group admin settings but tailored
-- for family management.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. FamilySettings table
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "FamilySettings" (
  "familyId" text PRIMARY KEY REFERENCES "Family"(id) ON DELETE CASCADE,
  -- Permission levels: 'everyone', 'admins', 'creator'
  "whoCanInvite" text NOT NULL DEFAULT 'everyone',
  "whoCanAddMembers" text NOT NULL DEFAULT 'everyone',
  "whoCanEditInfo" text NOT NULL DEFAULT 'creator',
  "whoCanEditGraph" text NOT NULL DEFAULT 'everyone',
  "whoCanChat" text NOT NULL DEFAULT 'everyone',
  "whoCanPostStories" text NOT NULL DEFAULT 'everyone',
  "whoCanCreateTruthStreak" text NOT NULL DEFAULT 'everyone',
  "whoCanAddEvents" text NOT NULL DEFAULT 'everyone',
  -- Safety controls
  "allowMemberRemoval" boolean NOT NULL DEFAULT true,
  "allowMembersToLeave" boolean NOT NULL DEFAULT true,
  "confirmBeforeDeleteRelationship" boolean NOT NULL DEFAULT true,
  -- Join approval
  "requireJoinApproval" boolean NOT NULL DEFAULT false,
  -- Privacy: 'private', 'invite_only', 'public'
  "familyVisibility" text NOT NULL DEFAULT 'invite_only',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

-- RLS: all family members can read settings; only creator/admins can update
ALTER TABLE "FamilySettings" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "FamilySettings select" ON "FamilySettings";
CREATE POLICY "FamilySettings select" ON "FamilySettings"
  FOR SELECT TO authenticated
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "FamilySettings update" ON "FamilySettings";
CREATE POLICY "FamilySettings update" ON "FamilySettings"
  FOR UPDATE TO authenticated
  USING (
    "familyId" IN (
      SELECT fm."familyId" FROM "FamilyMember" fm
      JOIN "Family" f ON f.id = fm."familyId"
      WHERE fm."userId" = auth.uid()::text
        AND (fm."role" = 'admin' OR fm."role" = 'owner' OR f."createdBy" = auth.uid()::text)
    )
  );

DROP POLICY IF EXISTS "FamilySettings insert" ON "FamilySettings";
CREATE POLICY "FamilySettings insert" ON "FamilySettings"
  FOR INSERT TO authenticated
  WITH CHECK (
    "familyId" IN (
      SELECT fm."familyId" FROM "FamilyMember" fm
      JOIN "Family" f ON f.id = fm."familyId"
      WHERE fm."userId" = auth.uid()::text
        AND (fm."role" = 'admin' OR fm."role" = 'owner' OR f."createdBy" = auth.uid()::text)
    )
  );

-- Add to realtime
ALTER TABLE "FamilySettings" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'FamilySettings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "FamilySettings";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. FamilyActivityLog table
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "FamilyActivityLog" (
  "id" text PRIMARY KEY,
  "familyId" text NOT NULL REFERENCES "Family"(id) ON DELETE CASCADE,
  "actorUserId" text NOT NULL,
  "actorName" text NOT NULL DEFAULT 'Unknown',
  "action" text NOT NULL,
  "description" text NOT NULL DEFAULT '',
  "metadata" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "FamilyActivityLog_family_idx" ON "FamilyActivityLog"("familyId");
CREATE INDEX IF NOT EXISTS "FamilyActivityLog_created_idx" ON "FamilyActivityLog"("createdAt" DESC);

ALTER TABLE "FamilyActivityLog" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "FamilyActivityLog select" ON "FamilyActivityLog";
CREATE POLICY "FamilyActivityLog select" ON "FamilyActivityLog"
  FOR SELECT TO authenticated
  USING (
    "familyId" IN (
      SELECT fm."familyId" FROM "FamilyMember" fm
      JOIN "Family" f ON f.id = fm."familyId"
      WHERE fm."userId" = auth.uid()::text
        AND (fm."role" = 'admin' OR fm."role" = 'owner' OR f."createdBy" = auth.uid()::text)
    )
  );

DROP POLICY IF EXISTS "FamilyActivityLog insert" ON "FamilyActivityLog";
CREATE POLICY "FamilyActivityLog insert" ON "FamilyActivityLog"
  FOR INSERT TO authenticated
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_get_family_settings — returns settings (creates defaults if missing)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_get_family_settings(
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings record;
BEGIN
  SELECT * INTO v_settings FROM "FamilySettings" WHERE "familyId" = p_family_id;

  IF NOT FOUND THEN
    -- Create default settings
    INSERT INTO "FamilySettings" ("familyId")
    VALUES (p_family_id)
    ON CONFLICT ("familyId") DO NOTHING;

    SELECT * INTO v_settings FROM "FamilySettings" WHERE "familyId" = p_family_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'settings', json_build_object(
      'whoCanInvite', v_settings."whoCanInvite",
      'whoCanAddMembers', v_settings."whoCanAddMembers",
      'whoCanEditInfo', v_settings."whoCanEditInfo",
      'whoCanEditGraph', v_settings."whoCanEditGraph",
      'whoCanChat', v_settings."whoCanChat",
      'whoCanPostStories', v_settings."whoCanPostStories",
      'whoCanCreateTruthStreak', v_settings."whoCanCreateTruthStreak",
      'whoCanAddEvents', v_settings."whoCanAddEvents",
      'allowMemberRemoval', v_settings."allowMemberRemoval",
      'allowMembersToLeave', v_settings."allowMembersToLeave",
      'confirmBeforeDeleteRelationship', v_settings."confirmBeforeDeleteRelationship",
      'requireJoinApproval', v_settings."requireJoinApproval",
      'familyVisibility', v_settings."familyVisibility"
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_settings(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. fn_update_family_setting — updates a single setting
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_update_family_setting(
  p_family_id text,
  p_setting_name text,
  p_setting_value text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_admin boolean := false;
  v_settings record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Check if user is admin or creator
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember" fm
    JOIN "Family" f ON f.id = fm."familyId"
    WHERE fm."familyId" = p_family_id
      AND fm."userId" = v_user_id
      AND (fm."role" IN ('admin', 'owner') OR f."createdBy" = v_user_id)
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Ensure settings row exists
  INSERT INTO "FamilySettings" ("familyId")
  VALUES (p_family_id)
  ON CONFLICT ("familyId") DO NOTHING;

  -- Update the specific setting
  EXECUTE format('UPDATE "FamilySettings" SET %I = %L, "updatedAt" = now() WHERE "familyId" = %L',
    p_setting_name, p_setting_value, p_family_id);

  -- Log the activity
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id,
    v_user_id,
    COALESCE((SELECT name FROM "User" WHERE id = v_user_id), 'Admin'),
    'setting_changed',
    'Setting "' || p_setting_name || '" changed to "' || p_setting_value || '"'
  );

  RETURN json_build_object('success', true, 'message', 'Setting updated');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_update_family_setting(text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. fn_promote_member — promote a member to admin
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_promote_member(
  p_family_id text,
  p_member_user_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_creator boolean := false;
  v_member_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Only creator can promote
  SELECT EXISTS(
    SELECT 1 FROM "Family" WHERE id = p_family_id AND "createdBy" = v_user_id
  ) INTO v_is_creator;

  IF NOT v_is_creator THEN
    RETURN json_build_object('success', false, 'error', 'Only the family creator can promote members');
  END IF;

  -- Promote
  UPDATE "FamilyMember" SET "role" = 'admin'
  WHERE "familyId" = p_family_id AND "userId" = p_member_user_id;

  -- Log
  SELECT name INTO v_member_name FROM "User" WHERE id = p_member_user_id;
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id, v_user_id,
    COALESCE((SELECT name FROM "User" WHERE id = v_user_id), 'Creator'),
    'member_promoted',
    COALESCE(v_member_name, 'A member') || ' was promoted to Admin'
  );

  RETURN json_build_object('success', true, 'message', 'Member promoted to admin');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_promote_member(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. fn_demote_member — demote admin back to member
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_demote_member(
  p_family_id text,
  p_member_user_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_creator boolean := false;
  v_member_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM "Family" WHERE id = p_family_id AND "createdBy" = v_user_id
  ) INTO v_is_creator;

  IF NOT v_is_creator THEN
    RETURN json_build_object('success', false, 'error', 'Only the family creator can demote admins');
  END IF;

  UPDATE "FamilyMember" SET "role" = 'member'
  WHERE "familyId" = p_family_id AND "userId" = p_member_user_id AND "role" = 'admin';

  SELECT name INTO v_member_name FROM "User" WHERE id = p_member_user_id;
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id, v_user_id,
    COALESCE((SELECT name FROM "User" WHERE id = v_user_id), 'Creator'),
    'member_demoted',
    COALESCE(v_member_name, 'An admin') || ' was demoted to Member'
  );

  RETURN json_build_object('success', true, 'message', 'Admin demoted to member');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_demote_member(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. fn_remove_member — remove a member from the family
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_remove_member(
  p_family_id text,
  p_member_user_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_admin boolean := false;
  v_member_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Can't remove yourself
  IF v_user_id = p_member_user_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot remove yourself');
  END IF;

  -- Check if caller is admin or creator
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember" fm
    JOIN "Family" f ON f.id = fm."familyId"
    WHERE fm."familyId" = p_family_id
      AND fm."userId" = v_user_id
      AND (fm."role" IN ('admin', 'owner') OR f."createdBy" = v_user_id)
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Check settings allow removal
  IF NOT COALESCE(
    (SELECT "allowMemberRemoval" FROM "FamilySettings" WHERE "familyId" = p_family_id),
    true
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Member removal is disabled');
  END IF;

  -- Remove the member
  DELETE FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = p_member_user_id;

  SELECT name INTO v_member_name FROM "User" WHERE id = p_member_user_id;
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id, v_user_id,
    COALESCE((SELECT name FROM "User" WHERE id = v_user_id), 'Admin'),
    'member_removed',
    COALESCE(v_member_name, 'A member') || ' was removed from the family'
  );

  RETURN json_build_object('success', true, 'message', 'Member removed');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_remove_member(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. fn_transfer_ownership — transfer family ownership
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_transfer_ownership(
  p_family_id text,
  p_new_owner_user_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_creator boolean := false;
  v_new_owner_name text;
  v_old_owner_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM "Family" WHERE id = p_family_id AND "createdBy" = v_user_id
  ) INTO v_is_creator;

  IF NOT v_is_creator THEN
    RETURN json_build_object('success', false, 'error', 'Only the creator can transfer ownership');
  END IF;

  -- Update family creator
  UPDATE "Family" SET "createdBy" = p_new_owner_user_id WHERE id = p_family_id;

  -- Promote new owner to 'owner' role
  UPDATE "FamilyMember" SET "role" = 'owner'
  WHERE "familyId" = p_family_id AND "userId" = p_new_owner_user_id;

  -- Demote old creator to 'admin'
  UPDATE "FamilyMember" SET "role" = 'admin'
  WHERE "familyId" = p_family_id AND "userId" = v_user_id;

  -- Log
  SELECT name INTO v_new_owner_name FROM "User" WHERE id = p_new_owner_user_id;
  SELECT name INTO v_old_owner_name FROM "User" WHERE id = v_user_id;
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id, v_user_id,
    COALESCE(v_old_owner_name, 'Creator'),
    'ownership_transferred',
    'Ownership transferred to ' || COALESCE(v_new_owner_name, 'a new owner')
  );

  RETURN json_build_object('success', true, 'message', 'Ownership transferred');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_transfer_ownership(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'FamilySettings table' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'FamilySettings') AS exists;
SELECT 'FamilyActivityLog table' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'FamilyActivityLog') AS exists;
SELECT 'fn_get_family_settings' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_settings') AS exists;
SELECT 'fn_update_family_setting' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_update_family_setting') AS exists;
SELECT 'fn_promote_member' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_promote_member') AS exists;
SELECT 'fn_demote_member' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_demote_member') AS exists;
SELECT 'fn_remove_member' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_remove_member') AS exists;
SELECT 'fn_transfer_ownership' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_transfer_ownership') AS exists;
