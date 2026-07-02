-- v91: Story replies + Sparq replies tables
-- Enables the Stories Reply and Sparq Reply Submission features
-- that were previously stubbed with "coming soon" snackbars.

-- ─────────────────────────────────────────────────────────────────
-- StoryReply — text replies to Instagram-style stories
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "StoryReply" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "storyId"       TEXT NOT NULL REFERENCES "Story"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,  -- auth.users.id (replier)
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "userAvatarUrl" TEXT,
    content         TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for fast lookup by story
CREATE INDEX IF NOT EXISTS idx_story_reply_story_id
    ON "StoryReply"("storyId");
CREATE INDEX IF NOT EXISTS idx_story_reply_created_at
    ON "StoryReply"("createdAt" DESC);

-- Enable RLS
ALTER TABLE "StoryReply" ENABLE ROW LEVEL SECURITY;

-- SELECT: story creator OR replier OR family member of the story's family
CREATE POLICY "story_reply_select" ON "StoryReply"
    FOR SELECT USING (
        "userId" = auth.uid()
        OR EXISTS (
            SELECT 1 FROM "Story" s
            WHERE s.id = "StoryReply"."storyId"
              AND s."userId" = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM "Story" s
            JOIN "FamilyMember" fm ON fm."familyId" = s."familyId"
            WHERE s.id = "StoryReply"."storyId"
              AND fm."userId" = auth.uid()
        )
    );

-- INSERT: any authenticated user (the story is visible to family members per Story RLS)
CREATE POLICY "story_reply_insert" ON "StoryReply"
    FOR INSERT WITH CHECK ("userId" = auth.uid());

-- DELETE: only the replier
CREATE POLICY "story_reply_delete" ON "StoryReply"
    FOR DELETE USING ("userId" = auth.uid());

-- Add to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE "StoryReply";

-- ─────────────────────────────────────────────────────────────────
-- SparqReply — text replies to Sparqs (social story format)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SparqReply" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "sparqId"       TEXT NOT NULL REFERENCES "Sparq"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,  -- auth.users.id (replier)
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "userAvatarUrl" TEXT,
    content         TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_sparq_reply_sparq_id
    ON "SparqReply"("sparqId");
CREATE INDEX IF NOT EXISTS idx_sparq_reply_created_at
    ON "SparqReply"("createdAt" DESC);

-- Enable RLS
ALTER TABLE "SparqReply" ENABLE ROW LEVEL SECURITY;

-- SELECT: sparq creator OR replier (conservative — doesn't expose to all followers)
CREATE POLICY "sparq_reply_select" ON "SparqReply"
    FOR SELECT USING (
        "userId" = auth.uid()
        OR EXISTS (
            SELECT 1 FROM "Sparq" sp
            WHERE sp.id = "SparqReply"."sparqId"
              AND sp."userId" = auth.uid()
        )
    );

-- INSERT: any authenticated user
CREATE POLICY "sparq_reply_insert" ON "SparqReply"
    FOR INSERT WITH CHECK ("userId" = auth.uid());

-- DELETE: only the replier
CREATE POLICY "sparq_reply_delete" ON "SparqReply"
    FOR DELETE USING ("userId" = auth.uid());

-- Add to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE "SparqReply";

-- ─────────────────────────────────────────────────────────────────
-- ChatMessage.mediaUrl — for chat attachments (photo/voice notes)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "ChatMessage"
    ADD COLUMN IF NOT EXISTS "mediaUrl" TEXT;

-- Storage bucket for chat attachments (photos, voice notes)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat-attachments',
    'chat-attachments',
    true,
    26214400,  -- 25 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif',
          'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav', 'audio/aac']
)
ON CONFLICT (id) DO NOTHING;

-- RLS for chat-attachments bucket
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
