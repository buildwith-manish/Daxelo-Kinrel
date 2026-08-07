-- =============================================================================
-- Daxelo Kinrel — Username Availability Check RPC
-- =============================================================================
-- The public."User" table has RLS that only lets a user read their OWN row.
-- This makes it impossible for the Flutter client to check if a username is
-- already taken by ANOTHER user — the query always returns empty (RLS filters
-- out other users' rows), so every username appears "available".
--
-- This migration adds a SECURITY DEFINER function that checks if a username
-- is taken by ANY user, bypassing the User table's RLS safely.
--
-- Returns true if the username is available (not taken), false if taken.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_username_available(
  p_username text,
  p_exclude_user_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS(
    SELECT 1
    FROM "User" u
    WHERE u."deletedAt" IS NULL
      AND LOWER(u.username) = LOWER(TRIM(p_username))
      -- Optionally exclude the current user (for profile-edit flow where
      -- the user's OWN username should not count as "taken")
      AND (p_exclude_user_id IS NULL OR u.id <> p_exclude_user_id)
  );
$$;

GRANT EXECUTE ON FUNCTION fn_check_username_available(text, text) TO authenticated;

COMMENT ON FUNCTION fn_check_username_available(text, text) IS
  'Checks if a username is available (not taken by any other user). '
  'SECURITY DEFINER — bypasses User table RLS so the client can check '
  'username availability across ALL users, not just the current user. '
  'Returns true if available, false if taken. Case-insensitive.';
