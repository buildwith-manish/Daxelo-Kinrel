-- =============================================================================
-- Daxelo-Kinrel — Chat member names helper
-- =============================================================================
-- The public."User" table has RLS that only lets a user read their own row,
-- which means the Flutter chat UI can't fetch display names for OTHER family
-- members. Without this, every other member shows up as "Member" in the chat
-- header.
--
-- This migration adds a SECURITY DEFINER function that returns
-- (userId, name) for all members of a given family, bypassing the User
-- table's RLS. The function is callable by any authenticated user, but it
-- only returns rows for families the caller is a member of (so you can't
-- enumerate members of families you don't belong to).
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_family_member_names(family_id text)
RETURNS TABLE ("userId" text, name text, username text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        fm."userId",
        COALESCE(NULLIF(u.name, ''), NULLIF(u.username, ''),
                 SPLIT_PART(u.email, '@', 1), 'Member') AS name,
        u.username
    FROM "FamilyMember" fm
    LEFT JOIN "User" u ON u.id = fm."userId"
    WHERE fm."familyId" = family_id
      -- SECURITY: only return members if the caller is also a member
      -- of this family. This prevents enumeration of families the
      -- caller doesn't belong to.
      AND EXISTS (
          SELECT 1
          FROM "FamilyMember" fm2
          WHERE fm2."familyId" = family_id
            AND fm2."userId" = auth.uid()::text
      );
$$;

-- Allow any authenticated user to call the function. The function itself
-- enforces family membership, so this GRANT is safe.
GRANT EXECUTE ON FUNCTION fn_get_family_member_names(text) TO authenticated;

COMMENT ON FUNCTION fn_get_family_member_names(text) IS
    'Returns (userId, name, username) for all members of the given family. '
    'SECURITY DEFINER — bypasses User table RLS so chat UI can show real names. '
    'Self-gates on family membership: caller must be a member of family_id.';
