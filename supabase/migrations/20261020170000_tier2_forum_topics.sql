-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.5: Forum Topics in Groups (Telegram-style)
-- =============================================================================
-- Schema-only migration. Adds the ChatTopic table + a nullable topicId column
-- on ChatMessage so each topic is its own message thread within a family chat.
--
-- NOTE: This migration adds the SCHEMA only. The NestJS listMessages filter
-- + Flutter TopicsGridScreen UI are follow-up tasks. See WORKLOG.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ChatTopic" (
  "id"            text PRIMARY KEY,
  "familyId"      text NOT NULL,
  "name"          text NOT NULL,
  "emoji"         text,
  "iconUrl"       text,
  "createdBy"     text NOT NULL,
  "isLocked"      boolean NOT NULL DEFAULT false,
  "isGeneral"     boolean NOT NULL DEFAULT false,  -- the General topic is always present + immutable
  "lastMessageAt" timestamptz,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ChatTopic_family_idx"        ON "ChatTopic"("familyId", "lastMessageAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatTopic_family_general_idx" ON "ChatTopic"("familyId") WHERE "isGeneral" = true;
CREATE UNIQUE INDEX IF NOT EXISTS "ChatTopic_general_uniq"
  ON "ChatTopic"("familyId") WHERE "isGeneral" = true;

ALTER TABLE "ChatTopic" ENABLE ROW LEVEL SECURITY;

-- SELECT: family members can see all topics.
DROP POLICY IF EXISTS "ChatTopic select member" ON "ChatTopic";
CREATE POLICY "ChatTopic select member" ON "ChatTopic"
  FOR SELECT TO authenticated USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- INSERT: family members can create topics (admins lock them later).
DROP POLICY IF EXISTS "ChatTopic insert member" ON "ChatTopic";
CREATE POLICY "ChatTopic insert member" ON "ChatTopic"
  FOR INSERT TO authenticated WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- UPDATE: only admins/creators can lock/unlock + rename.
DROP POLICY IF EXISTS "ChatTopic update admin" ON "ChatTopic";
CREATE POLICY "ChatTopic update admin" ON "ChatTopic"
  FOR UPDATE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "ChatTopic"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('admin', 'creator')
    )
  );

-- Add the topicId column on ChatMessage (nullable — null = General topic).
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "topicId" text;

CREATE INDEX IF NOT EXISTS "ChatMessage_topic_idx" ON "ChatMessage"("familyId", "topicId", "createdAt" DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_create_chat_topic — admin-only topic creation (except General which is
-- auto-created when the family is created + is immutable).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_create_chat_topic(
  p_family_id text,
  p_name text,
  p_emoji text DEFAULT NULL,
  p_icon_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  SELECT role INTO v_role FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  IF v_role NOT IN ('admin', 'creator') THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_name');
  END IF;

  v_id := 'ct_' || extract(epoch from now())::bigint::text || '_' || substring(p_family_id from 1 for 8);
  INSERT INTO "ChatTopic" (
    "id", "familyId", "name", "emoji", "iconUrl",
    "createdBy", "isGeneral", "createdAt", "updatedAt"
  ) VALUES (
    v_id, p_family_id, p_name, p_emoji, p_icon_url,
    v_user_id, false, now(), now()
  );

  PERFORM fn_log_group_audit(
    p_family_id, v_user_id, 'topic_created',
    NULL, NULL, jsonb_build_object('topicId', v_id, 'name', p_name)
  );

  RETURN json_build_object('success', true, 'topicId', v_id, 'familyId', p_family_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_chat_topic(text, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_ensure_general_topic — called by trigger when a family is created so
-- the General topic always exists. Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_ensure_general_topic(p_family_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing text;
BEGIN
  SELECT id INTO v_existing FROM "ChatTopic"
    WHERE "familyId" = p_family_id AND "isGeneral" = true;
  IF v_existing IS NOT NULL THEN RETURN; END IF;

  INSERT INTO "ChatTopic" (
    "id", "familyId", "name", "emoji",
    "createdBy", "isGeneral",
    "createdAt", "updatedAt"
  ) VALUES (
    'ct_general_' || p_family_id,
    p_family_id, 'General', '📌',
    'system', true,
    now(), now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_ensure_general_topic(text) TO authenticated;

-- Verification
SELECT 'ChatTopic' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatTopic') AS exists;
SELECT 'ChatMessage.topicId' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'topicId'
       ) AS exists;
SELECT 'fn_create_chat_topic' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_chat_topic') AS exists;
SELECT 'fn_ensure_general_topic' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_ensure_general_topic') AS exists;
