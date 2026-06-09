-- lib/features/memory_vault/data/supabase_migration.sql
--
-- DAXELO KINREL — Memory Vault Migration
--
-- Creates the family_memories table and Storage bucket
-- for the Memory Vault feature. Includes RLS policies
-- for family-scoped access control.
--
-- Table: family_memories
--   - Each row represents a photo memory uploaded by a family member
--   - RLS ensures only family members can read/insert
--   - Only the uploader can delete their own memories
--
-- Storage: family-memories (public read bucket)
--   - Path format: {family_id}/{memory_id}.jpg
--   - Family members can upload/delete within their family folder

-- ═══════════════════════════════════════════════════════════════════════
-- TABLE: family_memories
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS family_memories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  uploader_id UUID NOT NULL,
  uploader_name TEXT NOT NULL DEFAULT '',
  caption TEXT,
  photo_url TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT 'photo',
  taken_at DATE,
  tagged_person_ids UUID[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE family_memories ENABLE ROW LEVEL SECURITY;

-- Read policy: only family members can read memories
CREATE POLICY "Family members can read memories" ON family_memories
  FOR SELECT USING (
    auth.uid() IN (
      SELECT user_id FROM family_memberships WHERE family_id = family_memories.family_id
    )
  );

-- Insert policy: only family members can insert
CREATE POLICY "Family members can insert memories" ON family_memories
  FOR INSERT WITH CHECK (
    auth.uid() IN (
      SELECT user_id FROM family_memberships WHERE family_id = family_memories.family_id
    )
  );

-- Update policy: only uploader can update their memories
CREATE POLICY "Only uploader can update memories" ON family_memories
  FOR UPDATE USING (auth.uid() = uploader_id);

-- Delete policy: only uploader can delete
CREATE POLICY "Only uploader can delete memories" ON family_memories
  FOR DELETE USING (auth.uid() = uploader_id);

-- ═══════════════════════════════════════════════════════════════════════
-- STORAGE: family-memories bucket
-- ═══════════════════════════════════════════════════════════════════════

-- Create the storage bucket (public read for CDN performance)
INSERT INTO storage.buckets (id, name, public) VALUES ('family-memories', 'family-memories', true)
  ON CONFLICT (id) DO NOTHING;

-- Storage policy: family members can upload to their family folder
CREATE POLICY "Family members can upload memories" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'family-memories' AND
    auth.uid() IN (
      SELECT user_id FROM family_memberships WHERE family_id::text = (storage.foldername(name))[1]
    )
  );

-- Storage policy: anyone can read (public bucket — URLs are unguessable UUIDs)
CREATE POLICY "Public read memories" ON storage.objects
  FOR SELECT USING (bucket_id = 'family-memories');

-- Storage policy: only uploader can delete their memory files
-- Path format: {family_id}/{uploader_id}_{memory_id}.jpg
-- We match the second path segment which contains the uploader_id prefix
CREATE POLICY "Uploader can delete memory files" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'family-memories' AND auth.uid()::text = (storage.foldername(name))[2]
  );

-- ═══════════════════════════════════════════════════════════════════════
-- INDEXES for performance
-- ═══════════════════════════════════════════════════════════════════════

-- Index on family_id for fast family-scoped queries
CREATE INDEX IF NOT EXISTS idx_memories_family_id ON family_memories(family_id);

-- Index on created_at for ordered timeline queries
CREATE INDEX IF NOT EXISTS idx_memories_created_at ON family_memories(created_at DESC);

-- Index on uploader_id for owner-scoped queries
CREATE INDEX IF NOT EXISTS idx_memories_uploader_id ON family_memories(uploader_id);

-- Index on taken_at for "On This Day" date queries
CREATE INDEX IF NOT EXISTS idx_memories_taken_at ON family_memories(taken_at);

-- ═══════════════════════════════════════════════════════════════════════
-- TRIGGER: auto-update updated_at timestamp
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_memory_updated_at
  BEFORE UPDATE ON family_memories
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
