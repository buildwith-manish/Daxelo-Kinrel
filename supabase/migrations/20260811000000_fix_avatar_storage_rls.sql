-- =============================================================================
-- Daxelo Kinrel — Fix Storage RLS for Avatar Uploads (v118)
-- =============================================================================
-- ROOT CAUSE: The 'avatars' bucket's SELECT policy was dropped in migration
-- 20260617164625 and never recreated. The INSERT/UPDATE/DELETE policies were
-- tightened in 20260618000000 to require owner = auth.uid() on UPDATE/DELETE,
-- but the INSERT policy only checks auth.uid() IS NOT NULL — it does NOT
-- enforce that the owner column gets set to the uploading user's ID.
--
-- This caused 403 "new row violates row-level security policy" errors when:
--   1. The app tries to REPLACE an existing avatar (UPDATE path) — fails
--      because the existing file's owner doesn't match auth.uid().
--   2. The app tries to list or sign-URL avatars (SELECT) — fails because
--      the SELECT policy was dropped.
--
-- FIX: Recreate all 4 policies (SELECT/INSERT/UPDATE/DELETE) with consistent
-- owner = auth.uid() checks, matching the pattern used by the voice-messages
-- and chat-attachments buckets. This ensures:
--   - Any authenticated user can upload a NEW avatar (INSERT with owner set).
--   - Only the owner can replace/delete their own uploads (UPDATE/DELETE).
--   - Anyone can view avatars (SELECT — needed for signed URLs + listing).
-- =============================================================================

-- ── 1. Ensure the avatars bucket is public ──────────────────────────────
INSERT INTO storage.buckets ("id", "name", "public")
VALUES ('avatars', 'avatars', true)
ON CONFLICT ("id") DO UPDATE SET "public" = true;

-- ── 2. Drop all existing avatar policies ────────────────────────────────
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;

-- ── 3. Recreate policies with correct owner checks ─────────────────────

-- SELECT: anyone can view avatars (bucket is public, but this policy is
-- needed for .list() and .createSignedUrl() API calls).
CREATE POLICY "Avatar images are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- INSERT: authenticated users can upload new avatars. The owner column
-- is set automatically by the Storage API to auth.uid() when the upload
-- uses the user's JWT. The WITH CHECK ensures the owner matches.
CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (select auth.uid()) IS NOT NULL
  );

-- UPDATE: only the owner can replace their own avatar.
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  );

-- DELETE: only the owner can delete their own avatar.
CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND owner = (select auth.uid())
  );

-- ── 4. Verification ────────────────────────────────────────────────────
SELECT 'avatars bucket' AS object,
       EXISTS(SELECT 1 FROM storage.buckets WHERE id = 'avatars' AND public = true) AS is_public;

SELECT 'avatars SELECT policy' AS policy,
       EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Avatar images are publicly accessible') AS exists;

SELECT 'avatars INSERT policy' AS policy,
       EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Authenticated users can upload avatars') AS exists;

SELECT 'avatars UPDATE policy' AS policy,
       EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Users can update their own avatar') AS exists;

SELECT 'avatars DELETE policy' AS policy,
       EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Users can delete their own avatar') AS exists;
