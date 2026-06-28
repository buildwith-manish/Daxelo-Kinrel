-- =============================================================================
-- Daxelo-Kinrel — Global user search RPC for "Find on Kinrel" feature
-- =============================================================================
-- The public."User" table has RLS that only lets a user read their own row.
-- This makes it impossible for the Flutter client to search ALL Kinrel users
-- for the "Find on Kinrel" add-member flow.
--
-- This migration adds a SECURITY DEFINER function that searches all users
-- with public profiles, bypassing the User table's RLS safely. The function:
--   - Only returns users where profileVisibility = 'public' (or NULL)
--   - Excludes the current user from results
--   - Excludes users with deletedAt IS NOT NULL
--   - Searches by name, username (ILIKE, case-insensitive)
--   - Returns: id, name, username, email, avatarUrl, photoThumb, bio, gender
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_search_kinrel_users(
  p_query text,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id text,
  name text,
  username text,
  email text,
  "avatarUrl" text,
  "photoThumb" text,
  bio text,
  gender text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    u.name,
    u.username,
    u.email,
    u."avatarUrl",
    u."photoThumb",
    u.bio,
    u.gender
  FROM "User" u
  WHERE u."deletedAt" IS NULL
    -- Only return users with public profiles (or NULL = default public)
    AND (u."profileVisibility" IS NULL OR u."profileVisibility" = 'public')
    -- Exclude the current user from search results
    AND u.id <> auth.uid()::text
    -- Search by name or username (case-insensitive ILIKE)
    AND (
      u.name ILIKE '%' || TRIM(p_query) || '%'
      OR u.username ILIKE '%' || TRIM(p_query) || '%'
      OR u.email ILIKE '%' || TRIM(p_query) || '%'
    )
  ORDER BY
    -- Exact username match first
    CASE WHEN u.username ILIKE TRIM(p_query) THEN 0 ELSE 1 END,
    -- Then exact name match
    CASE WHEN u.name ILIKE TRIM(p_query) THEN 0 ELSE 1 END,
    u.name ASC
  LIMIT LEAST(p_limit, 100)  -- cap at 100 to prevent abuse
  OFFSET GREATEST(p_offset, 0);
$$;

-- Allow any authenticated user to call the function
GRANT EXECUTE ON FUNCTION fn_search_kinrel_users(text, int, int) TO authenticated;

COMMENT ON FUNCTION fn_search_kinrel_users(text, int, int) IS
  'Searches all public-profile Kinrel users by name/username/email. '
  'SECURITY DEFINER — bypasses User table RLS so users can find each other. '
  'Excludes the caller and deleted/private users. Returns at most 100 rows.';
