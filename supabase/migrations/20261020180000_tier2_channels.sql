-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.2: Channels (broadcast, one-to-many)
-- =============================================================================
-- Schema-only migration. Lets any user create a channel; subscribers get
-- posts but can't reply (only admins post). Posts support all media + reactions.
-- Subscriber count visible.
--
-- NOTE: This migration adds the SCHEMA only. The NestJS channels/ module +
-- Flutter ChannelScreen UI are follow-up tasks. See WORKLOG.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "Channel" (
  "id"              text PRIMARY KEY,
  "name"            text NOT NULL,
  "handle"          text NOT NULL UNIQUE,           -- @channel_handle
  "description"     text,
  "avatarUrl"       text,
  "ownerId"         text NOT NULL,
  "isPublic"        boolean NOT NULL DEFAULT true,
  "subscriberCount" integer NOT NULL DEFAULT 0,
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "updatedAt"       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "Channel_owner_idx"      ON "Channel"("ownerId");
CREATE INDEX IF NOT EXISTS "Channel_handle_lower_idx" ON "Channel"(lower("handle"));

CREATE TABLE IF NOT EXISTS "ChannelSubscriber" (
  "id"          text PRIMARY KEY,
  "channelId"   text NOT NULL REFERENCES "Channel"(id) ON DELETE CASCADE,
  "userId"      text NOT NULL,
  "joinedAt"    timestamptz NOT NULL DEFAULT now(),
  "muted"       boolean NOT NULL DEFAULT false,
  UNIQUE("channelId", "userId")
);

CREATE INDEX IF NOT EXISTS "ChannelSubscriber_channel_idx" ON "ChannelSubscriber"("channelId");
CREATE INDEX IF NOT EXISTS "ChannelSubscriber_user_idx"    ON "ChannelSubscriber"("userId");

CREATE TABLE IF NOT EXISTS "ChannelPost" (
  "id"            text PRIMARY KEY,
  "channelId"     text NOT NULL REFERENCES "Channel"(id) ON DELETE CASCADE,
  "senderId"      text NOT NULL,
  "content"       text NOT NULL DEFAULT '',
  "messageType"   text NOT NULL DEFAULT 'text',
  "mediaUrl"      text,
  "mediaType"     text,
  "caption"       text,
  "forwardedFrom" text,
  "replyToId"      text,
  "editedAt"      timestamptz,
  "viewsCount"    integer NOT NULL DEFAULT 0,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ChannelPost_channel_idx" ON "ChannelPost"("channelId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChannelPost_sender_idx"  ON "ChannelPost"("senderId");

CREATE TABLE IF NOT EXISTS "ChannelReaction" (
  "id"          text PRIMARY KEY,
  "postId"      text NOT NULL REFERENCES "ChannelPost"(id) ON DELETE CASCADE,
  "userId"      text NOT NULL,
  "emoji"       text NOT NULL,
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  UNIQUE("postId", "userId")
);

CREATE INDEX IF NOT EXISTS "ChannelReaction_post_idx" ON "ChannelReaction"("postId");

-- RLS — only the channel owner can write posts; subscribers can read + react.

ALTER TABLE "Channel" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Channel select" ON "Channel";
CREATE POLICY "Channel select" ON "Channel"
  FOR SELECT TO authenticated USING ("isPublic" = true OR "ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "Channel insert" ON "Channel";
CREATE POLICY "Channel insert" ON "Channel"
  FOR INSERT TO authenticated WITH CHECK ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "Channel update" ON "Channel";
CREATE POLICY "Channel update" ON "Channel"
  FOR UPDATE TO authenticated USING ("ownerId" = auth.uid()::text);

ALTER TABLE "ChannelSubscriber" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ChannelSubscriber select" ON "ChannelSubscriber";
CREATE POLICY "ChannelSubscriber select" ON "ChannelSubscriber"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text OR "channelId" IN (SELECT id FROM "Channel" WHERE "ownerId" = auth.uid()::text));
DROP POLICY IF EXISTS "ChannelSubscriber insert" ON "ChannelSubscriber";
CREATE POLICY "ChannelSubscriber insert" ON "ChannelSubscriber"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "ChannelSubscriber delete" ON "ChannelSubscriber";
CREATE POLICY "ChannelSubscriber delete" ON "ChannelSubscriber"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "ChannelPost" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ChannelPost select subscriber" ON "ChannelPost";
CREATE POLICY "ChannelPost select subscriber" ON "ChannelPost"
  FOR SELECT TO authenticated USING (
    "channelId" IN (
      SELECT "channelId" FROM "ChannelSubscriber"
      WHERE "userId" = auth.uid()::text
    )
    OR "channelId" IN (SELECT id FROM "Channel" WHERE "ownerId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "ChannelPost insert owner" ON "ChannelPost";
CREATE POLICY "ChannelPost insert owner" ON "ChannelPost"
  FOR INSERT TO authenticated WITH CHECK (
    "channelId" IN (SELECT id FROM "Channel" WHERE "ownerId" = auth.uid()::text)
  );

ALTER TABLE "ChannelReaction" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ChannelReaction select" ON "ChannelReaction";
CREATE POLICY "ChannelReaction select" ON "ChannelReaction"
  FOR SELECT TO authenticated USING (
    "postId" IN (
      SELECT cp.id FROM "ChannelPost" cp
      JOIN "ChannelSubscriber" cs ON cs."channelId" = cp."channelId"
      WHERE cs."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "ChannelReaction insert own" ON "ChannelReaction";
CREATE POLICY "ChannelReaction insert own" ON "ChannelReaction"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "ChannelReaction delete own" ON "ChannelReaction";
CREATE POLICY "ChannelReaction delete own" ON "ChannelReaction"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Realtime publication on ChannelPost so subscribers see new posts live.
ALTER TABLE "ChannelPost" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ChannelPost'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChannelPost";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_subscribe_to_channel — idempotent subscribe (inserts row if absent +
-- bumps the channel's subscriberCount)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_subscribe_to_channel(p_channel_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "Channel" WHERE id = p_channel_id AND "isPublic" = true) THEN
    RETURN json_build_object('success', false, 'error', 'not_found_or_private');
  END IF;

  INSERT INTO "ChannelSubscriber" ("id", "channelId", "userId", "joinedAt")
  VALUES ('cs_' || p_channel_id || '_' || v_user_id, p_channel_id, v_user_id, now())
  ON CONFLICT ("channelId", "userId") DO NOTHING;

  UPDATE "Channel"
    SET "subscriberCount" = "subscriberCount" + 1, "updatedAt" = now()
    WHERE id = p_channel_id
      AND NOT EXISTS (SELECT 1 FROM "ChannelSubscriber" WHERE "channelId" = p_channel_id AND "userId" = v_user_id);

  RETURN json_build_object('success', true, 'channelId', p_channel_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_subscribe_to_channel(text) TO authenticated;

-- Verification
SELECT 'Channel' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'Channel') AS exists;
SELECT 'ChannelSubscriber' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChannelSubscriber') AS exists;
SELECT 'ChannelPost' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChannelPost') AS exists;
SELECT 'ChannelReaction' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChannelReaction') AS exists;
SELECT 'fn_subscribe_to_channel' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_subscribe_to_channel') AS exists;
