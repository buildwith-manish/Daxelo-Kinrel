-- ============================================================
-- Migration: fix_storage_bucket_drop_redundant_tables
-- Version:  20260701090000
--
-- FIXES:
--   1. Create 'post-media' storage bucket (missing — post uploads fail)
--   2. Drop 3 redundant lowercase tables (graph_state_cache, blocks, permissions)
-- ============================================================

-- ── 1. Create post-media storage bucket ──────────────────────
-- The app's post_create_provider.dart uploads family post media
-- to this bucket, but it didn't exist — only 'avatars' existed.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'post-media',
  'post-media',
  true,
  10485760,  -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4']
)
ON CONFLICT (id) DO NOTHING;

-- Grant public read access (public bucket)
CREATE POLICY "post_media_public_read" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'post-media');

-- Grant authenticated users upload access
CREATE POLICY "post_media_auth_insert" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'post-media');

-- Grant authenticated users update/delete on their own files
CREATE POLICY "post_media_auth_update" ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (bucket_id = 'post-media' AND owner = auth.uid()::text);

CREATE POLICY "post_media_auth_delete" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'post-media' AND owner = auth.uid()::text);

-- ── 2. Drop redundant lowercase tables ───────────────────────
-- These are leftovers from older migrations. The app uses the
-- PascalCase versions (GraphLayoutState, BlockedUser, PersonPrivacySetting).
-- All three have 0 rows.

DROP TABLE IF EXISTS public.graph_state_cache CASCADE;
DROP TABLE IF EXISTS public.blocks CASCADE;
DROP TABLE IF EXISTS public.permissions CASCADE;

-- ── Verify ───────────────────────────────────────────────────
-- Storage buckets should now show: avatars, post-media
-- SELECT id, name, public FROM storage.buckets ORDER BY name;
