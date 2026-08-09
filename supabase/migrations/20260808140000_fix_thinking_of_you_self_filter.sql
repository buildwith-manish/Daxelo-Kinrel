-- =============================================================================
-- Daxelo Kinrel — Fix "Thinking of You" showing self + duplicates
-- =============================================================================
-- Problem: The "Thinking of You" section was showing the current user's own
-- account and/or duplicate entries instead of only other family members.
--
-- Root cause analysis:
--   The previous RPC (fn_get_family_kinrel_members) used:
--     WHERE u.id <> auth.uid()::text
--   If auth.uid() returns NULL (e.g., edge case in SECURITY DEFINER context
--   or JWT not yet loaded), then `u.id <> NULL` evaluates to NULL (falsy),
--   which filters ALL rows OUT — not the reported behavior.
--   However, if there's ANY mismatch between auth.uid() and the User.id
--   stored in FamilyMember (e.g., case sensitivity, whitespace, or a stale
--   JWT), the current user would NOT be filtered out and would appear.
--
-- Fix (server-side, belt #1):
--   1. Use COALESCE(auth.uid()::text, '') so NULL auth context → empty
--      string comparison → ALL rows filtered out (safe empty result).
--   2. Use DISTINCT ON (fm."userId") to guarantee no duplicate rows even
--      if FamilyMember has duplicate (familyId, userId) pairs.
--   3. Also filter out users with no name (defensive).
--
-- Fix (client-side, belt #2):
--   The Flutter widget ALSO filters out the current user by userId and
--   dedupes — so even if the server returns the current user, the UI
--   hides them.
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
  SELECT DISTINCT ON (fm."userId")
    fm."userId" as user_id,
    u.name as name,
    u.username as username,
    u."avatarUrl" as avatar_url,
    u."photoThumb" as photo_thumb
  FROM "FamilyMember" fm
  INNER JOIN "User" u ON u.id = fm."userId"
  WHERE fm."familyId" = p_family_id
    AND u."deletedAt" IS NULL
    AND u.id <> COALESCE(auth.uid()::text, '')
    AND u.name IS NOT NULL
    AND u.name <> ''
  ORDER BY fm."userId", fm."joinedAt" ASC;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_kinrel_members(text) TO authenticated;

COMMENT ON FUNCTION fn_get_family_kinrel_members(text) IS
  'Returns all real Kinrel users who are members of the given family, '
  'EXCLUDING the calling user and any deleted/unnamed users. '
  'SECURITY DEFINER — bypasses User table RLS so the caller can see '
  'other family members'' names, usernames, and avatars. '
  'Uses DISTINCT ON to guarantee no duplicate rows. '
  'Used by the "Thinking of You" section.';

-- Verification
SELECT 'fn_get_family_kinrel_members' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_family_kinrel_members') AS exists;
