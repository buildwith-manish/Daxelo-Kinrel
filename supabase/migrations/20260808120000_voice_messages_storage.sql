-- =============================================================================
-- Daxelo Kinrel — Voice Messages Storage (Phase 13)
-- =============================================================================
-- Creates a dedicated `voice-messages` storage bucket for uploaded voice
-- notes. Reuses the existing ChatMessage table — voice notes are stored as
-- ChatMessage rows with messageType='voiceNote', messageSubType='voice',
-- mediaUrl=<public URL of the audio file>, and voiceMessageDuration=<seconds>.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────
-- 1. Voice-messages storage bucket (public read, auth write)
-- ─────────────────────────────────────────────────────────────────
-- Allowed MIME types cover all platforms Flutter `record` package emits:
--   - Android: audio/m4a, audio/3gpp, audio/amr
--   - iOS/macOS: audio/m4a, audio/x-m4a, audio/mp4
--   - Web: audio/webm;codecs=opus, audio/ogg, audio/mp4
--   - Windows/Linux: audio/wav, audio/mp3
-- File size limit: 25 MB (a 5-minute AAC voice note is ~1–2 MB).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'voice-messages',
    'voice-messages',
    true,
    26214400,  -- 25 MB
    ARRAY[
        'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/m4a', 'audio/x-m4a',
        'audio/aac', 'audio/ogg', 'audio/wav', 'audio/x-wav', 'audio/webm',
        'audio/3gpp', 'audio/amr', 'audio/flac', 'audio/x-flac'
    ]
)
ON CONFLICT (id) DO UPDATE
SET file_size_limit = 26214400,
    allowed_mime_types = ARRAY[
        'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/m4a', 'audio/x-m4a',
        'audio/aac', 'audio/ogg', 'audio/wav', 'audio/x-wav', 'audio/webm',
        'audio/3gpp', 'audio/amr', 'audio/flac', 'audio/x-flac'
    ];

-- ─────────────────────────────────────────────────────────────────
-- 2. RLS policies for the voice-messages bucket
-- ─────────────────────────────────────────────────────────────────

-- Anyone (even unauthenticated) can READ voice messages — this lets
-- recipients stream them via the public URL embedded in ChatMessage.
DROP POLICY IF EXISTS "voice_messages_select" ON storage.objects;
CREATE POLICY "voice_messages_select" ON storage.objects
    FOR SELECT USING (bucket_id = 'voice-messages');

-- Any authenticated user can UPLOAD a voice message they own.
DROP POLICY IF EXISTS "voice_messages_insert" ON storage.objects;
CREATE POLICY "voice_messages_insert" ON storage.objects
    FOR INSERT TO authenticated WITH CHECK (
        bucket_id = 'voice-messages'
        AND owner = auth.uid()
    );

-- Owner can UPDATE / DELETE their own voice messages.
DROP POLICY IF EXISTS "voice_messages_update" ON storage.objects;
CREATE POLICY "voice_messages_update" ON storage.objects
    FOR UPDATE TO authenticated USING (
        bucket_id = 'voice-messages'
        AND owner = auth.uid()
    );

DROP POLICY IF EXISTS "voice_messages_delete" ON storage.objects;
CREATE POLICY "voice_messages_delete" ON storage.objects
    FOR DELETE TO authenticated USING (
        bucket_id = 'voice-messages'
        AND owner = auth.uid()
    );

-- ─────────────────────────────────────────────────────────────────
-- 3. Verification
-- ─────────────────────────────────────────────────────────────────

SELECT 'voice-messages bucket' AS obj,
       EXISTS(SELECT 1 FROM storage.buckets WHERE id = 'voice-messages') AS exists;
