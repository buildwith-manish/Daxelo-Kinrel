-- =============================================================================
-- Daxelo Kinrel — Family Management Enforcement RPCs
-- =============================================================================
-- RPCs that ENFORCE permissions across the app:
--   1. fn_check_family_permission — checks if user has permission for an action
--   2. fn_get_family_members_with_roles — returns all members with roles + badges
--   3. fn_get_family_activity_log — returns the activity log
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_check_family_permission — enforcement gate
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_check_family_permission(
  p_family_id text,
  p_permission text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_setting_value text;
  v_user_role text;
  v_is_creator boolean;
BEGIN
  IF v_user_id IS NULL THEN RETURN false; END IF;

  -- Get the permission setting (default to 'everyone' if no settings row)
  EXECUTE format(
    'SELECT COALESCE((SELECT %I FROM "FamilySettings" WHERE "familyId" = $1), ''everyone'')',
    p_permission
  ) INTO v_setting_value USING p_family_id;

  -- Get user's role
  SELECT fm."role" INTO v_user_role
  FROM "FamilyMember" fm
  WHERE fm."familyId" = p_family_id AND fm."userId" = v_user_id
  LIMIT 1;

  -- Check if creator
  SELECT EXISTS(
    SELECT 1 FROM "Family" WHERE id = p_family_id AND "createdBy" = v_user_id
  ) INTO v_is_creator;

  -- If creator, always allowed
  IF v_is_creator THEN RETURN true; END IF;

  -- Evaluate based on setting value
  CASE v_setting_value
    WHEN 'everyone' THEN
      RETURN v_user_role IS NOT NULL; -- any family member
    WHEN 'admins' THEN
      RETURN v_user_role IN ('admin', 'owner');
    WHEN 'creator' THEN
      RETURN false; -- only creator (already checked above)
    ELSE
      RETURN false;
  END CASE;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_check_family_permission(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_get_family_members_with_roles — for member management UI
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_get_family_members_with_roles(
  p_family_id text
)
RETURNS TABLE(
  user_id text,
  name text,
  username text,
  avatar_url text,
  role text,
  is_creator boolean,
  joined_at timestamp without time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    fm."userId" as user_id,
    u.name as name,
    u.username as username,
    u."avatarUrl" as avatar_url,
    COALESCE(fm."role", 'member') as role,
    (f."createdBy" = fm."userId") as is_creator,
    fm."joinedAt" as joined_at
  FROM "FamilyMember" fm
  INNER JOIN "User" u ON u.id = fm."userId"
  INNER JOIN "Family" f ON f.id = fm."familyId"
  WHERE fm."familyId" = p_family_id
    AND u."deletedAt" IS NULL
  ORDER BY
    CASE
      WHEN f."createdBy" = fm."userId" THEN 0
      WHEN fm."role" IN ('admin', 'owner') THEN 1
      ELSE 2
    END,
    fm."joinedAt" ASC;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_members_with_roles(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_get_family_activity_log — returns activity log entries
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_get_family_activity_log(
  p_family_id text,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id text,
  actor_user_id text,
  actor_name text,
  action text,
  description text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    al."id",
    al."actorUserId" as actor_user_id,
    al."actorName" as actor_name,
    al."action",
    al."description",
    al."createdAt" as created_at
  FROM "FamilyActivityLog" al
  WHERE al."familyId" = p_family_id
  ORDER BY al."createdAt" DESC
  LIMIT LEAST(p_limit, 100)
  OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_activity_log(text, int, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_check_family_permission' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_check_family_permission') AS exists;
SELECT 'fn_get_family_members_with_roles' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_members_with_roles') AS exists;
SELECT 'fn_get_family_activity_log' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_activity_log') AS exists;
