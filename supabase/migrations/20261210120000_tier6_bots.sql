-- =============================================================================
-- Daxelo Kinrel — Tier 6 Features 6.6 + 6.7: Bots + Inline bots + Mini-apps
-- =============================================================================
-- Schema for Telegram-style bots:
--   • DM with a bot — the user sends messages, the bot responds via webhook
--     (the NestJS BotsService dispatches the incoming message to the bot's
--     configured webhookUrl).
--   • Inline bots — type `@gif cat` in any chat → the bot returns inline
--     results (e.g. 10 cat GIFs) → tap to send as a normal message.
--   • Mini-apps — a bot can render a mini web-app inside the chat (Telegram
--     Web Apps pattern). The NestJS BotMiniAppsService issues a signed
--     initData token so the web-app can verify the user identity + chat
--     context securely.
--
-- Schema:
--   • Bot — id, name, handle (unique, @-prefixed), ownerUserId, webhookUrl,
--     isInline (can be used inline), description, avatarUrl, isVerified,
--     createdAt.
--   • BotMessage — id, botId, userId (the user the bot is talking to),
--     direction ('incoming' = user→bot, 'outgoing' = bot→user),
--     content, payload (jsonb — inline results, mini-app initData, etc.),
--     createdAt.
--   • UserBotInstall — userId + botId (so the user can pin favorite bots).
--   • BotMiniAppSession — id, botId, userId, familyId|receiverId, initData,
--     expiresAt, createdAt. The initData is a JWT-like signed token
--     (HMAC-SHA256) that the web-app verifies.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "Bot" (
  "id"          text PRIMARY KEY,
  "name"        text NOT NULL,
  "handle"      text NOT NULL UNIQUE,                 -- @gif_bot, @poll_maker_bot, etc.
  "ownerUserId" text NOT NULL,
  "webhookUrl"  text,                                  -- null for inline-only bots
  "isInline"    boolean NOT NULL DEFAULT false,
  "description" text,
  "avatarUrl"   text,
  "isVerified"  boolean NOT NULL DEFAULT false,
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  "updatedAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "Bot_handle_lower_idx" ON "Bot"(lower("handle"));
CREATE INDEX IF NOT EXISTS "Bot_owner_idx"        ON "Bot"("ownerUserId");
CREATE INDEX IF NOT EXISTS "Bot_inline_idx"       ON "Bot"("isInline", "name") WHERE "isInline" = true;

CREATE TABLE IF NOT EXISTS "BotMessage" (
  "id"         text PRIMARY KEY,
  "botId"      text NOT NULL REFERENCES "Bot"(id) ON DELETE CASCADE,
  "userId"     text NOT NULL,                          -- the user the bot is talking to
  "direction"  text NOT NULL,                          -- 'incoming' | 'outgoing'
  "content"    text NOT NULL DEFAULT '',
  "payload"    jsonb NOT NULL DEFAULT '[]'::jsonb,     -- inline results, mini-app refs, etc.
  "createdAt"  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "BotMessage_direction_chk" CHECK ("direction" IN ('incoming', 'outgoing'))
);

CREATE INDEX IF NOT EXISTS "BotMessage_bot_user_idx" ON "BotMessage"("botId", "userId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "UserBotInstall" (
  "id"        text PRIMARY KEY,
  "userId"    text NOT NULL,
  "botId"     text NOT NULL REFERENCES "Bot"(id) ON DELETE CASCADE,
  "installedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("userId", "botId")
);

CREATE INDEX IF NOT EXISTS "UserBotInstall_user_idx" ON "UserBotInstall"("userId", "installedAt" DESC);

CREATE TABLE IF NOT EXISTS "BotMiniAppSession" (
  "id"          text PRIMARY KEY,
  "botId"       text NOT NULL REFERENCES "Bot"(id) ON DELETE CASCADE,
  "userId"      text NOT NULL,
  "familyId"    text,                                  -- null when launched from a DM
  "receiverId"  text,                                  -- null when launched from a family chat
  "initData"    text NOT NULL,                         -- signed token (HMAC-SHA256)
  "expiresAt"   timestamptz NOT NULL,
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "BotMiniAppSession_bot_user_idx" ON "BotMiniAppSession"("botId", "userId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "BotMiniAppSession_expires_idx"   ON "BotMiniAppSession"("expiresAt");

-- RLS.

-- Bot is publicly readable (the catalog is browseable).
ALTER TABLE "Bot" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Bot select" ON "Bot";
CREATE POLICY "Bot select" ON "Bot"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Bot insert owner" ON "Bot";
CREATE POLICY "Bot insert owner" ON "Bot"
  FOR INSERT TO authenticated WITH CHECK ("ownerUserId" = auth.uid()::text);
DROP POLICY IF EXISTS "Bot update owner" ON "Bot";
CREATE POLICY "Bot update owner" ON "Bot"
  FOR UPDATE TO authenticated USING ("ownerUserId" = auth.uid()::text);
DROP POLICY IF EXISTS "Bot delete owner" ON "Bot";
CREATE POLICY "Bot delete owner" ON "Bot"
  FOR DELETE TO authenticated USING ("ownerUserId" = auth.uid()::text);

-- BotMessage: visible to the user the bot is talking to AND to the bot's owner.
ALTER TABLE "BotMessage" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "BotMessage select" ON "BotMessage";
CREATE POLICY "BotMessage select" ON "BotMessage"
  FOR SELECT TO authenticated USING (
    "userId" = auth.uid()::text
    OR "botId" IN (SELECT id FROM "Bot" WHERE "ownerUserId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "BotMessage insert" ON "BotMessage";
CREATE POLICY "BotMessage insert" ON "BotMessage"
  FOR INSERT TO authenticated WITH CHECK (
    "userId" = auth.uid()::text
    OR "botId" IN (SELECT id FROM "Bot" WHERE "ownerUserId" = auth.uid()::text)
  );

-- UserBotInstall: owner-only.
ALTER TABLE "UserBotInstall" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "UserBotInstall select own" ON "UserBotInstall";
CREATE POLICY "UserBotInstall select own" ON "UserBotInstall"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserBotInstall insert own" ON "UserBotInstall";
CREATE POLICY "UserBotInstall insert own" ON "UserBotInstall"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserBotInstall delete own" ON "UserBotInstall";
CREATE POLICY "UserBotInstall delete own" ON "UserBotInstall"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- BotMiniAppSession: visible to the user the session was issued for.
ALTER TABLE "BotMiniAppSession" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "BotMiniAppSession select own" ON "BotMiniAppSession";
CREATE POLICY "BotMiniAppSession select own" ON "BotMiniAppSession"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
-- INSERT/UPDATE only via SECURITY DEFINER RPC.

-- Realtime: the user sees bot responses appear live in the DM.
ALTER TABLE "BotMessage" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'BotMessage'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "BotMessage";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_create_bot — caller registers a new bot. The handle must start with
-- a letter + be 4-32 chars (letters/digits/underscore). The webhookUrl is
-- optional (null for inline-only bots).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_create_bot(
  p_name text,
  p_handle text,
  p_webhook_url text DEFAULT NULL,
  p_is_inline boolean DEFAULT false,
  p_description text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_handle text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_name');
  END IF;
  -- Normalize handle: lowercase + ensure no leading @.
  v_handle := lower(btrim(p_handle));
  v_handle := regexp_replace(v_handle, '^@', '');
  IF char_length(v_handle) < 4 OR char_length(v_handle) > 32 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_handle_length');
  END IF;
  IF v_handle !~ '^[a-z][a-z0-9_]*$' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_handle_format',
      'message', 'Handle must start with a letter + use only letters, digits, underscore.');
  END IF;

  v_id := 'bot_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);
  INSERT INTO "Bot" (
    "id", "name", "handle", "ownerUserId",
    "webhookUrl", "isInline", "description", "avatarUrl",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, p_name, v_handle, v_user_id,
    p_webhook_url, p_is_inline, p_description, p_avatar_url,
    now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'botId', v_id,
    'handle', v_handle
  );
EXCEPTION WHEN unique_violation THEN
  RETURN json_build_object('success', false, 'error', 'handle_taken');
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_bot(
  text, text, text, boolean, text, text
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_bot_by_handle — fetch a bot by its @handle (for inline bot resolution).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_bot_by_handle(p_handle text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_handle text := lower(btrim(p_handle));
BEGIN
  v_handle := regexp_replace(v_handle, '^@', '');
  SELECT * INTO v_row FROM "Bot" WHERE lower("handle") = v_handle;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'bot_not_found');
  END IF;
  RETURN json_build_object(
    'success', true,
    'botId', v_row."id",
    'name', v_row."name",
    'handle', v_row."handle",
    'isInline', v_row."isInline",
    'webhookUrl', v_row."webhookUrl",
    'avatarUrl', v_row."avatarUrl",
    'description', v_row."description"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_bot_by_handle(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_install_bot — pin a bot to the user's installed list (so it shows
-- in the picker). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_install_bot(p_bot_id text)
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
  IF NOT EXISTS (SELECT 1 FROM "Bot" WHERE id = p_bot_id) THEN
    RETURN json_build_object('success', false, 'error', 'bot_not_found');
  END IF;

  v_id := 'ubi_' || p_bot_id || '_' || v_user_id;
  INSERT INTO "UserBotInstall" ("id", "userId", "botId", "installedAt")
  VALUES (v_id, v_user_id, p_bot_id, now())
  ON CONFLICT ("userId", "botId") DO NOTHING;

  RETURN json_build_object('success', true, 'botId', p_bot_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_install_bot(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_create_mini_app_session — issues a signed initData token for a bot
-- mini-app launch. The token is HMAC-SHA256 signed with a server-side
-- secret (BOT_MINIAPP_SECRET env var) — the web-app verifies the signature
-- to confirm the user identity + chat context.
--
-- NOTE: the actual HMAC signing happens in the NestJS BotMiniAppsService
-- (we don't expose the secret to SQL). This RPC just persists the session
-- row + returns the unsigned payload that the NestJS layer then signs.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_create_mini_app_session(
  p_bot_id text,
  p_family_id text DEFAULT NULL,
  p_receiver_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_expires_at timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF (p_family_id IS NULL) = (p_receiver_id IS NULL) THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target',
      'message', 'Pass exactly one of familyId or receiverId.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "Bot" WHERE id = p_bot_id) THEN
    RETURN json_build_object('success', false, 'error', 'bot_not_found');
  END IF;

  -- Validate family membership OR DM self-presence.
  IF p_family_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = p_family_id AND "userId" = v_user_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_in_family');
    END IF;
  END IF;

  v_expires_at := now() + interval '1 hour';
  v_id := 'bmas_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);

  INSERT INTO "BotMiniAppSession" (
    "id", "botId", "userId",
    "familyId", "receiverId",
    "initData", "expiresAt", "createdAt"
  ) VALUES (
    v_id, p_bot_id, v_user_id,
    p_family_id, p_receiver_id,
    '',  -- placeholder; the NestJS layer overwrites this with the signed token
    v_expires_at, now()
  );

  RETURN json_build_object(
    'success', true,
    'sessionId', v_id,
    'botId', p_bot_id,
    'userId', v_user_id,
    'familyId', p_family_id,
    'receiverId', p_receiver_id,
    'expiresAt', to_char(v_expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_mini_app_session(text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_cleanup_expired_mini_app_sessions — hourly cron.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cleanup_expired_mini_app_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  DELETE FROM "BotMiniAppSession" WHERE "expiresAt" < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Mini-app session cleanup: deleted % expired rows', v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cleanup_expired_mini_app_sessions() TO authenticated;

DO $$
DECLARE
  v_job_name text := 'cleanup-expired-mini-app-sessions';
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = v_job_name;
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      v_job_name,
      '0 * * * *',  -- hourly
      'SELECT fn_cleanup_expired_mini_app_sessions();'
    );
    RAISE NOTICE 'Scheduled cron job %', v_job_name;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron schedule skipped: %', SQLERRM;
END $$;

-- Verification
SELECT 'Bot' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'Bot') AS exists;
SELECT 'BotMessage' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'BotMessage') AS exists;
SELECT 'UserBotInstall' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserBotInstall') AS exists;
SELECT 'BotMiniAppSession' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'BotMiniAppSession') AS exists;
SELECT 'fn_create_bot' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_bot') AS exists;
SELECT 'fn_get_bot_by_handle' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_bot_by_handle') AS exists;
SELECT 'fn_install_bot' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_install_bot') AS exists;
SELECT 'fn_create_mini_app_session' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_mini_app_session') AS exists;
SELECT 'fn_cleanup_expired_mini_app_sessions' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cleanup_expired_mini_app_sessions') AS exists;
SELECT 'cron job mini-app' AS obj,
       EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'cleanup-expired-mini-app-sessions') AS exists;
