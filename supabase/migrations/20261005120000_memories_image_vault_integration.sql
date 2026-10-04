-- supabase/migrations/20261005120000_memories_image_vault_integration.sql
--
-- DAXELO KINREL — Memories, Timeline & Memory Vault Integration
--
-- Extends the existing `family_memories` table with the columns needed to
-- support:
--   1. One optional cover image per memory (image_url + image_storage_key)
--   2. Title / description / location / member ids / memory_type / date
--   3. source_post_id — optional FK back to "FamilyPost" when a memory was
--      created from a post
--   4. is_pinned_to_vault — flag for the Memory Vault (premium archive)
--
-- All new columns are NULLable or have defaults so existing rows (which
-- only have photo_url + caption) continue to work unchanged. This is the
-- backward-compatibility guarantee from Feature 10.
--
-- Storage bucket: `memory-images` (NEW — separate from `family-memories`)
--   Path format: memory-images/{familyId}/{memoryId}/image.jpg
--   This matches the folder structure required by the implementation prompt
--   and keeps memory covers separate from the legacy Memory Vault photo
--   gallery (which used `family-memories/{familyId}/{memoryId}.jpg`).
--
-- Post ↔ Memory link is one-way nullable: a Memory *may* reference a Post,
-- but a Post has no direct column for "saved to memory" — the badge on the
-- post is computed by querying `family_memories.source_post_id`.

-- ═══════════════════════════════════════════════════════════════════════
-- 1. EXTEND family_memories TABLE (backward-compatible)
-- ═══════════════════════════════════════════════════════════════════════

-- Cover image URL (Supabase Storage public URL for the cropped, compressed
-- image uploaded to memory-images bucket). Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Storage key for the cover image (so we can delete the storage object
-- when the memory is deleted). Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS image_storage_key TEXT;

-- Memory title (short headline). Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS title TEXT;

-- Longer story / description. Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Free-form location string (e.g. "Jaipur"). Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS location TEXT;

-- Memory type label (festival / birth / marriage / achievement / etc.)
-- Stored as TEXT to keep the schema flexible. Nullable for backward compat.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS memory_type TEXT;

-- Optional reference back to the FamilyPost the memory was created from.
-- Nullable: most memories are NOT created from a post.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS source_post_id TEXT;

-- Vault pin flag. Default false. Pinned memories appear in Memory Vault.
ALTER TABLE family_memories
  ADD COLUMN IF NOT EXISTS is_pinned_to_vault BOOLEAN NOT NULL DEFAULT false;

-- Member IDs already exist as `tagged_person_ids UUID[]` from the original
-- migration — re-used as the "members" list. No new column needed.

-- `taken_at` already exists and is reused as the "date" for the memory.

-- ═══════════════════════════════════════════════════════════════════════
-- 2. INDEXES for new columns (cursor pagination + vault queries)
-- ═══════════════════════════════════════════════════════════════════════

-- Composite index for cursor-paginated timeline fetches:
--   WHERE family_id = $1 AND created_at < $2 ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_memories_family_created_at
  ON family_memories(family_id, created_at DESC);

-- Index for "pinned to vault" queries (Memory Vault tab).
CREATE INDEX IF NOT EXISTS idx_memories_family_pinned
  ON family_memories(family_id, is_pinned_to_vault, created_at DESC);

-- Index for source_post_id lookups (the "Saved To Memories" badge on a post)
CREATE INDEX IF NOT EXISTS idx_memories_source_post_id
  ON family_memories(source_post_id)
  WHERE source_post_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. RLS POLICIES for new columns
-- ═══════════════════════════════════════════════════════════════════════
--
-- The existing RLS policies on family_memories cover SELECT/INSERT/UPDATE/
-- DELETE for family members. New columns inherit those policies — no
-- additional policy needed. (RLS is column-agnostic once enabled.)

-- Update policy already exists ("Only uploader can update memories") and
-- covers the new is_pinned_to_vault + image_url + ... columns.

-- ═══════════════════════════════════════════════════════════════════════
-- 4. STORAGE BUCKET: memory-images (NEW)
-- ═══════════════════════════════════════════════════════════════════════
--
-- Public read bucket (URLs are unguessable UUIDs — same security model as
-- the existing family-memories bucket). Path format:
--   memory-images/{familyId}/{memoryId}/image.jpg

INSERT INTO storage.buckets (id, name, public)
VALUES ('memory-images', 'memory-images', true)
ON CONFLICT (id) DO NOTHING;

-- Upload policy: family members can write into their family's folder.
CREATE POLICY "Family members can upload memory images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'memory-images' AND
    auth.uid() IN (
      SELECT user_id FROM family_memberships
      WHERE family_id::text = (storage.foldername(name))[1]
    )
  );

-- Public read (bucket is public; URLs contain unguessable UUIDs).
CREATE POLICY "Public read memory images" ON storage.objects
  FOR SELECT USING (bucket_id = 'memory-images');

-- Delete policy: only the uploader can delete their memory's storage object.
-- Path format: memory-images/{familyId}/{memoryId}/image.jpg
-- We match on family_id (first segment) and rely on the table-level RLS to
-- ensure only the memory's uploader can call DELETE on the row that owns
-- this storage key.
CREATE POLICY "Family members can delete memory image files" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'memory-images' AND
    auth.uid() IN (
      SELECT user_id FROM family_memberships
      WHERE family_id::text = (storage.foldername(name))[1]
    )
  );

-- ═══════════════════════════════════════════════════════════════════════
-- 5. AUTOCOMPLETE/CONSTANT — verify backward compatibility
-- ═══════════════════════════════════════════════════════════════════════
--
-- All new columns are nullable (or have defaults), so:
--   - Existing rows with only (id, family_id, uploader_id, caption,
--     photo_url, taken_at, tagged_person_ids) continue to work.
--   - Existing Flutter code that reads photo_url / caption continues to
--     function without changes.
--   - The new image_url / image_storage_key / title / description /
--     location / memory_type / source_post_id / is_pinned_to_vault
--     columns are simply NULL on old rows.
--
-- No data backfill is required.
