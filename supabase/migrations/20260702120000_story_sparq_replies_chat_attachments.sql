-- v91: Story replies + Sparq replies tables (FIXED version)
-- Uses auth.uid()::text casts to avoid text = uuid operator errors.

-- ─────────────────────────────────────────────────────────────────
-- StoryReply — text replies to Instagram-style stories
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "StoryReply" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "storyId"       TEXT NOT NULL REFERENCES "Story"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "userAvatarUrl" TEXT,
    content         TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_story_reply_story_id
    ON "StoryReply"("storyId");
CREATE INDEX IF NOT EXISTS idx_story_reply_created_at
    ON "StoryReply"("createdAt" DESC);

ALTER TABLE "StoryReply" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "story_reply_select" ON "StoryReply"
    FOR SELECT USING (
        "userId" = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM "Story" s
            WHERE s.id = "StoryReply"."storyId"
              AND s."userId" = auth.uid()::text
        )
        OR EXISTS (
            SELECT 1 FROM "Story" s
            JOIN "FamilyMember" fm ON fm."familyId" = s."familyId"
            WHERE s.id = "StoryReply"."storyId"
              AND fm."userId" = auth.uid()::text
        )
    );

CREATE POLICY "story_reply_insert" ON "StoryReply"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "story_reply_delete" ON "StoryReply"
    FOR DELETE USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "StoryReply";

-- ─────────────────────────────────────────────────────────────────
-- SparqReply — text replies to Sparqs
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SparqReply" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "sparqId"       TEXT NOT NULL REFERENCES "Sparq"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "userAvatarUrl" TEXT,
    content         TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sparq_reply_sparq_id
    ON "SparqReply"("sparqId");
CREATE INDEX IF NOT EXISTS idx_sparq_reply_created_at
    ON "SparqReply"("createdAt" DESC);

ALTER TABLE "SparqReply" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sparq_reply_select" ON "SparqReply"
    FOR SELECT USING (
        "userId" = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM "Sparq" sp
            WHERE sp.id = "SparqReply"."sparqId"
              AND sp."userId" = auth.uid()::text
        )
    );

CREATE POLICY "sparq_reply_insert" ON "SparqReply"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "sparq_reply_delete" ON "SparqReply"
    FOR DELETE USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "SparqReply";

-- ─────────────────────────────────────────────────────────────────
-- ChatMessage.mediaUrl — for chat attachments
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "ChatMessage"
    ADD COLUMN IF NOT EXISTS "mediaUrl" TEXT;

-- ─────────────────────────────────────────────────────────────────
-- Storage bucket for chat attachments
-- ─────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat-attachments',
    'chat-attachments',
    true,
    26214400,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif',
          'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav', 'audio/aac']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "chat_attachments_select" ON storage.objects
    FOR SELECT USING (bucket_id = 'chat-attachments');

CREATE POLICY "chat_attachments_insert" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'chat-attachments'
        AND owner = auth.uid()
    );

CREATE POLICY "chat_attachments_update" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'chat-attachments'
        AND owner = auth.uid()
    );

CREATE POLICY "chat_attachments_delete" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'chat-attachments'
        AND owner = auth.uid()
    );
