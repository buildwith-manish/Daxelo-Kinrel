-- =============================================================================
-- Daxelo-Kinrel — DM Engagement Parity (reactions + typing indicator)
-- =============================================================================
-- The group chat has supported per-user emoji reactions since
-- 20260628120000_create_chat_messages.sql:
--   "ChatMessageReaction" (messageId, userId, emoji, UNIQUE triple)
-- and typing status since 20260808110000_chat_enhancement_schema.sql:
--   "ChatTypingStatus" (familyId, userId, isTyping, updatedAt)
--
-- The 1:1 DM chat has NEITHER — which is why the shared ChatMessageList
-- passes showReactions=false for DMs and the DM header shows a static
-- "Private chat" subtitle instead of live status.
--
-- This migration mirrors the same two tables (same column semantics,
-- same UNIQUE constraint, same RLS shape, same realtime publication) for
-- DirectMessage-backed threads so the shared reaction chips, reaction
-- picker overlay, and typing indicator render IDENTICALLY in both chat
-- types:
--
--   1. "DirectMessageReaction" — per-user emoji reactions on DM rows.
--      RLS mirrors DirectMessage's own policies (only the sender or the
--      receiver of the reacted-to message can read; only participants
--      react; only the reactor removes their own reaction).
--
--   2. "DirectTypingStatus" — who is currently typing in a 1:1 thread.
--      Keyed by a symmetric dmKey ("<idA>__<idB>", ids sorted) so both
--      parties compute the SAME key from their own perspective and a
--      user typing in two different DMs creates two rows. RLS: both
--      parties of the dmKey can read; a user can only write their own
--      row.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS + DROP POLICY IF EXISTS.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. DirectMessageReaction table (mirrors ChatMessageReaction)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "DirectMessageReaction" (
    id          text        PRIMARY KEY,
    "messageId" text        NOT NULL REFERENCES "DirectMessage"(id) ON DELETE CASCADE,
    "userId"    text        NOT NULL,                               -- auth.users.id as text
    emoji       text        NOT NULL,
    "createdAt" timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("messageId", "userId", emoji)
);

CREATE INDEX IF NOT EXISTS idx_dmreaction_message
    ON "DirectMessageReaction" ("messageId");

CREATE INDEX IF NOT EXISTS idx_dmreaction_user
    ON "DirectMessageReaction" ("userId");

ALTER TABLE "DirectMessageReaction" ENABLE ROW LEVEL SECURITY;

-- SELECT: only the two participants of the reacted-to DM can see its
-- reactions (mirrors "DM select policy" on DirectMessage).
DROP POLICY IF EXISTS "DM reaction select policy" ON "DirectMessageReaction";
CREATE POLICY "DM reaction select policy"
    ON "DirectMessageReaction"
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM "DirectMessage" m
            WHERE m.id = "DirectMessageReaction"."messageId"
              AND (auth.uid()::text = m."senderId" OR auth.uid()::text = m."receiverId")
        )
    );

-- INSERT: only a participant can react, and only in their own name
-- (mirrors "DM insert policy" + the group's self-reaction guard).
DROP POLICY IF EXISTS "DM reaction insert policy" ON "DirectMessageReaction";
CREATE POLICY "DM reaction insert policy"
    ON "DirectMessageReaction"
    FOR INSERT TO authenticated
    WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM "DirectMessage" m
            WHERE m.id = "DirectMessageReaction"."messageId"
              AND (auth.uid()::text = m."senderId" OR auth.uid()::text = m."receiverId")
        )
    );

-- DELETE: only the reactor can remove their own reaction (same rule as
-- the group's chatreaction_delete_policy).
DROP POLICY IF EXISTS "DM reaction delete policy" ON "DirectMessageReaction";
CREATE POLICY "DM reaction delete policy"
    ON "DirectMessageReaction"
    FOR DELETE TO authenticated
    USING ("userId" = auth.uid()::text);

-- Realtime: reaction changes fan out to the open DM screens so both
-- participants see chips appear/disappear without polling.
ALTER TABLE "DirectMessageReaction" REPLICA IDENTITY FULL;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'DirectMessageReaction'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "DirectMessageReaction";
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Realtime setup (DirectMessageReaction): %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. DirectTypingStatus table (mirrors ChatTypingStatus)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "DirectTypingStatus" (
    "id"        text        PRIMARY KEY,
    "dmKey"     text        NOT NULL,                               -- "<idA>__<idB>" (sorted)
    "userId"    text        NOT NULL,                               -- auth.users.id as text
    "isTyping"  boolean     NOT NULL DEFAULT false,
    "updatedAt" timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("dmKey", "userId")
);

CREATE INDEX IF NOT EXISTS idx_dmtyping_key
    ON "DirectTypingStatus" ("dmKey");

ALTER TABLE "DirectTypingStatus" ENABLE ROW LEVEL SECURITY;

-- SELECT: only the two participants of the dmKey can see who's typing
-- (the dmKey is exactly "<idA>__<idB>", so membership = id in split).
DROP POLICY IF EXISTS "DM typing select policy" ON "DirectTypingStatus";
CREATE POLICY "DM typing select policy"
    ON "DirectTypingStatus"
    FOR SELECT TO authenticated
    USING (
        auth.uid()::text = ANY (string_to_array("dmKey", '__'))
    );

-- INSERT/UPDATE: a user can only upsert their OWN typing row, and only
-- inside a dmKey they participate in.
DROP POLICY IF EXISTS "DM typing insert policy" ON "DirectTypingStatus";
CREATE POLICY "DM typing insert policy"
    ON "DirectTypingStatus"
    FOR INSERT TO authenticated
    WITH CHECK (
        "userId" = auth.uid()::text
        AND auth.uid()::text = ANY (string_to_array("dmKey", '__'))
    );

DROP POLICY IF EXISTS "DM typing update policy" ON "DirectTypingStatus";
CREATE POLICY "DM typing update policy"
    ON "DirectTypingStatus"
    FOR UPDATE TO authenticated
    USING ("userId" = auth.uid()::text)
    WITH CHECK (
        "userId" = auth.uid()::text
        AND auth.uid()::text = ANY (string_to_array("dmKey", '__'))
    );

-- Realtime: typing flips propagate to the open DM screen instantly.
ALTER TABLE "DirectTypingStatus" REPLICA IDENTITY FULL;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'DirectTypingStatus'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "DirectTypingStatus";
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Realtime setup (DirectTypingStatus): %', SQLERRM;
END $$;
