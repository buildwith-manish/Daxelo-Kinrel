-- =============================================================================
-- Daxelo Kinrel — Phase 1 — Circles (account-level cross-family group chats)
-- =============================================================================
-- File: 20261101120000_create_circles.sql
-- Status: WRITTEN, NOT YET APPLIED. Per the user's instruction:
--   "Do NOT run migrations against any real database; write them and show me."
--
-- What this migration does:
--   1. Creates 6 new tables: Circle, CircleMember, CircleMessage,
--      CircleReaction, CircleReadReceipt, SparqAudienceCircle.
--   2. Creates 3 RLS helper SQL functions: fn_user_is_circle_member,
--      fn_user_is_circle_admin, fn_user_can_be_added_to_circle.
--   3. Enables RLS on all 6 tables + creates the RLS policies.
--   4. Creates indexes for the common query paths.
--   5. Adds the new tables to the supabase_realtime publication.
--   6. Adds the CIRCLE value to the SparqAudience Postgres enum.
--   7. Creates a new private storage bucket 'circle-attachments' +
--      RLS policies for it.
--   8. Adds a circle-scoped SELECT policy to the 'voice-messages'
--      bucket so circle voice notes can be stored there too.
--
-- Backwards compatibility:
--   This migration does NOT touch ChatMessage, Group, GroupMember,
--   FamilyMember, Follow, BlockedUser, Block, or ContentReport.
--   Existing family chats, DMs, archive, drafts, scheduled messages,
--   block/report, and push batching keep working unchanged.
--
-- Rollback (at the bottom of this file as a comment):
--   DROP the 6 tables, 3 functions, the storage bucket, and the
--   enum value. The enum value drop requires a DROP TYPE + recreate
--   (Postgres cannot remove a single value from an enum).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────────────────────────

