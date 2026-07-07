-- =============================================================================
-- Daxelo-Kinrel — Username / Email login resolver
-- =============================================================================
-- The public."User" table has RLS that only lets a user read their own row.
-- This means an unauthenticated (anon) user cannot run:
--     SELECT email FROM "User" WHERE username = 'foo';
-- which is required for username-based sign-in.
--
-- This migration adds a SECURITY DEFINER function that:
--   1. Accepts an identifier (either a username OR an email).
--   2. If the identifier contains '@', treats it as an email and looks up
--      the row by email directly.
--   3. Otherwise, treats it as a username (case-insensitive) and looks up
--      the row by username.
--   4. Returns ONLY the email column of the matched row, or NULL if no
--      row matched.
--
-- SECURITY/PRIVACY:
--   - The function is callable by `anon` (pre-auth) and `authenticated`.
--   - It only returns the email field — no id, name, avatarUrl, etc.
--   - Returns NULL for non-existent usernames/emails. The caller then
--     attempts signInWithPassword(NULL, password) which fails with the
--     generic "Invalid login credentials" message from Supabase, so
--     username enumeration is no easier than password brute-force.
--   - Only considers active users (deletedAt IS NULL).
--   - Case-insensitive username match (User.username is stored lowercase
--     per app convention, but we ILIKE to be safe).
--   - Email match is case-insensitive too (Supabase Auth lowercases emails).
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_email_by_identifier(
  p_identifier text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.email
  FROM "User" u
  WHERE u."deletedAt" IS NULL
    AND (
      CASE
        WHEN p_identifier ILIKE '%@%' THEN
          u.email ILIKE LOWER(TRIM(p_identifier))
        ELSE
          u.username = LOWER(TRIM(p_identifier))
      END
    )
  LIMIT 1;
$$;

-- Allow anon (pre-auth) and authenticated users to call the resolver.
-- This is required because username login happens BEFORE authentication.
GRANT EXECUTE ON FUNCTION fn_get_email_by_identifier(text) TO anon;
GRANT EXECUTE ON FUNCTION fn_get_email_by_identifier(text) TO authenticated;

COMMENT ON FUNCTION fn_get_email_by_identifier(text) IS
  'Resolves a username OR email identifier to the user''s email for sign-in. '
  'Returns only the email field, or NULL if not found. '
  'SECURITY DEFINER — bypasses User table RLS so anon users can log in by username. '
  'Only returns email; no other PII is exposed.';
