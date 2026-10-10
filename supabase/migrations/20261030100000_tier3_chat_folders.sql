-- =============================================================================
-- Daxelo Kinrel — Tier 3 Feature 3.1: Chat Folders (Telegram-style)
-- =============================================================================
-- Lets a user organize their inbox with custom folders. Each folder has a
-- ruleType ('all' | 'unread' | 'family' | 'dm' | 'by-name' | 'by-user-id')
-- + a ruleValue (the parameter for the rule). Examples:
--   • "All"          ruleType='all'
--   • "Unread"       ruleType='unread'
--   • "Family chats" ruleType='family'
--   • "Direct chats" ruleType='dm'
--   • "By name: Sharma" ruleType='by-name' ruleValue='Sharma'
--   • "From user: <userId>" ruleType='by-user-id' ruleValue='<userId>'
--
-- The Flutter inbox renders a horizontal folder bar at the top. Tapping
-- a folder filters the inbox by its rule. Each folder carries an unread
-- count badge.
--
-- Schema:
--   • ChatFolder table — id, userId, name, iconEmoji, ruleType, ruleValue,
--     orderIndex, includeUnread (whether 'unread' folder rule is also
--     applied additively).
--   • RLS: only the owner can read/write their folders.
--
-- Idempotent.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ChatFolder" (
  "id"            text PRIMARY KEY,
  "userId"        text NOT NULL,
  "name"          text NOT NULL,
  "iconEmoji"     text,
  "ruleType"      text NOT NULL,   -- all | unread | family | dm | by-name | by-user-id
  "ruleValue"     text,            -- null when ruleType in (all, unread, family, dm)
  "orderIndex"    integer NOT NULL DEFAULT 0,
  "includeUnread" boolean NOT NULL DEFAULT false,  -- additive: also filter to unread
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "ChatFolder_ruleType_chk" CHECK (
    "ruleType" IN ('all', 'unread', 'family', 'dm', 'by-name', 'by-user-id')
  )
);

CREATE INDEX IF NOT EXISTS "ChatFolder_user_idx"      ON "ChatFolder"("userId", "orderIndex");
CREATE UNIQUE INDEX IF NOT EXISTS "ChatFolder_user_name_uniq" ON "ChatFolder"("userId", lower("name"));

ALTER TABLE "ChatFolder" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ChatFolder select own" ON "ChatFolder";
CREATE POLICY "ChatFolder select own" ON "ChatFolder"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatFolder insert own" ON "ChatFolder";
CREATE POLICY "ChatFolder insert own" ON "ChatFolder"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatFolder update own" ON "ChatFolder";
CREATE POLICY "ChatFolder update own" ON "ChatFolder"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatFolder delete own" ON "ChatFolder";
CREATE POLICY "ChatFolder delete own" ON "ChatFolder"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Realtime: the user's other devices see folder changes live (so a folder
-- created on the phone shows up on desktop instantly).
ALTER TABLE "ChatFolder" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ChatFolder'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatFolder";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_save_chat_folder — upsert a folder. Empty name = delete (matches the
-- draft pattern).
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS fn_save_chat_folder(text, text, text, text, text, integer, boolean);
CREATE OR REPLACE FUNCTION fn_save_chat_folder(
  p_folder_id text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_icon_emoji text DEFAULT NULL,
  p_rule_type text DEFAULT 'all',
  p_rule_value text DEFAULT NULL,
  p_order_index integer DEFAULT 0,
  p_include_unread boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_existing record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_rule_type NOT IN ('all', 'unread', 'family', 'dm', 'by-name', 'by-user-id') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_rule_type');
  END IF;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_name');
  END IF;

  IF p_folder_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM "ChatFolder" WHERE "id" = p_folder_id AND "userId" = v_user_id;
    IF v_existing IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'not_found');
    END IF;
    UPDATE "ChatFolder"
      SET "name" = p_name,
          "iconEmoji" = p_icon_emoji,
          "ruleType" = p_rule_type,
          "ruleValue" = p_rule_value,
          "orderIndex" = p_order_index,
          "includeUnread" = p_include_unread,
          "updatedAt" = now()
      WHERE "id" = p_folder_id;
    RETURN json_build_object('success', true, 'action', 'updated', 'folderId', p_folder_id);
  END IF;

  v_id := 'cf_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "ChatFolder" (
    "id", "userId", "name", "iconEmoji",
    "ruleType", "ruleValue", "orderIndex", "includeUnread",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_name, p_icon_emoji,
    p_rule_type, p_rule_value, p_order_index, p_include_unread,
    now(), now()
  );
  RETURN json_build_object('success', true, 'action', 'created', 'folderId', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_chat_folder(
  text, text, text, text, text, integer, boolean
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_list_chat_folders — caller's folders ordered by orderIndex
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS fn_list_chat_folders();
CREATE OR REPLACE FUNCTION fn_list_chat_folders()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', f."id",
      'userId', f."userId",
      'name', f."name",
      'iconEmoji', f."iconEmoji",
      'ruleType', f."ruleType",
      'ruleValue', f."ruleValue",
      'orderIndex', f."orderIndex",
      'includeUnread', f."includeUnread",
      'createdAt', to_char(f."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'updatedAt', to_char(f."updatedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ) ORDER BY f."orderIndex" ASC)
    FROM "ChatFolder" f
    WHERE f."userId" = v_user_id
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_list_chat_folders() TO authenticated;

-- Verification
SELECT 'ChatFolder' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatFolder') AS exists;
SELECT 'fn_save_chat_folder' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_save_chat_folder') AS exists;
SELECT 'fn_list_chat_folders' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_list_chat_folders') AS exists;
