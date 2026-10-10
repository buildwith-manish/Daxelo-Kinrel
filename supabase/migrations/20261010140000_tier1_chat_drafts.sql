-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.3: Auto-saved Drafts (multi-device sync)
-- =============================================================================
-- Lets a user type a message, leave the chat, and come back to find the
-- text still there — and synced to their other devices.
--
-- Schema:
--   • ChatDraft table — id, userId, familyId, receiverId, draftText,
--     replyToId, updatedAt. (familyId OR receiverId is set; the other
--     is null. For Saved Messages: receiverId = userId.)
--   • RLS: only the owner can read/write their drafts.
--   • Realtime publication so the user's other devices see the draft
--     update live (Supabase Realtime broadcasts the UPDATE).
--
-- Server:
--   • NestJS exposes PUT /chat/draft (upsert) + GET /chat/drafts (list).
--   • The Flutter client debounce-writes the controller text 800ms after
--     the last keystroke.
--
-- Idempotent.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ChatDraft" (
  "id"          text PRIMARY KEY,
  "userId"      text NOT NULL,
  "familyId"    text,                  -- null when this is a DM draft
  "receiverId"  text,                  -- null when this is a family-group draft
  "draftText"   text NOT NULL DEFAULT '',
  "replyToId"   text,
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  "updatedAt"   timestamptz NOT NULL DEFAULT now(),
  -- A draft must target exactly one of family / DM.
  CONSTRAINT "cd_target_chk" CHECK (
    ("familyId" IS NOT NULL AND "receiverId" IS NULL) OR
    ("familyId" IS NULL AND "receiverId" IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS "ChatDraft_user_target_uniq"
  ON "ChatDraft"("userId", COALESCE("familyId", ''), COALESCE("receiverId", ''));

CREATE INDEX IF NOT EXISTS "ChatDraft_user_idx" ON "ChatDraft"("userId");
CREATE INDEX IF NOT EXISTS "ChatDraft_updated_idx" ON "ChatDraft"("updatedAt" DESC);

ALTER TABLE "ChatDraft" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ChatDraft select own" ON "ChatDraft";
CREATE POLICY "ChatDraft select own" ON "ChatDraft"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatDraft insert own" ON "ChatDraft";
CREATE POLICY "ChatDraft insert own" ON "ChatDraft"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatDraft update own" ON "ChatDraft";
CREATE POLICY "ChatDraft update own" ON "ChatDraft"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "ChatDraft delete own" ON "ChatDraft";
CREATE POLICY "ChatDraft delete own" ON "ChatDraft"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- Realtime: the user's other devices need to see draft updates as they
-- happen (so typing on the phone is mirrored on desktop). We add the
-- table to the supabase_realtime publication.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE "ChatDraft" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ChatDraft'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatDraft";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_save_draft — upsert a draft for the caller.
--   Pass either p_family_id (group) or p_receiver_id (DM/Saved Messages).
--   p_draft_text='' or NULL will DELETE the existing draft (clears on send).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_save_draft(
  p_family_id text,
  p_receiver_id text,
  p_draft_text text,
  p_reply_to_id text DEFAULT NULL
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

  IF (p_family_id IS NULL) = (p_receiver_id IS NULL) THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target',
      'message', 'Pass exactly one of familyId or receiverId.');
  END IF;

  -- Empty draft = clear (matches WhatsApp: send clears the draft).
  IF p_draft_text IS NULL OR btrim(p_draft_text) = '' THEN
    DELETE FROM "ChatDraft"
      WHERE "userId" = v_user_id
        AND COALESCE("familyId", '') = COALESCE(p_family_id, '')
        AND COALESCE("receiverId", '') = COALESCE(p_receiver_id, '');
    RETURN json_build_object('success', true, 'action', 'cleared');
  END IF;

  SELECT * INTO v_existing FROM "ChatDraft"
    WHERE "userId" = v_user_id
      AND COALESCE("familyId", '') = COALESCE(p_family_id, '')
      AND COALESCE("receiverId", '') = COALESCE(p_receiver_id, '');

  IF v_existing IS NOT NULL THEN
    UPDATE "ChatDraft"
      SET "draftText" = p_draft_text,
          "replyToId" = p_reply_to_id,
          "updatedAt" = now()
      WHERE "id" = v_existing."id";
    RETURN json_build_object('success', true, 'action', 'updated', 'draftId', v_existing."id");
  END IF;

  v_id := 'cd_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "ChatDraft" (
    "id", "userId", "familyId", "receiverId",
    "draftText", "replyToId",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id, p_receiver_id,
    p_draft_text, p_reply_to_id,
    now(), now()
  );
  RETURN json_build_object('success', true, 'action', 'created', 'draftId', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_draft(text, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_draft — load the caller's draft for a specific chat (or null)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_draft(
  p_family_id text,
  p_receiver_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_row FROM "ChatDraft"
    WHERE "userId" = v_user_id
      AND COALESCE("familyId", '') = COALESCE(p_family_id, '')
      AND COALESCE("receiverId", '') = COALESCE(p_receiver_id, '');

  IF v_row IS NULL THEN
    RETURN json_build_object('success', true, 'hasDraft', false, 'draftText', NULL, 'replyToId', NULL);
  END IF;

  RETURN json_build_object(
    'success', true,
    'hasDraft', true,
    'draftText', v_row."draftText",
    'replyToId', v_row."replyToId",
    'updatedAt', to_char(v_row."updatedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_draft(text, text) TO authenticated;

-- Verification
SELECT 'ChatDraft' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatDraft') AS exists;
SELECT 'fn_save_draft' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_save_draft') AS exists;
SELECT 'fn_get_draft' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_draft') AS exists;
