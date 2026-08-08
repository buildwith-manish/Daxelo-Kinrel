-- =============================================================================
-- Daxelo Kinrel — Fix "Thinking of You" member query (RLS bypass)
-- =============================================================================
-- The User table has RLS that only lets a user read THEIR OWN row.
-- The Flutter client's JOIN query (FamilyMember → User) returns null
-- for the User data of OTHER family members, so the "Thinking of You"
-- section shows an empty list (or falls back to old cached data).
--
-- This RPC bypasses RLS via SECURITY DEFINER to return all family
-- members with their User table data — only real registered Kinrel
-- users who are actual family members.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_family_kinrel_members(
  p_family_id text
)
RETURNS TABLE(
  user_id text,
  name text,
  username text,
  avatar_url text,
  photo_thumb text
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
    u."photoThumb" as photo_thumb
  FROM "FamilyMember" fm
  INNER JOIN "User" u ON u.id = fm."userId"
  WHERE fm."familyId" = p_family_id
    AND u."deletedAt" IS NULL
    AND u.id <> auth.uid()::text
  ORDER BY fm."joinedAt" ASC;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_kinrel_members(text) TO authenticated;

COMMENT ON FUNCTION fn_get_family_kinrel_members(text) IS
  'Returns all real Kinrel users who are members of the given family. '
  'SECURITY DEFINER — bypasses User table RLS so the caller can see '
  'other family members'' names, usernames, and avatars. Excludes '
  'deleted users and the caller. Used by the "Thinking of You" section.';

-- Verification
SELECT 'fn_get_family_kinrel_members' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_kinrel_members') AS exists;
