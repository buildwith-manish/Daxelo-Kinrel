-- =============================================================================
-- Daxelo Kinrel — Family Management Permission Enforcement (Phase 14)
-- =============================================================================
-- Tightens the existing fn_update_family_setting RPC so that:
--
--   1. Members get READ-ONLY access (rejected with 403-style error).
--   2. Admins can edit most settings but CANNOT touch Creator-only ones.
--   3. Creators have full control.
--
-- Creator-only settings (admin cannot change):
--   * whoCanEditInfo           (controls who can edit the family's public info)
--   * familyVisibility         (controls whether the family is discoverable)
--   * allowMemberRemoval       (controls whether members can be removed)
--   * requireJoinApproval      (controls whether new joins need approval)
--   * allowMembersToLeave      (kept for back-compat with old rows, but UI
--                               no longer exposes this option)
--
-- Also adds a new RPC `fn_get_current_user_family_role` that returns
-- 'creator' | 'admin' | 'member' for the calling user. Used by the Flutter
-- UI to render read-only vs editable tiles.
--
-- Also drops the `confirmBeforeDeleteRelationship` and
-- `allowMembersToLeave` columns from the JSON returned by
-- fn_get_family_settings (the UI no longer renders them, but the columns
-- remain in the table for back-compat with old data).
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_get_current_user_family_role
--    Returns 'creator' | 'admin' | 'member' | null
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_get_current_user_family_role(
  p_family_id text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
  v_is_creator boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Check creator
  SELECT EXISTS(
    SELECT 1 FROM "Family" WHERE id = p_family_id AND "createdBy" = v_user_id
  ) INTO v_is_creator;

  IF v_is_creator THEN
    RETURN 'creator';
  END IF;

  -- Check role in FamilyMember
  SELECT "role" INTO v_role
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_user_id;

  IF v_role IN ('admin', 'owner') THEN
    RETURN 'admin';
  END IF;

  IF v_role IS NOT NULL THEN
    RETURN 'member';
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_current_user_family_role(text) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_get_family_settings — also include the caller's role
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
  v_user_id text := auth.uid()::text;
  v_role text;
BEGIN
  SELECT * INTO v_settings FROM "FamilySettings" WHERE "familyId" = p_family_id;

  IF NOT FOUND THEN
    -- Create default settings
    INSERT INTO "FamilySettings" ("familyId")
    VALUES (p_family_id)
    ON CONFLICT ("familyId") DO NOTHING;

    SELECT * INTO v_settings FROM "FamilySettings" WHERE "familyId" = p_family_id;
  END IF;

  -- Resolve the calling user's role so the UI can render read-only vs editable
  v_role := public.fn_get_current_user_family_role(p_family_id);

  RETURN json_build_object(
    'success', true,
    'role', v_role,
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
      'requireJoinApproval', v_settings."requireJoinApproval",
      'familyVisibility', v_settings."familyVisibility"
      -- NOTE: allowMembersToLeave and confirmBeforeDeleteRelationship are
      -- intentionally NOT returned. The UI no longer exposes them.
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_settings(text) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_update_family_setting — tightened permission check
--
--    Members: rejected (read-only)
--    Admins:  can edit all settings EXCEPT creator-only ones
--    Creator: full control
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
  v_role text;
  v_creator_only_settings text[] := ARRAY[
    'whoCanEditInfo',
    'familyVisibility',
    'allowMemberRemoval',
    'requireJoinApproval',
    'allowMembersToLeave'
  ];
  v_allowed_settings text[] := ARRAY[
    'whoCanInvite',
    'whoCanAddMembers',
    'whoCanEditInfo',
    'whoCanEditGraph',
    'whoCanChat',
    'whoCanPostStories',
    'whoCanCreateTruthStreak',
    'whoCanAddEvents',
    'allowMemberRemoval',
    'allowMembersToLeave',
    'requireJoinApproval',
    'familyVisibility'
  ];
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Validate setting name (prevent SQL injection via EXECUTE format)
  IF NOT (p_setting_name = ANY(v_allowed_settings)) THEN
    RETURN json_build_object('success', false, 'error', 'Unknown setting: ' || p_setting_name);
  END IF;

  -- Reject the deprecated settings (UI no longer exposes them — old
  -- values remain in the DB but no one can change them).
  IF p_setting_name = 'allowMembersToLeave'
     OR p_setting_name = 'confirmBeforeDeleteRelationship' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'This setting is deprecated and cannot be changed.'
    );
  END IF;

  -- Resolve caller's role
  v_role := public.fn_get_current_user_family_role(p_family_id);

  -- Members are read-only
  IF v_role IS NULL OR v_role = 'member' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'You do not have permission to change family settings. Only Admins and the Creator can modify settings.'
    );
  END IF;

  -- Admins cannot touch creator-only settings
  IF v_role = 'admin' AND p_setting_name = ANY(v_creator_only_settings) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Only the Creator can change this setting.'
    );
  END IF;

  -- Ensure settings row exists
  INSERT INTO "FamilySettings" ("familyId")
  VALUES (p_family_id)
  ON CONFLICT ("familyId") DO NOTHING;

  -- Update the specific setting
  EXECUTE format(
    'UPDATE "FamilySettings" SET %I = %L, "updatedAt" = now() WHERE "familyId" = %L',
    p_setting_name, p_setting_value, p_family_id
  );

  -- Log the activity
  INSERT INTO "FamilyActivityLog" ("id", "familyId", "actorUserId", "actorName", "action", "description")
  VALUES (
    'log_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
    p_family_id,
    v_user_id,
    COALESCE((SELECT name FROM "User" WHERE id = v_user_id),
             CASE WHEN v_role = 'creator' THEN 'Creator'
                  WHEN v_role = 'admin'   THEN 'Admin'
                  ELSE 'Member' END),
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
-- 4. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_get_current_user_family_role' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_current_user_family_role') AS exists;
SELECT 'fn_get_family_settings' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_settings') AS exists;
SELECT 'fn_update_family_setting' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_update_family_setting') AS exists;
