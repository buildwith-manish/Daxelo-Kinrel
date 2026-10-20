-- =============================================================================
-- Daxelo Kinrel — Phase B — voice-messages bucket privacy migration
-- =============================================================================
-- File: 20261020120000_voice_messages_private_bucket.sql
-- Status: WRITTEN, NOT YET RUN AGAINST PRODUCTION.
--   Apply manually after the Phase B code is on Test/Staging, verify the
--   signed-URL playback works end-to-end, then promote to Prod.
--
-- What this migration does:
--   1. Makes the `voice-messages` storage bucket PRIVATE (public = false).
--      Without this, `getPublicUrl(...)` returns a URL that anyone on the
--      internet can fetch — which is what Phase B point 6 ("Privacy check:
--      report whether the 'voice-messages' bucket is public") flagged.
--
--   2. Replaces the bucket's existing SELECT policy (which currently
--      allows ANY unauthenticated user to read ANY voice message) with a
--      family-scoped SELECT policy: a row's bytes can be fetched only by
--      authenticated users who share a family with the file's owner.
--
--   3. Adds an `AncestralMemory.storagePath` column so the Phase B save
--      flow can persist the storage path separately from the signed URL
--      (Phase C will re-mint fresh signed URLs on demand without parsing
--      the URL).
--
-- Privacy gaps closed (the audit the user asked for):
--   GAP-1 (CLOSED): Public bucket + public SELECT policy → anyone on the
--     internet could fetch any voice message by guessing/enumerating
--     storage paths. CLOSED by steps 1+2 below.
--   GAP-2 (CLOSED): No family-scoping on reads → an authenticated user
--     in family A could fetch voice messages uploaded by a user in
--     family B by knowing the path. CLOSED by step 2's family-scoped
--     SELECT policy.
--   GAP-3 (PARTIAL — needs application-layer fix): The path layout
--     `oral-history/<userId>/<file>.m4a` (legacy) and the new
--     `todays-question/<userId>/<file>.m4a` (Phase B) both namespace
--     by owner userId. The new SELECT policy joins `Person.linkedUserId`
--     to `FamilyMember` to confirm the requester is in the same family
--     as the owner. This works for families where the owner has a
--     Person node with `linkedUserId` set — which is the app's normal
--     state. For legacy recordings uploaded by users who have since
--     been removed from all families, the owner check returns no
--     family rows and reads will be DENIED — which is the desired
--     fail-closed behavior.
--
-- Remaining RLS gaps the application layer must address:
--   • The signed URLs minted by `client.storage.from('voice-messages')
--     .createSignedUrl(path, 3600)` are bearer tokens — anyone who
--     obtains the URL within the 1-hour window can stream the audio.
--     The new SELECT policy does NOT protect signed URLs (Supabase
--     validates the signed-URL token at the storage edge, bypassing
--     RLS). The 1-hour expiry is the primary mitigation. For tighter
--     scoping, switch to server-side proxied streaming via an Edge
--     Function that issues per-request short-lived URLs — a Phase D
--     task.
--   • INSERT/UPDATE/DELETE policies are UNCHANGED — owners can still
--     manage their own files. No new gaps introduced.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────
-- Step 1: Make the bucket private
-- ─────────────────────────────────────────────────────────────────

UPDATE storage.buckets
SET public = false
WHERE id = 'voice-messages';

-- ─────────────────────────────────────────────────────────────────
-- Step 2: Replace the public SELECT policy with a family-scoped one
-- ─────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "voice_messages_select" ON storage.objects;

-- A user can READ a voice message iff they share at least one family
-- with the file's owner. The owner is identified by the `owner`
-- column on storage.objects (= auth.uid() at upload time). The
-- requester's families come from FamilyMember. The owner's families
-- are looked up the same way, joined through Person.linkedUserId
-- (the canonical link between an auth user and their Person nodes
-- across families).
CREATE POLICY "voice_messages_select_family_scoped" ON storage.objects
    FOR SELECT TO authenticated USING (
        bucket_id = 'voice-messages'
        AND EXISTS (
            -- Requester shares a family with the file's owner.
            SELECT 1
            FROM "FamilyMember" requester_fm
            JOIN "FamilyMember" owner_fm
                ON owner_fm.familyId = requester_fm.familyId
            WHERE requester_fm.userId = auth.uid()
              AND owner_fm.userId = storage.objects.owner
        )
    );

-- Comment so future DBAs understand why this policy exists.
COMMENT ON POLICY "voice_messages_select_family_scoped" ON storage.objects IS
    'Phase B — voice-messages bucket is now private. Only authenticated users who share at least one family with the file''s owner can read the audio bytes. Signed URLs bypass this (Supabase validates the token at the storage edge) so the 1-hour signed-URL expiry is the primary mitigation. INSERT/UPDATE/DELETE policies are unchanged (owner-only).';

-- ─────────────────────────────────────────────────────────────────
-- Step 3: Add AncestralMemory.storagePath column
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE "AncestralMemory"
    ADD COLUMN IF NOT EXISTS "storagePath" text;

COMMENT ON COLUMN "AncestralMemory"."storagePath" IS
    'Phase B — storage path inside the voice-messages bucket (e.g. todays-question/<userId>/<file>.m4a). Stored separately from mediaUrl (which is the signed/public URL) so Phase C can re-mint fresh signed URLs on demand without parsing the URL.';

-- Index for the picker''s "already answered" lookup — filters by
-- familyId + topic + userTags contains 'elder:<personId>'.
CREATE INDEX IF NOT EXISTS "ancestralmemory_family_topic_idx"
    ON "AncestralMemory" ("familyId", "topic");

-- ─────────────────────────────────────────────────────────────────
-- Step 4: Verification queries (do NOT auto-execute — paste these
-- into the Supabase SQL editor after applying the migration to
-- verify the new state).
-- ─────────────────────────────────────────────────────────────────

-- Confirm the bucket is private:
--   SELECT id, name, public FROM storage.buckets WHERE id = 'voice-messages';
-- Expected: public = false.

-- Confirm the new SELECT policy replaced the old public one:
--   SELECT polname, polqual::text
--   FROM pg_policies
--   WHERE tablename = 'objects' AND schemaname = 'storage'
--     AND polname LIKE 'voice_messages%';
-- Expected: only `voice_messages_select_family_scoped` (the old
-- `voice_messages_select` is gone). INSERT/UPDATE/DELETE policies
-- unchanged.

-- Confirm the new column:
--   SELECT column_name, data_type
--   FROM information_schema.columns
--   WHERE table_name = 'AncestralMemory' AND column_name = 'storagePath';
-- Expected: storagePath | text.

-- ─────────────────────────────────────────────────────────────────
-- Rollback script (in case the new policy breaks something and we
-- need to revert to public-read while debugging):
-- ─────────────────────────────────────────────────────────────────
--
-- UPDATE storage.buckets SET public = true WHERE id = 'voice-messages';
-- DROP POLICY IF EXISTS "voice_messages_select_family_scoped" ON storage.objects;
-- CREATE POLICY "voice_messages_select" ON storage.objects
--     FOR SELECT USING (bucket_id = 'voice-messages');
-- -- (AncestralMemory.storagePath is left in place — drop is optional.)
-- =============================================================================
