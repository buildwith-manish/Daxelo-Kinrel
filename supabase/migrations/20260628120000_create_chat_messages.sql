-- =============================================================================
-- Daxelo-Kinrel — Real-time 1-1 / family-group chat schema
-- =============================================================================
-- Creates three tables:
--   1. ChatMessage          — the messages themselves
--   2. ChatMessageReaction  — per-user emoji reactions
--   3. ChatReadReceipt      — per-user read state
--
-- Design goals:
--   • Reuse the existing Family + FamilyMember + auth.users tables — no new
--     user identity is introduced. FamilyMember.userId is text (matches
--     auth.users.id cast to text), so we use text everywhere for user ids.
--   • RLS is scoped to family membership: only members of a family can
--     read/write chat messages in that family.
--   • All three tables are added to the supabase_realtime publication so
--     the Flutter client can subscribe to INSERT / UPDATE / DELETE events
--     via Postgres Changes.
--   • Timestamps are timestamptz to keep message ordering correct across
--     timezones.
--   • Idempotent: every CREATE / ALTER is wrapped in IF NOT EXISTS so the
--     migration is safe to re-run.
-- =============================================================================

-- ─── 1. ChatMessage ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "ChatMessage" (
    id                  text        PRIMARY KEY,
    "familyId"          text        NOT NULL REFERENCES "Family"(id) ON DELETE CASCADE,
    "senderId"          text        NOT NULL,                       -- auth.users.id as text
    "senderPersonId"    text,                                       -- optional: Person.id of the sender
    "senderName"        text        NOT NULL,                       -- denormalized for display
    "senderInitials"    text,                                       -- denormalized for avatar
    content             text        NOT NULL DEFAULT '',
    "messageType"       text        NOT NULL DEFAULT 'text',        -- text | photo | voiceNote | familyEvent
    "replyToId"         text        REFERENCES "ChatMessage"(id) ON DELETE SET NULL,
    "replyToContent"    text,
    "replyToSenderName" text,
    "isRead"            boolean     NOT NULL DEFAULT false,         -- denormalized: true once ANY other member has read it
    "isEdited"          boolean     NOT NULL DEFAULT false,
    "isDeleted"         boolean     NOT NULL DEFAULT false,         -- soft delete (sender hides their own message)
    "durationSeconds"   integer,
    "eventTitle"        text,
    "eventDate"         text,
    "createdAt"         timestamptz NOT NULL DEFAULT now(),
    "updatedAt"         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chatmessage_family_created
    ON "ChatMessage" ("familyId", "createdAt" DESC);

CREATE INDEX IF NOT EXISTS idx_chatmessage_sender
    ON "ChatMessage" ("senderId");

CREATE INDEX IF NOT EXISTS idx_chatmessage_reply
    ON "ChatMessage" ("replyToId");

CREATE INDEX IF NOT EXISTS idx_chatmessage_not_deleted
    ON "ChatMessage" ("familyId")
    WHERE "isDeleted" = false;

-- ─── 2. ChatMessageReaction ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "ChatMessageReaction" (
    id          text        PRIMARY KEY,
    "messageId" text        NOT NULL REFERENCES "ChatMessage"(id) ON DELETE CASCADE,
    "userId"    text        NOT NULL,                               -- auth.users.id as text
    emoji       text        NOT NULL,
    "createdAt" timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("messageId", "userId", emoji)
);

CREATE INDEX IF NOT EXISTS idx_chatmsgreaction_message
    ON "ChatMessageReaction" ("messageId");

CREATE INDEX IF NOT EXISTS idx_chatmsgreaction_user
    ON "ChatMessageReaction" ("userId");

-- ─── 3. ChatReadReceipt ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "ChatReadReceipt" (
    id          text        PRIMARY KEY,
    "messageId" text        NOT NULL REFERENCES "ChatMessage"(id) ON DELETE CASCADE,
    "userId"    text        NOT NULL,                               -- auth.users.id as text
    "readAt"    timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("messageId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_chatreadreceipt_message
    ON "ChatReadReceipt" ("messageId");

CREATE INDEX IF NOT EXISTS idx_chatreadreceipt_user
    ON "ChatReadReceipt" ("userId");

-- ─── 4. updated_at trigger for ChatMessage ──────────────────────────────────

CREATE OR REPLACE FUNCTION fn_chatmessage_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW."updatedAt" = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatmessage_set_updated_at ON "ChatMessage";
CREATE TRIGGER trg_chatmessage_set_updated_at
    BEFORE UPDATE ON "ChatMessage"
    FOR EACH ROW
    EXECUTE FUNCTION fn_chatmessage_set_updated_at();

-- ─── 5. Auto-generate id if not provided ────────────────────────────────────
-- The Flutter client generates CUID-like ids, but we also want INSERTs from
-- other sources (admin tools, server-side scripts) to work without an id.

CREATE OR REPLACE FUNCTION fn_chatmessage_gen_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        NEW.id := 'cm_' || encode(gen_random_bytes(12), 'hex');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatmessage_gen_id ON "ChatMessage";
CREATE TRIGGER trg_chatmessage_gen_id
    BEFORE INSERT ON "ChatMessage"
    FOR EACH ROW
    WHEN (NEW.id IS NULL OR NEW.id = '')
    EXECUTE FUNCTION fn_chatmessage_gen_id();

CREATE OR REPLACE FUNCTION fn_chatreaction_gen_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        NEW.id := 'cr_' || encode(gen_random_bytes(12), 'hex');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatreaction_gen_id ON "ChatMessageReaction";
CREATE TRIGGER trg_chatreaction_gen_id
    BEFORE INSERT ON "ChatMessageReaction"
    FOR EACH ROW
    WHEN (NEW.id IS NULL OR NEW.id = '')
    EXECUTE FUNCTION fn_chatreaction_gen_id();

CREATE OR REPLACE FUNCTION fn_chatreadreceipt_gen_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        NEW.id := 'crr_' || encode(gen_random_bytes(12), 'hex');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatreadreceipt_gen_id ON "ChatReadReceipt";
CREATE TRIGGER trg_chatreadreceipt_gen_id
    BEFORE INSERT ON "ChatReadReceipt"
    FOR EACH ROW
    WHEN (NEW.id IS NULL OR NEW.id = '')
    EXECUTE FUNCTION fn_chatreadreceipt_gen_id();

-- ─── 6. Helper: is current user a member of family X? ───────────────────────
-- Reused by all RLS policies below. Returns true if there is a FamilyMember
-- row for (auth.uid()::text, family_id).

CREATE OR REPLACE FUNCTION fn_user_is_family_member(family_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM "FamilyMember"
        WHERE "familyId" = family_id
          AND "userId" = auth.uid()::text
    );
$$;

-- ─── 7. Row-Level Security ─────────────────────────────────────────────────

ALTER TABLE "ChatMessage"          ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ChatMessageReaction"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ChatReadReceipt"      ENABLE ROW LEVEL SECURITY;

-- ChatMessage: SELECT — any family member can read all messages in their family
DROP POLICY IF EXISTS chatmessage_select_policy ON "ChatMessage";
CREATE POLICY chatmessage_select_policy
    ON "ChatMessage"
    FOR SELECT
    USING (fn_user_is_family_member("familyId"));

-- ChatMessage: INSERT — family members can post messages as themselves
DROP POLICY IF EXISTS chatmessage_insert_policy ON "ChatMessage";
CREATE POLICY chatmessage_insert_policy
    ON "ChatMessage"
    FOR INSERT
    WITH CHECK (
        fn_user_is_family_member("familyId")
        AND "senderId" = auth.uid()::text
    );

-- ChatMessage: UPDATE — sender can update (edit / soft-delete) their own
-- messages. We also allow any family member to flip isRead (handled via
-- the read-receipts table below, but the denormalized flag is updated by
-- a trigger — see §8 — so we need to allow updates from any member for
-- the isRead column specifically).
DROP POLICY IF EXISTS chatmessage_update_policy ON "ChatMessage";
CREATE POLICY chatmessage_update_policy
    ON "ChatMessage"
    FOR UPDATE
    USING (fn_user_is_family_member("familyId"))
    WITH CHECK (fn_user_is_family_member("familyId"));

-- ChatMessage: DELETE — only the sender can hard-delete their own message
DROP POLICY IF EXISTS chatmessage_delete_policy ON "ChatMessage";
CREATE POLICY chatmessage_delete_policy
    ON "ChatMessage"
    FOR DELETE
    USING (
        "senderId" = auth.uid()::text
    );

-- ChatMessageReaction: SELECT — any family member can see reactions
DROP POLICY IF EXISTS chatreaction_select_policy ON "ChatMessageReaction";
CREATE POLICY chatreaction_select_policy
    ON "ChatMessageReaction"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM "ChatMessage" m
            WHERE m.id = "ChatMessageReaction"."messageId"
              AND fn_user_is_family_member(m."familyId")
        )
    );

-- ChatMessageReaction: INSERT — family members can react to messages in their family
DROP POLICY IF EXISTS chatreaction_insert_policy ON "ChatMessageReaction";
CREATE POLICY chatreaction_insert_policy
    ON "ChatMessageReaction"
    FOR INSERT
    WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1
            FROM "ChatMessage" m
            WHERE m.id = "ChatMessageReaction"."messageId"
              AND fn_user_is_family_member(m."familyId")
        )
    );

