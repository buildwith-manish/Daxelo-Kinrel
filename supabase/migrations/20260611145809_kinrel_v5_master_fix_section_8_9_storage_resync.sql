-- ============================================================
-- Migration: kinrel_v5_master_fix_section_8_9_storage_resync
-- Version:  20260611145809
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- SECTION 8: Storage Bucket Policies
INSERT INTO storage.buckets ("id", "name", "public")
VALUES ('avatars', 'avatars', true)
ON CONFLICT ("id") DO UPDATE SET "public" = true;

DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload avatars"   ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar"        ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar"        ON storage.objects;

CREATE POLICY "Avatar images are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid() IS NOT NULL
  );

CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.uid() IS NOT NULL
  );

CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.uid() IS NOT NULL
  );

-- SECTION 9: Re-sync memberCount for existing data
UPDATE "Family" f
SET "memberCount" = (
  SELECT COUNT(*) FROM "Person" p
  WHERE p."familyId" = f."id"
    AND p."deletedAt" IS NULL
);

-- SECTION 10: Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
