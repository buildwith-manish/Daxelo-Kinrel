-- supabase/migrations/20261005160000_ancestral_memory_member_write_rls.sql
--
-- DAXELO KINREL — Oral History: Enable client-side writes + add missing
-- columns for the "working real" database wiring.
--
-- Problem:
--   The AncestralMemory table was created with RLS policies that only
--   allow service_role to INSERT/UPDATE/DELETE. The Flutter client
--   uses the authenticated role, so all client-side writes silently
--   fail (caught + debugPrint'd, never surfaced to the user).
--   Additionally, the Oral History save dialog captures narratorName,
--   tags, era, and waveformData — none of which have columns on the
--   table, so they're thrown away on save.
--
-- Fix:
--   1. Add RLS policies allowing authenticated family members to
--      INSERT/UPDATE/DELETE their OWN memories (recorderId = auth.uid()).
--   2. Add the missing columns: narratorName, userTags, era, waveformData.
--   3. Add an updated_at auto-trigger (the column has DEFAULT NOW() but
--      no BEFORE UPDATE trigger to actually update it on UPDATE).
--
-- Scope: AncestralMemory table only. Storage bucket 'voice-messages'
-- already allows authenticated users to upload — no changes needed there.

-- ═══════════════════════════════════════════════════════════════════════
-- 1. Add missing columns (IF NOT EXISTS for idempotency)
-- ═══════════════════════════════════════════════════════════════════════

-- The name of the person telling the story (the elder/narrator).
-- Denormalized for fast reads — avoids a JOIN to Person/User on every
-- list render. The recorderId is the authenticated user who recorded;
-- narratorName is the elder whose voice is in the recording (may differ
-- from the recorder, e.g., a grandchild recording a grandparent).
ALTER TABLE "AncestralMemory"
  ADD COLUMN IF NOT EXISTS "narratorName" TEXT;

-- User-assigned tags (e.g., ["wedding", "partition", "recipe"]).
-- Stored as JSONB array. Separate from aiTags (which is the AI pipeline's
-- auto-generated tags) so user input isn't overwritten by AI processing.
ALTER TABLE "AncestralMemory"
  ADD COLUMN IF NOT EXISTS "userTags" JSONB DEFAULT '[]'::jsonb;

-- Era label (e.g., "1960s", "Pre-Independence", "Childhood").
-- Freeform text — the save dialog has a text field for this.
ALTER TABLE "AncestralMemory"
  ADD COLUMN IF NOT EXISTS "era" TEXT;

-- Waveform amplitude data for the audio player visualization.
-- Stored as JSONB array of doubles (0.0-1.0). Sampled at recording
-- time from the `record` package's amplitude stream.
ALTER TABLE "AncestralMemory"
  ADD COLUMN IF NOT EXISTS "waveformData" JSONB DEFAULT '[]'::jsonb;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. RLS policies — allow authenticated family members to write their
--    OWN memories (recorderId = auth.uid()).
-- ═══════════════════════════════════════════════════════════════════════
--
-- The existing SELECT policy already allows family members to read.
-- The existing INSERT/UPDATE/DELETE policies only allow service_role.
-- We ADD (not replace) policies for authenticated users scoped to
-- their own recordings — the recorder can manage their own memories
-- but not someone else's.

-- INSERT: authenticated users can insert rows where they are the recorder.
DROP POLICY IF EXISTS "AncestralMemory_recorder_insert" ON "AncestralMemory";
CREATE POLICY "AncestralMemory_recorder_insert" ON "AncestralMemory"
  FOR INSERT TO authenticated
  WITH CHECK ("recorderId" = auth.uid()::text);

-- UPDATE: authenticated users can update their own recordings.
DROP POLICY IF EXISTS "AncestralMemory_recorder_update" ON "AncestralMemory";
CREATE POLICY "AncestralMemory_recorder_update" ON "AncestralMemory"
  FOR UPDATE TO authenticated
  USING ("recorderId" = auth.uid()::text)
  WITH CHECK ("recorderId" = auth.uid()::text);

-- DELETE: authenticated users can delete their own recordings.
DROP POLICY IF EXISTS "AncestralMemory_recorder_delete" ON "AncestralMemory";
CREATE POLICY "AncestralMemory_recorder_delete" ON "AncestralMemory"
  FOR DELETE TO authenticated
  USING ("recorderId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════
-- 3. updated_at auto-trigger (the table has DEFAULT NOW() but no
--    BEFORE UPDATE trigger to actually set it on UPDATE).
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_ancestral_memory_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW."updatedAt" = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_ancestral_memory_updated_at ON "AncestralMemory";
CREATE TRIGGER set_ancestral_memory_updated_at
  BEFORE UPDATE ON "AncestralMemory"
  FOR EACH ROW
  EXECUTE FUNCTION update_ancestral_memory_updated_at();

-- ═══════════════════════════════════════════════════════════════════════
-- 4. GRANT table-level privileges to the authenticated role.
-- ═══════════════════════════════════════════════════════════════════════
--
-- RLS policies define WHICH ROWS a role can touch, but the role also
-- needs table-level GRANT to touch the table at all. The existing
-- setup only GRANTed SELECT to authenticated (for the read-only RLS
-- policy). Now that we've added INSERT/UPDATE/DELETE RLS policies for
-- authenticated, we also need to GRANT those operations.
--
-- Without this GRANT, client-side writes fail with:
--   42501 / permission denied for table AncestralMemory
-- even though the RLS policy would allow the specific row.

GRANT SELECT, INSERT, UPDATE, DELETE ON "AncestralMemory" TO authenticated;
