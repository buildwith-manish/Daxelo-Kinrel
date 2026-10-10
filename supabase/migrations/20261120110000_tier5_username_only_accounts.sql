-- =============================================================================
-- Daxelo Kinrel — Tier 5 Feature 5.2: Public username discovery (no phone/email needed)
-- =============================================================================
-- Lets a user sign up with just a @username (no email or phone required).
-- The username is already unique on the User table (added by an earlier
-- migration). This migration adds:
--   • isUsernameOnlyAccount boolean DEFAULT false — when true, the user
--     has no email/phone and is discoverable ONLY by their @username.
--   • showOnUsernameSearch boolean DEFAULT true — lets the user opt out
--     of being discoverable by username search (privacy).
--
-- The auth flow change (allowing null email when isUsernameOnlyAccount=true)
-- is enforced in the NestJS auth module — the schema just permits it.
-- =============================================================================

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "isUsernameOnlyAccount" boolean NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "showOnUsernameSearch" boolean NOT NULL DEFAULT true;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_username_only_account — flips the caller's account to username-only
-- (or back). When set to true, the user must have a non-null, non-empty
-- username (enforced by the CHECK).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_username_only_account(
  p_is_username_only boolean,
  p_show_on_username_search boolean DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_username text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT username INTO v_username FROM "User" WHERE id = v_user_id;
  IF p_is_username_only AND (v_username IS NULL OR btrim(v_username) = '') THEN
    RETURN json_build_object('success', false, 'error', 'no_username',
      'message', 'Set a @username before flipping to a username-only account.');
  END IF;

  UPDATE "User" SET
    "isUsernameOnlyAccount" = p_is_username_only,
    "showOnUsernameSearch" = COALESCE(p_show_on_username_search, "showOnUsernameSearch"),
    "updatedAt" = now()
    WHERE id = v_user_id;

  RETURN json_build_object(
    'success', true,
    'userId', v_user_id,
    'isUsernameOnlyAccount', p_is_username_only,
    'showOnUsernameSearch', COALESCE(p_show_on_username_search, (SELECT "showOnUsernameSearch" FROM "User" WHERE id = v_user_id))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_username_only_account(boolean, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_search_users_by_username — search the public user catalog by username.
-- Returns users where showOnUsernameSearch=true AND username matches the
-- prefix. Excludes the caller. Capped at 20 results.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_search_users_by_username(
  p_query text,
  p_limit int DEFAULT 20
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_trimmed text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  v_trimmed := btrim(p_query);
  IF v_trimmed IS NULL OR char_length(v_trimmed) < 2 THEN
    RETURN json_build_object('success', true, 'results', '[]'::jsonb);
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', u.id,
      'name', u.name,
      'username', u.username,
      'avatarUrl', u."avatarUrl"
    ) ORDER BY similarity(u.username, v_trimmed) DESC)
    FROM "User" u
    WHERE u."showOnUsernameSearch" = true
      AND u.id <> v_user_id
      AND u.username IS NOT NULL
      AND u.username ILIKE v_trimmed || '%'
    LIMIT GREATEST(LEAST(p_limit, 50), 1)
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_search_users_by_username(text, int) TO authenticated;

-- Verification
SELECT 'User.isUsernameOnlyAccount' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'isUsernameOnlyAccount'
       ) AS exists;
SELECT 'User.showOnUsernameSearch' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'showOnUsernameSearch'
       ) AS exists;
SELECT 'fn_set_username_only_account' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_username_only_account') AS exists;
SELECT 'fn_search_users_by_username' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_search_users_by_username') AS exists;
