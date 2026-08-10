-- =============================================================================
-- Daxelo Kinrel — Public user profile RPC (Phase 21)
-- =============================================================================
-- Returns a user's name + avatar for display in a 1:1 chat header.
-- SECURITY DEFINER bypasses User table RLS (which only lets you read
-- YOUR OWN row) so the chat header can show the OTHER user's name.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_user_public_profile(
  p_user_id text
)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'name', u.name,
    'username', u.username,
    'avatarUrl', u."avatarUrl",
    'photoThumb', u."photoThumb"
  )
  FROM "User" u
  WHERE u.id = p_user_id
    AND u."deletedAt" IS NULL;
$$;

GRANT EXECUTE ON FUNCTION fn_get_user_public_profile(text) TO authenticated;

-- Verification
SELECT 'fn_get_user_public_profile' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_user_public_profile') AS exists;
