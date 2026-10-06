-- supabase/migrations/20261005120000_memories_image_vault_integration.sql
--
-- DAXELO KINREL — Memories, Timeline & Memory Vault Integration
--
-- Creates the `family_memories` table (it does not yet exist in production)
-- AND extends it with all the columns needed to support:
--   1. One optional cover image per memory (image_url + image_storage_key)
--   2. Title / description / location / member ids / memory_type / date
--   3. source_post_id — optional FK back to "FamilyPost" when a memory was
--      created from a post
--   4. is_pinned_to_vault — flag for the Memory Vault (premium archive)
--
-- Schema notes (verified against the actual production database):
--   • The "Family" table uses TEXT ids and camelCase column names.
--   • The "FamilyMember" table is the membership join table — it has
--     (familyId, userId, role, joinedAt) columns. There is no
--     `family_memberships` table; the original migration's RLS policies
--     referenced a non-existent table.
--   • The "FamilyPost" table also uses TEXT ids.
--   • We use TEXT ids for family_memories to match the rest of the schema.
--
-- Storage bucket: `memory-images` (NEW — separate from `family-memories`)
--   Path format: memory-images/{familyId}/{memoryId}/image.jpg
--
-- Backward compatibility:
--   The Flutter `MemoryModel` already reads `photo_url`, `caption`,
--   `taken_at`, `tagged_person_ids` from this table. By creating the
--   table with ALL columns (legacy + v2) in a single migration, we
--   preserve the existing Flutter code path while adding the new image /
--   title / description / location / type / source_post_id / pin columns.