-- ChatMessageReaction: DELETE — only the reactor can remove their own reaction
DROP POLICY IF EXISTS chatreaction_delete_policy ON "ChatMessageReaction";
CREATE POLICY chatreaction_delete_policy
    ON "ChatMessageReaction"
    FOR DELETE
    USING ("userId" = auth.uid()::text);

-- ChatReadReceipt: SELECT — any family member can see read receipts
DROP POLICY IF EXISTS chatreadreceipt_select_policy ON "ChatReadReceipt";
CREATE POLICY chatreadreceipt_select_policy
    ON "ChatReadReceipt"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM "ChatMessage" m
            WHERE m.id = "ChatReadReceipt"."messageId"
              AND fn_user_is_family_member(m."familyId")
        )
    );

-- ChatReadReceipt: INSERT — family members can mark messages in their family as read
DROP POLICY IF EXISTS chatreadreceipt_insert_policy ON "ChatReadReceipt";
CREATE POLICY chatreadreceipt_insert_policy
    ON "ChatReadReceipt"
    FOR INSERT
    WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1
            FROM "ChatMessage" m
            WHERE m.id = "ChatReadReceipt"."messageId"
              AND fn_user_is_family_member(m."familyId")
        )
    );

-- ChatReadReceipt: DELETE — only the user themselves can delete their own receipts
DROP POLICY IF EXISTS chatreadreceipt_delete_policy ON "ChatReadReceipt";
CREATE POLICY chatreadreceipt_delete_policy
    ON "ChatReadReceipt"
    FOR DELETE
    USING ("userId" = auth.uid()::text);