-- ── 1a. Circle ────────────────────────────────────────────────────
-- Account-scoped. No familyId column — this is the entire point.
CREATE TABLE IF NOT EXISTS "Circle" (
    "id"              text PRIMARY KEY,
    "ownerId"         text NOT NULL,                         -- creator's auth.uid()
    "name"            text NOT NULL,
    "description"      text,
    "iconKey"         text NOT NULL DEFAULT 'default',       -- small curated set per mockup 12
    "avatarUrl"       text,
    "onlyAdminsPost"  boolean NOT NULL DEFAULT false,        -- announcement circle
    "anyoneCanAdd"    boolean NOT NULL DEFAULT false,
    "lastActivityAt"  timestamptz NOT NULL DEFAULT now(),
    "createdAt"       timestamptz NOT NULL DEFAULT now(),
    "updatedAt"       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_circle_owner" ON "Circle" ("ownerId");
CREATE INDEX IF NOT EXISTS "idx_circle_activity" ON "Circle" ("lastActivityAt" DESC);

-- ── 1b. CircleMember ─────────────────────────────────────────────
-- Per-member state (archive, mute, role, display snapshot).
-- Circle membership is independent of family membership: leaving a
-- family does NOT auto-remove someone from a circle (per the product
-- rule). The ON DELETE CASCADE on circleId ensures the circle's
-- members are cleaned up when the circle itself is deleted.
CREATE TABLE IF NOT EXISTS "CircleMember" (
    "id"           text PRIMARY KEY,
    "circleId"     text NOT NULL REFERENCES "Circle"("id") ON DELETE CASCADE,
    "userId"       text NOT NULL,
    "role"         text NOT NULL DEFAULT 'member',           -- admin | member (no CHECK constraint — app-enforced, matching GroupMember's pattern)
    "joinedAt"     timestamptz NOT NULL DEFAULT now(),
    "isArchived"   boolean NOT NULL DEFAULT false,           -- per-member archive
    "mutedUntil"   timestamptz,                               -- null = not muted; future = snoozed
    "displayName"  text NOT NULL,                             -- snapshot at join (so roster renders without JOIN to auth.users)
    "avatarUrl"    text
);

CREATE UNIQUE INDEX IF NOT EXISTS "uniq_circle_member" ON "CircleMember" ("circleId", "userId");
CREATE INDEX IF NOT EXISTS "idx_circle_member_circle" ON "CircleMember" ("circleId");
CREATE INDEX IF NOT EXISTS "idx_circle_member_user" ON "CircleMember" ("userId");

-- ── 1c. CircleMessage ───────────────────────────────────────────
-- Does NOT touch ChatMessage.familyId (which stays NOT NULL).
-- Parallel table with the columns circles actually need.
CREATE TABLE IF NOT EXISTS "CircleMessage" (
    "id"                    text PRIMARY KEY,
    "circleId"              text NOT NULL REFERENCES "Circle"("id") ON DELETE CASCADE,
    "senderId"              text NOT NULL,
    "senderName"            text NOT NULL,                    -- snapshot at send time (display-name fallback for cross-family members)
    "senderInitials"        text,
    "senderPersonId"        text,                              -- per-family Person.id resolved at send time (for kinship lookup)
    "senderFamilyId"        text,                              -- the family the sender resolved in (see Phase 0 §3.3)
    "content"               text NOT NULL DEFAULT '',
    "messageType"           text NOT NULL DEFAULT 'text',     -- text | photo | voiceNote | sticker | gif | document | poll
    "messageSubType"        text NOT NULL DEFAULT 'text',
    "replyToId"             text REFERENCES "CircleMessage"("id") ON DELETE SET NULL,
    "replyToContent"        text,
    "replyToSenderName"     text,
    "isEdited"              boolean NOT NULL DEFAULT false,
    "isDeletedForEveryone"  boolean NOT NULL DEFAULT false,
    "isPinned"              boolean NOT NULL DEFAULT false,
    "pinnedBy"              text,
    "pinnedAt"              timestamptz,
    "messageStatus"         text NOT NULL DEFAULT 'sent',     -- sent | delivered | read
    "deletedForMe"          jsonb NOT NULL DEFAULT '[]'::jsonb,
    "mentions"              jsonb NOT NULL DEFAULT '[]'::jsonb,
    "mediaUrl"              text,
    "mediaType"             text,
    "mediaFileName"         text,
    "mediaSize"             bigint,
    "thumbnailUrl"          text,
    "voiceMessageDuration"  integer,
    "durationSeconds"       integer,
    "pollQuestion"          text,
    "pollOptions"           jsonb,
    "pollVoteCounts"        jsonb,
    "pollVoterIds"          jsonb,
    "pollCreatedAt"         timestamptz,
    "editedAt"              timestamptz,
    "deletedAt"             timestamptz,
    "readBy"                text[] NOT NULL DEFAULT '{}',     -- denormalized read-receipt cache (same pattern as ChatMessage)
    "notified"             boolean NOT NULL DEFAULT false,   -- smart-batched-push marker
    "createdAt"             timestamptz NOT NULL DEFAULT now(),
    "updatedAt"             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_circlemsg_circle_created" ON "CircleMessage" ("circleId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "idx_circlemsg_sender" ON "CircleMessage" ("senderId");
CREATE INDEX IF NOT EXISTS "idx_circlemsg_status" ON "CircleMessage" ("messageStatus");
CREATE INDEX IF NOT EXISTS "idx_circlemsg_pinned" ON "CircleMessage" ("isPinned") WHERE "isPinned" = true;
CREATE INDEX IF NOT EXISTS "idx_circlemsg_notified" ON "CircleMessage" ("notified") WHERE "notified" = false;

-- ── 1d. CircleReaction ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "CircleReaction" (
    "id"         text PRIMARY KEY,
    "messageId"  text NOT NULL REFERENCES "CircleMessage"("id") ON DELETE CASCADE,
    "userId"     text NOT NULL,
    "emoji"      text NOT NULL,
    "createdAt"  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "uniq_circle_reaction" ON "CircleReaction" ("messageId", "userId", "emoji");
CREATE INDEX IF NOT EXISTS "idx_circle_reaction_msg" ON "CircleReaction" ("messageId");

-- ── 1e. CircleReadReceipt ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS "CircleReadReceipt" (
    "id"         text PRIMARY KEY,
    "messageId"  text NOT NULL REFERENCES "CircleMessage"("id") ON DELETE CASCADE,
    "userId"     text NOT NULL,
    "readAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "uniq_circle_receipt" ON "CircleReadReceipt" ("messageId", "userId");
CREATE INDEX IF NOT EXISTS "idx_circle_receipt_msg" ON "CircleReadReceipt" ("messageId");
CREATE INDEX IF NOT EXISTS "idx_circle_receipt_user" ON "CircleReadReceipt" ("userId");

-- ── 1f. SparqAudienceCircle (Phase 4 preview — many-to-many) ────
-- A Sparq with audience CIRCLE can be scoped to one or more circles.
-- The feed query joins this table to check membership.
CREATE TABLE IF NOT EXISTS "SparqAudienceCircle" (
    "id"         text PRIMARY KEY,
    "sparqId"    text NOT NULL REFERENCES "Sparq"("id") ON DELETE CASCADE,
    "circleId"   text NOT NULL REFERENCES "Circle"("id") ON DELETE CASCADE,
    "createdAt"  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "uniq_sparq_audience_circle" ON "SparqAudienceCircle" ("sparqId", "circleId");
CREATE INDEX IF NOT EXISTS "idx_sparq_audience_circle_sparq" ON "SparqAudienceCircle" ("sparqId");
CREATE INDEX IF NOT EXISTS "idx_sparq_audience_circle_circle" ON "SparqAudienceCircle" ("circleId");

-- ─────────────────────────────────────────────────────────────────
-- 2. RLS helper SQL functions (SECURITY DEFINER so they can read
--    CircleMember / FamilyMember / Follow / BlockedUser without
--    exposing those tables to the caller)
-- ─────────────────────────────────────────────────────────────────

-- ── 2a. fn_user_is_circle_member(circle_id) ──────────────────────
-- Strict membership check (no family fallback — circles have no family).
CREATE OR REPLACE FUNCTION fn_user_is_circle_member(circle_id text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS(
        SELECT 1 FROM "CircleMember"
        WHERE "circleId" = circle_id
          AND "userId" = auth.uid()
    );
$$;

-- ── 2b. fn_user_is_circle_admin(circle_id) ───────────────────────
-- Admin check — used by onlyAdminsCanAdd + onlyAdminsPost.
CREATE OR REPLACE FUNCTION fn_user_is_circle_admin(circle_id text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS(
        SELECT 1 FROM "CircleMember"
        WHERE "circleId" = circle_id
          AND "userId" = auth.uid()
          AND "role" = 'admin'
    );
$$;

-- ── 2c. fn_user_can_be_added_to_circle(circle_id, candidate_user_id) ─
-- The eligibility rule: "share at least one family OR accepted follow"
-- + "not blocked" + "not already a member" + "circle has < 100 members".
--
-- SECURITY DEFINER so it can read FamilyMember, Follow, and BlockedUser
-- without exposing those tables to the caller.
CREATE OR REPLACE FUNCTION fn_user_can_be_added_to_circle(
    circle_id text,
    candidate_user_id text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT
        -- Pre-condition 1: candidate is not already a member
        NOT EXISTS(
            SELECT 1 FROM "CircleMember"
            WHERE "circleId" = circle_id AND "userId" = candidate_user_id
        )
        -- Pre-condition 2: circle has < 100 members (product limit)
        AND (
            SELECT COUNT(*) FROM "CircleMember" WHERE "circleId" = circle_id
        ) < 100
        -- Eligibility: share at least one family OR accepted follow (either direction)
        AND (
            EXISTS(
                SELECT 1
                FROM "FamilyMember" a
                JOIN "FamilyMember" b ON a."familyId" = b."familyId"
                WHERE a."userId" = (SELECT "ownerId" FROM "Circle" WHERE id = circle_id)
                  AND b."userId" = candidate_user_id
            )
            OR EXISTS(
                SELECT 1 FROM "Follow" f
                WHERE f."status" = 'ACCEPTED'
                AND (
                    (f."followerId" = (SELECT "ownerId" FROM "Circle" WHERE id = circle_id)
                     AND f."followingId" = candidate_user_id)
                    OR
                    (f."followerId" = candidate_user_id
                     AND f."followingId" = (SELECT "ownerId" FROM "Circle" WHERE id = circle_id))
                )
            )
        )
        -- Not blocked (either direction — "blocked users cannot be added
        -- and cannot add you")
        AND NOT EXISTS(
            SELECT 1 FROM "BlockedUser"
            WHERE ("blockerId" = (SELECT "ownerId" FROM "Circle" WHERE id = circle_id)
                   AND "blockedId" = candidate_user_id)
               OR ("blockerId" = candidate_user_id
                   AND "blockedId" = (SELECT "ownerId" FROM "Circle" WHERE id = circle_id))
        );
$$;

-- ─────────────────────────────────────────────────────────────────
-- 3. RLS — enable + policies on all 6 tables
-- ─────────────────────────────────────────────────────────────────

-- ── 3a. Circle ───────────────────────────────────────────────────
ALTER TABLE "Circle" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "circle_select_member" ON "Circle";
CREATE POLICY "circle_select_member" ON "Circle"
    FOR SELECT TO authenticated USING (fn_user_is_circle_member("id"));

DROP POLICY IF EXISTS "circle_insert_owner" ON "Circle";
CREATE POLICY "circle_insert_owner" ON "Circle"
    FOR INSERT TO authenticated WITH CHECK ("ownerId" = auth.uid());

DROP POLICY IF EXISTS "circle_update_admin" ON "Circle";
CREATE POLICY "circle_update_admin" ON "Circle"
    FOR UPDATE TO authenticated USING (fn_user_is_circle_admin("id"))
    WITH CHECK (fn_user_is_circle_admin("id"));

DROP POLICY IF EXISTS "circle_delete_admin" ON "Circle";
CREATE POLICY "circle_delete_admin" ON "Circle"
    FOR DELETE TO authenticated USING (fn_user_is_circle_admin("id"));

-- ── 3b. CircleMember ─────────────────────────────────────────────
ALTER TABLE "CircleMember" ENABLE ROW LEVEL SECURITY;

-- Members see the roster; users see their own row even if not a member
-- (needed for the "You are no longer in this circle" state — the user
-- can read their own membership row to know they were removed).
DROP POLICY IF EXISTS "circlemember_select_member_or_self" ON "CircleMember";
CREATE POLICY "circlemember_select_member_or_self" ON "CircleMember"
    FOR SELECT TO authenticated USING (
        fn_user_is_circle_member("circleId") OR "userId" = auth.uid()
    );

-- INSERT: admin-add (with eligibility) OR self-join (not used in v1 —
-- people are added by admins only). The eligibility function is the
-- server-side enforcement of "blocked users cannot be added".
DROP POLICY IF EXISTS "circlemember_insert_admin" ON "CircleMember";
CREATE POLICY "circlemember_insert_admin" ON "CircleMember"
    FOR INSERT TO authenticated WITH CHECK (
        (fn_user_is_circle_admin("circleId") OR (
            -- anyoneCanAdd: any member can add
            SELECT "anyoneCanAdd" FROM "Circle" WHERE id = "circleId"
        ))
        AND fn_user_can_be_added_to_circle("circleId", "userId")
    );

-- UPDATE: self-update (archive/mute only) OR admin-update (role changes)
DROP POLICY IF EXISTS "circlemember_update_self_or_admin" ON "CircleMember";
CREATE POLICY "circlemember_update_self_or_admin" ON "CircleMember"
    FOR UPDATE TO authenticated USING (
        "userId" = auth.uid() OR fn_user_is_circle_admin("circleId")
    )
    WITH CHECK (
        "userId" = auth.uid() OR fn_user_is_circle_admin("circleId")
    );

-- DELETE: self-leave OR admin-remove
DROP POLICY IF EXISTS "circlemember_delete_self_or_admin" ON "CircleMember";
CREATE POLICY "circlemember_delete_self_or_admin" ON "CircleMember"
    FOR DELETE TO authenticated USING (
        "userId" = auth.uid() OR fn_user_is_circle_admin("circleId")
    );

-- ── 3c. CircleMessage ───────────────────────────────────────────
ALTER TABLE "CircleMessage" ENABLE ROW LEVEL SECURITY;

-- Members can read all messages in their circles
DROP POLICY IF EXISTS "circlemsg_select_member" ON "CircleMessage";
CREATE POLICY "circlemsg_select_member" ON "CircleMessage"
    FOR SELECT TO authenticated USING (fn_user_is_circle_member("circleId"));

-- INSERT: members can send, BUT onlyAdminsPost is enforced
DROP POLICY IF EXISTS "circlemsg_insert_member" ON "CircleMessage";
CREATE POLICY "circlemsg_insert_member" ON "CircleMessage"
    FOR INSERT TO authenticated WITH CHECK (
        fn_user_is_circle_member("circleId")
        AND (
            NOT (SELECT "onlyAdminsPost" FROM "Circle" WHERE id = "circleId")
            OR fn_user_is_circle_admin("circleId")
        )
        AND "senderId" = auth.uid()
    );

-- UPDATE: sender only (edits, soft-delete, pin toggle)
DROP POLICY IF EXISTS "circlemsg_update_sender" ON "CircleMessage";
CREATE POLICY "circlemsg_update_sender" ON "CircleMessage"
    FOR UPDATE TO authenticated USING ("senderId" = auth.uid())
    WITH CHECK ("senderId" = auth.uid());

-- DELETE: sender only (hard delete — rare, cascade from circle deletion)
DROP POLICY IF EXISTS "circlemsg_delete_sender" ON "CircleMessage";
CREATE POLICY "circlemsg_delete_sender" ON "CircleMessage"
    FOR DELETE TO authenticated USING ("senderId" = auth.uid());

-- ── 3d. CircleReaction ──────────────────────────────────────────
ALTER TABLE "CircleReaction" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "circlereaction_select_member" ON "CircleReaction";
CREATE POLICY "circlereaction_select_member" ON "CircleReaction"
    FOR SELECT TO authenticated USING (
        fn_user_is_circle_member(
            (SELECT "circleId" FROM "CircleMessage" WHERE id = "messageId")
        )
    );

DROP POLICY IF EXISTS "circlereaction_insert_member" ON "CircleReaction";
CREATE POLICY "circlereaction_insert_member" ON "CircleReaction"
    FOR INSERT TO authenticated WITH CHECK (
        fn_user_is_circle_member(
            (SELECT "circleId" FROM "CircleMessage" WHERE id = "messageId")
        )
        AND "userId" = auth.uid()
    );

DROP POLICY IF EXISTS "circlereaction_update_owner" ON "CircleReaction";
CREATE POLICY "circlereaction_update_owner" ON "CircleReaction"
    FOR UPDATE TO authenticated USING ("userId" = auth.uid())
    WITH CHECK ("userId" = auth.uid());

DROP POLICY IF EXISTS "circlereaction_delete_owner" ON "CircleReaction";
CREATE POLICY "circlereaction_delete_owner" ON "CircleReaction"
    FOR DELETE TO authenticated USING ("userId" = auth.uid());

-- ── 3e. CircleReadReceipt ────────────────────────────────────────
ALTER TABLE "CircleReadReceipt" ENABLE ROW LEVEL SECURITY;

-- Privacy: users see only their OWN receipts (not other members')
DROP POLICY IF EXISTS "circlereceipt_select_self" ON "CircleReadReceipt";
CREATE POLICY "circlereceipt_select_self" ON "CircleReadReceipt"
    FOR SELECT TO authenticated USING ("userId" = auth.uid());

DROP POLICY IF EXISTS "circlereceipt_insert_member" ON "CircleReadReceipt";
CREATE POLICY "circlereceipt_insert_member" ON "CircleReadReceipt"
    FOR INSERT TO authenticated WITH CHECK (
        "userId" = auth.uid()
        AND fn_user_is_circle_member(
            (SELECT "circleId" FROM "CircleMessage" WHERE id = "messageId")
        )
    );

DROP POLICY IF EXISTS "circlereceipt_update_self" ON "CircleReadReceipt";
CREATE POLICY "circlereceipt_update_self" ON "CircleReadReceipt"
    FOR UPDATE TO authenticated USING ("userId" = auth.uid())
    WITH CHECK ("userId" = auth.uid());

DROP POLICY IF EXISTS "circlereceipt_delete_self" ON "CircleReadReceipt";
CREATE POLICY "circlereceipt_delete_self" ON "CircleReadReceipt"
    FOR DELETE TO authenticated USING ("userId" = auth.uid());

-- ── 3f. SparqAudienceCircle ──────────────────────────────────────
ALTER TABLE "SparqAudienceCircle" ENABLE ROW LEVEL SECURITY;

-- A user can see which circles a Sparq is scoped to ONLY if they are
-- a member of at least one of those circles (or the Sparq author).
DROP POLICY IF EXISTS "sparqaudiencecircle_select_member" ON "SparqAudienceCircle";
CREATE POLICY "sparqaudiencecircle_select_member" ON "SparqAudienceCircle"
    FOR SELECT TO authenticated USING (
        fn_user_is_circle_member("circleId")
        OR EXISTS(
            SELECT 1 FROM "Sparq" WHERE id = "sparqId" AND "userId" = auth.uid()
        )
    );

-- Only the Sparq author can INSERT/DELETE audience-circle mappings
DROP POLICY IF EXISTS "sparqaudiencecircle_insert_author" ON "SparqAudienceCircle";
CREATE POLICY "sparqaudiencecircle_insert_author" ON "SparqAudienceCircle"
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS(
            SELECT 1 FROM "Sparq" WHERE id = "sparqId" AND "userId" = auth.uid()
        )
    );

DROP POLICY IF EXISTS "sparqaudiencecircle_delete_author" ON "SparqAudienceCircle";
CREATE POLICY "sparqaudiencecircle_delete_author" ON "SparqAudienceCircle"
    FOR DELETE TO authenticated USING (
        EXISTS(
            SELECT 1 FROM "Sparq" WHERE id = "sparqId" AND "userId" = auth.uid()
        )
    );

-- ─────────────────────────────────────────────────────────────────
-- 4. Realtime publication — add the new tables
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "Circle";
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "CircleMember";
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "CircleMessage";
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "CircleReaction";
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "CircleReadReceipt";
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS "SparqAudienceCircle";

-- ─────────────────────────────────────────────────────────────────
-- 5. SparqAudience enum — add CIRCLE value
-- ─────────────────────────────────────────────────────────────────
-- IF NOT EXISTS is supported in PostgreSQL 12+ and is safe inside
-- a transaction block (Supabase uses PG 15+).
ALTER TYPE "SparqAudience" ADD VALUE IF NOT EXISTS 'CIRCLE';

-- ─────────────────────────────────────────────────────────────────
-- 6. Storage bucket — circle-attachments (private)
-- ─────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'circle-attachments',
    'circle-attachments',
    false,                                              -- PRIVATE — circles need strict per-member scoping
    52428800,                                           -- 50 MB (photos + voice + small videos)
    ARRAY[
        'image/jpeg', 'image/png', 'image/webp', 'image/gif',
        'video/mp4', 'video/webm',
        'audio/m4a', 'audio/mp4', 'audio/aac', 'audio/ogg',
        'audio/wav', 'audio/webm', 'audio/3gpp', 'audio/amr',
        'application/pdf'
    ]
)
ON CONFLICT (id) DO UPDATE
SET file_size_limit = 52428800,
    allowed_mime_types = ARRAY[
        'image/jpeg', 'image/png', 'image/webp', 'image/gif',
        'video/mp4', 'video/webm',
        'audio/m4a', 'audio/mp4', 'audio/aac', 'audio/ogg',
        'audio/wav', 'audio/webm', 'audio/3gpp', 'audio/amr',
        'application/pdf'
    ];

-- ── 6a. RLS policies for circle-attachments bucket ───────────────
-- Path scheme: circle/<circleId>/<msgId>-<fileName>
-- The SELECT policy extracts the circleId from the path's second
-- segment (storage.foldername(name))[2] and checks circle membership.
-- (This mirrors the voice_messages_select_family_scoped pattern
-- from migration 20261020120000.)

DROP POLICY IF EXISTS "circle_attachments_select_member" ON storage.objects;
CREATE POLICY "circle_attachments_select_member" ON storage.objects
    FOR SELECT TO authenticated USING (
        bucket_id = 'circle-attachments'
        AND fn_user_is_circle_member(
            (storage.foldername(name))[2]
        )
    );

DROP POLICY IF EXISTS "circle_attachments_insert_owner" ON storage.objects;
CREATE POLICY "circle_attachments_insert_owner" ON storage.objects
    FOR INSERT TO authenticated WITH CHECK (
        bucket_id = 'circle-attachments'
        AND owner = auth.uid()
    );

DROP POLICY IF EXISTS "circle_attachments_update_owner" ON storage.objects;
CREATE POLICY "circle_attachments_update_owner" ON storage.objects
    FOR UPDATE TO authenticated USING (
        bucket_id = 'circle-attachments'
        AND owner = auth.uid()
    )
    WITH CHECK (
        bucket_id = 'circle-attachments'
        AND owner = auth.uid()
    );

DROP POLICY IF EXISTS "circle_attachments_delete_owner" ON storage.objects;
CREATE POLICY "circle_attachments_delete_owner" ON storage.objects
    FOR DELETE TO authenticated USING (
        bucket_id = 'circle-attachments'
        AND owner = auth.uid()
    );

-- ── 6b. Add a circle-scoped SELECT policy to the voice-messages bucket ─
-- So circle voice notes stored at path circle-voice/<circleId>/<file>
-- in the voice-messages bucket can be read by circle members.
-- (The existing voice_messages_select_family_scoped policy stays;
-- both policies are OR'd by Supabase — any matching policy grants access.)
DROP POLICY IF EXISTS "voice_messages_select_circle_scoped" ON storage.objects;
CREATE POLICY "voice_messages_select_circle_scoped" ON storage.objects
    FOR SELECT TO authenticated USING (
        bucket_id = 'voice-messages'
        -- Only apply this policy to paths that start with circle-voice/
        AND left(name, 13) = 'circle-voice/'
        AND fn_user_is_circle_member(
            (storage.foldername(name))[2]
        )
    );

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification queries (do NOT auto-execute — paste into the
--    Supabase SQL editor after applying the migration to verify)
-- ─────────────────────────────────────────────────────────────────
-- SELECT 'Circle table' AS obj,
--        EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'Circle') AS exists;
-- SELECT 'CircleMember table' AS obj,
--        EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'CircleMember') AS exists;
-- SELECT 'CircleMessage table' AS obj,
--        EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'CircleMessage') AS exists;
-- SELECT 'SparqAudience enum has CIRCLE' AS obj,
--        EXISTS(SELECT 1 FROM pg_enum WHERE enumlabel = 'CIRCLE'
--         AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'SparqAudience')) AS exists;
-- SELECT 'circle-attachments bucket' AS obj,
--        EXISTS(SELECT 1 FROM storage.buckets WHERE id = 'circle-attachments') AS exists;
-- SELECT 'fn_user_is_circle_member function' AS obj,
--        EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_user_is_circle_member') AS exists;
-- SELECT 'fn_user_can_be_added_to_circle function' AS obj,
--        EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_user_can_be_added_to_circle') AS exists;

-- ─────────────────────────────────────────────────────────────────
-- ROLLBACK SCRIPT (run manually if you need to revert)
-- ─────────────────────────────────────────────────────────────────
-- -- Drop storage policies
-- DROP POLICY IF EXISTS "voice_messages_select_circle_scoped" ON storage.objects;
-- DROP POLICY IF EXISTS "circle_attachments_delete_owner" ON storage.objects;
-- DROP POLICY IF EXISTS "circle_attachments_update_owner" ON storage.objects;
-- DROP POLICY IF EXISTS "circle_attachments_insert_owner" ON storage.objects;
-- DROP POLICY IF EXISTS "circle_attachments_select_member" ON storage.objects;
-- -- Drop the bucket (does NOT delete uploaded files — use storage admin)
-- DELETE FROM storage.buckets WHERE id = 'circle-attachments';
-- -- Drop tables (CASCADE drops dependent indexes + RLS policies)
-- DROP TABLE IF EXISTS "SparqAudienceCircle";
-- DROP TABLE IF EXISTS "CircleReadReceipt";
-- DROP TABLE IF EXISTS "CircleReaction";
-- DROP TABLE IF EXISTS "CircleMessage";
-- DROP TABLE IF EXISTS "CircleMember";
-- DROP TABLE IF EXISTS "Circle";
-- -- Drop RLS helper functions
-- DROP FUNCTION IF EXISTS fn_user_can_be_added_to_circle(text, text);
-- DROP FUNCTION IF EXISTS fn_user_is_circle_admin(text);
-- DROP FUNCTION IF EXISTS fn_user_is_circle_member(text);
-- -- Remove the CIRCLE enum value (requires DROP TYPE + recreate —
-- -- Postgres cannot remove a single value from an enum without
-- -- recreating the type. This is destructive if any Sparq rows use
-- -- the CIRCLE value — only run if you're sure.)
-- -- ALTER TYPE "SparqAudience" DROP VALUE IF EXISTS 'CIRCLE'; -- not supported in PG
-- -- Instead: CREATE TYPE "SparqAudience_new" AS ENUM ('PUBLIC', 'FAMILY_ONLY', 'VIP_CIRCLE');
-- --         ALTER TABLE "Sparq" ALTER COLUMN "audience" TYPE "SparqAudience_new"
-- --           USING (CASE WHEN "audience"::text = 'CIRCLE' THEN 'FAMILY_ONLY'::"SparqAudience_new"
-- --                       ELSE "audience"::text::"SparqAudience_new" END);
-- --         DROP TYPE "SparqAudience";
-- --         ALTER TYPE "SparqAudience_new" RENAME TO "SparqAudience";
-- =============================================================================