-- ═══════════════════════════════════════════════════════════════════════
-- 1. CREATE family_memories TABLE (with all v2 columns)
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS family_memories (
  -- Identity
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,

  -- Family scoping (FK to "Family" — TEXT id)
  family_id TEXT NOT NULL REFERENCES "Family"(id) ON DELETE CASCADE,

  -- Uploader (denormalized for fast reads)
  uploader_id TEXT NOT NULL,
  uploader_name TEXT NOT NULL DEFAULT '',

  -- Legacy fields (preserved for backward compat with the original
  -- MemoryVault feature that used photo_url + caption)
  caption TEXT,
  photo_url TEXT NOT NULL DEFAULT '',
  media_type TEXT NOT NULL DEFAULT 'photo',

  -- When the memory was originally taken / occurred
  taken_at DATE,

  -- Tagged family members (TEXT ids — matching the rest of the schema)
  tagged_person_ids TEXT[] DEFAULT '{}',

  -- Server timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- ── v2 fields (Feature 1, 6, 8) ──────────────────────────────────
  -- All nullable for backward compatibility.

  -- Cover image URL (Supabase Storage public URL for the cropped,
  -- compressed image uploaded to the memory-images bucket).
  image_url TEXT,

  -- Storage key for the cover image (so we can DELETE the storage
  -- object when the memory is deleted). Format: {familyId}/{memoryId}/image.jpg
  image_storage_key TEXT,

  -- Short headline / title for the memory.
  title TEXT,

  -- Longer story / description.
  description TEXT,

  -- Free-form location string (e.g. "Jaipur").
  location TEXT,

  -- Memory type label (Festival / Birth / Marriage / Achievement / ...).
  -- Stored as TEXT to keep the schema flexible.
  memory_type TEXT,

  -- Optional FK back to "FamilyPost" — set when this memory was created
  -- from a post via the "Save As Memory" flow. TEXT to match FamilyPost.id.
  source_post_id TEXT,

  -- Vault pin flag. Default false. Pinned memories appear in Memory Vault.
  is_pinned_to_vault BOOLEAN NOT NULL DEFAULT false
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2. INDEXES for performance (cursor pagination + vault queries)
-- ═══════════════════════════════════════════════════════════════════════

-- Composite index for cursor-paginated timeline fetches:
--   WHERE family_id = $1 AND created_at < $2 ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_memories_family_created_at
  ON family_memories(family_id, created_at DESC);

-- Index for "pinned to vault" queries (Memory Vault tab).
CREATE INDEX IF NOT EXISTS idx_memories_family_pinned
  ON family_memories(family_id, is_pinned_to_vault, created_at DESC);

-- Index for source_post_id lookups (the "Saved To Memories" badge on a post).
-- Partial index — only rows with a non-null source_post_id are indexed.
CREATE INDEX IF NOT EXISTS idx_memories_source_post_id
  ON family_memories(source_post_id)
  WHERE source_post_id IS NOT NULL;

-- Index on taken_at for "On This Day" date queries.
CREATE INDEX IF NOT EXISTS idx_memories_taken_at
  ON family_memories(taken_at);

-- Index on uploader_id for owner-scoped queries.
CREATE INDEX IF NOT EXISTS idx_memories_uploader_id
  ON family_memories(uploader_id);

-- ═══════════════════════════════════════════════════════════════════════
-- 3. ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE family_memories ENABLE ROW LEVEL SECURITY;

-- Read policy: only family members can read memories.
-- Uses the real "FamilyMember" table (NOT family_memberships).
DROP POLICY IF EXISTS "Family members can read memories" ON family_memories;
CREATE POLICY "Family members can read memories" ON family_memories
  FOR SELECT USING (
    auth.uid()::text IN (
      SELECT "userId" FROM "FamilyMember" WHERE "familyId" = family_memories.family_id
    )
  );

-- Insert policy: only family members can insert
DROP POLICY IF EXISTS "Family members can insert memories" ON family_memories;
CREATE POLICY "Family members can insert memories" ON family_memories
  FOR INSERT WITH CHECK (
    auth.uid()::text IN (
      SELECT "userId" FROM "FamilyMember" WHERE "familyId" = family_memories.family_id
    )
  );

-- Update policy: only the uploader can update their memories
-- (covers the new is_pinned_to_vault + image_url + ... columns)
DROP POLICY IF EXISTS "Only uploader can update memories" ON family_memories;
CREATE POLICY "Only uploader can update memories" ON family_memories
  FOR UPDATE USING (auth.uid()::text = uploader_id);

-- Delete policy: only uploader can delete
DROP POLICY IF EXISTS "Only uploader can delete memories" ON family_memories;
CREATE POLICY "Only uploader can delete memories" ON family_memories
  FOR DELETE USING (auth.uid()::text = uploader_id);

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
DROP POLICY IF EXISTS "Family members can upload memory images" ON storage.objects;
CREATE POLICY "Family members can upload memory images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'memory-images' AND
    auth.uid()::text IN (
      SELECT "userId" FROM "FamilyMember"
      WHERE "familyId"::text = (storage.foldername(name))[1]
    )
  );

-- Public read (bucket is public; URLs contain unguessable UUIDs).
DROP POLICY IF EXISTS "Public read memory images" ON storage.objects;
CREATE POLICY "Public read memory images" ON storage.objects
  FOR SELECT USING (bucket_id = 'memory-images');

-- Delete policy: family members can delete memory image files in their
-- family's folder. (The table-level RLS already ensures only the memory's
-- uploader can trigger a DELETE on the row that owns this storage key.)
DROP POLICY IF EXISTS "Family members can delete memory image files" ON storage.objects;
CREATE POLICY "Family members can delete memory image files" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'memory-images' AND
    auth.uid()::text IN (
      SELECT "userId" FROM "FamilyMember"
      WHERE "familyId"::text = (storage.foldername(name))[1]
    )
  );

-- ═══════════════════════════════════════════════════════════════════════
-- 5. TRIGGER: auto-update updated_at timestamp
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_memory_updated_at ON family_memories;
CREATE TRIGGER set_memory_updated_at
  BEFORE UPDATE ON family_memories
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