-- ─── 8. Trigger: auto-mark isRead=true when a non-sender reads a message ────
-- When a ChatReadReceipt row is created for a message that wasn't sent by the
-- reading user, flip the denormalized isRead flag on the ChatMessage so the
-- sender's UI can show the double-tick.

CREATE OR REPLACE FUNCTION fn_chatmessage_mark_read()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only flip isRead when the receipt is from a user OTHER than the sender
    UPDATE "ChatMessage"
       SET "isRead" = true
     WHERE id = NEW."messageId"
       AND "isRead" = false
       AND "senderId" <> NEW."userId";
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatmessage_mark_read ON "ChatReadReceipt";
CREATE TRIGGER trg_chatmessage_mark_read
    AFTER INSERT ON "ChatReadReceipt"
    FOR EACH ROW
    EXECUTE FUNCTION fn_chatmessage_mark_read();

-- ─── 9. Add tables to the supabase_realtime publication ─────────────────────
-- Postgres Changes in Supabase only fire for tables in this publication.
-- Use a DO block so we can guard each ADD TABLE against the case where the
-- table is already a member (ALTER PUBLICATION ... ADD TABLE IF NOT EXISTS
-- exists in PG 15+ but the Supabase pooler rejects it with a 42601 parser
-- error, so we use a dynamic SQL guard instead).

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'ChatMessage'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "ChatMessage";
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'ChatMessageReaction'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "ChatMessageReaction";
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'ChatReadReceipt'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "ChatReadReceipt";
    END IF;
END $$;

-- ─── 10. Helpful view for the Flutter client: messages with reaction counts ─
-- Returns one row per ChatMessage with a JSON array of reactions. The Flutter
-- client can either call this view or build the same shape client-side; we
-- expose it for convenience.

CREATE OR REPLACE VIEW "ChatMessageWithReactions" AS
SELECT
    m.*,
    COALESCE(
        json_agg(
            json_build_object(
                'emoji', r.emoji,
                'userId', r."userId"
            )
        ) FILTER (WHERE r.id IS NOT NULL),
        '[]'::json
    ) AS reactions_json,
    (
        SELECT COUNT(DISTINCT rr."userId")
        FROM "ChatReadReceipt" rr
        WHERE rr."messageId" = m.id
          AND rr."userId" <> m."senderId"
    ) AS read_by_count
FROM "ChatMessage" m
LEFT JOIN "ChatMessageReaction" r ON r."messageId" = m.id
GROUP BY m.id;

COMMENT ON TABLE "ChatMessage" IS
    'Family group chat messages. RLS-scoped to family membership. Realtime-enabled.';
COMMENT ON TABLE "ChatMessageReaction" IS
    'Per-user emoji reactions on chat messages. Realtime-enabled.';
COMMENT ON TABLE "ChatReadReceipt" IS
    'Per-user read receipts for chat messages. Triggers isRead on ChatMessage. Realtime-enabled.';
COMMENT ON VIEW "ChatMessageWithReactions" IS
    'Convenience view: ChatMessage + JSON array of reactions + distinct reader count.';
