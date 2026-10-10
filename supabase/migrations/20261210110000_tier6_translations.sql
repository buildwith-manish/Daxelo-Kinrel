-- =============================================================================
-- Daxelo Kinrel — Tier 6 Feature 6.4: Translation in chat (inline)
-- =============================================================================
-- Lets a user long-press a foreign-language message → "Translate" → the
-- translation renders below the bubble. Cached per (messageId, targetLang)
-- so repeat opens don't re-call the translation provider.
--
-- The actual translation happens server-side via a provider-agnostic
-- TranslationService that supports DeepL OR Google Translate (configured
-- via env var TRANSLATION_PROVIDER + the corresponding API key). When no
-- provider is configured, the service returns a "no_provider" error so
-- the Flutter client can fall back to a "Translate not configured" toast.
--
-- Schema:
--   • MessageTranslation — messageId, targetLang, sourceLang (nullable;
--     detected by the provider), translatedText, provider, confidence,
--     createdAt. UNIQUE on (messageId, targetLang) so the cache is hit
--     on repeat opens.
--   • RLS: family members can SELECT (matches ChatMessage visibility);
--     INSERT/UPDATE only via SECURITY DEFINER RPC (so the provider
--     result is cached authoritatively).
-- =============================================================================

CREATE TABLE IF NOT EXISTS "MessageTranslation" (
  "id"              text PRIMARY KEY,
  "messageId"       text NOT NULL,
  "isDirectMessage" boolean NOT NULL DEFAULT false,  -- true for DirectMessage rows
  "targetLang"      text NOT NULL,                    -- ISO 639-1 code (en, hi, es, fr, ...)
  "sourceLang"      text,                              -- detected by the provider (nullable)
  "translatedText"  text NOT NULL,
  "provider"        text NOT NULL,                    -- 'deepl' | 'google' | 'libretranslate'
  "confidence"      real,                              -- 0..1
  "createdAt"       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "MessageTranslation_msg_lang_uniq"
  ON "MessageTranslation"("messageId", "targetLang");
CREATE INDEX IF NOT EXISTS "MessageTranslation_msg_idx"
  ON "MessageTranslation"("messageId");

ALTER TABLE "MessageTranslation" ENABLE ROW LEVEL SECURITY;

-- SELECT: family members can read (matches ChatMessage visibility for
-- family messages; sender-or-receiver for DMs).
DROP POLICY IF EXISTS "MessageTranslation select" ON "MessageTranslation";
CREATE POLICY "MessageTranslation select" ON "MessageTranslation"
  FOR SELECT TO authenticated USING (
    ("isDirectMessage" = false AND "messageId" IN (
      SELECT cm.id FROM "ChatMessage" cm
      JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
      WHERE fm."userId" = auth.uid()::text
    ))
    OR ("isDirectMessage" = true AND "messageId" IN (
      SELECT dm.id FROM "DirectMessage" dm
      WHERE dm."senderId" = auth.uid()::text OR dm."receiverId" = auth.uid()::text
    ))
  );

-- No INSERT/UPDATE/DELETE policy — writes go through SECURITY DEFINER RPC.

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_cached_translation — returns the cached translation for a
-- (messageId, targetLang) tuple, or null when no cache exists.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_cached_translation(
  p_message_id text,
  p_target_lang text,
  p_is_direct_message boolean DEFAULT false
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

  -- Visibility check (same as the SELECT policy, enforced here as defense-in-depth).
  IF p_is_direct_message THEN
    IF NOT EXISTS (
      SELECT 1 FROM "DirectMessage"
      WHERE "id" = p_message_id
        AND ("senderId" = v_user_id OR "receiverId" = v_user_id)
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_authorized');
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM "ChatMessage" cm
      JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
      WHERE cm."id" = p_message_id AND fm."userId" = v_user_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_authorized');
    END IF;
  END IF;

  SELECT * INTO v_row FROM "MessageTranslation"
    WHERE "messageId" = p_message_id AND "targetLang" = p_target_lang
    LIMIT 1;

  IF v_row IS NULL THEN
    RETURN json_build_object('success', true, 'cached', false);
  END IF;

  RETURN json_build_object(
    'success', true,
    'cached', true,
    'translationId', v_row."id",
    'messageId', v_row."messageId",
    'targetLang', v_row."targetLang",
    'sourceLang', v_row."sourceLang",
    'translatedText', v_row."translatedText",
    'provider', v_row."provider",
    'confidence', v_row."confidence",
    'createdAt', to_char(v_row."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_cached_translation(text, text, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_cache_translation — called by the NestJS TranslationService after a
-- fresh provider response. Inserts (or replaces) the cached row.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cache_translation(
  p_message_id text,
  p_is_direct_message boolean,
  p_target_lang text,
  p_source_lang text,
  p_translated_text text,
  p_provider text,
  p_confidence real DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
BEGIN
  -- No auth check here — this RPC is called by the NestJS server AFTER
  -- it has already validated the caller's identity + visibility. We DO
  -- verify the provider name is one of the supported ones as defense-in-depth.
  IF p_provider NOT IN ('deepl', 'google', 'libretranslate') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_provider');
  END IF;

  v_id := 'mt_' || p_message_id || '_' || p_target_lang;
  INSERT INTO "MessageTranslation" (
    "id", "messageId", "isDirectMessage",
    "targetLang", "sourceLang", "translatedText",
    "provider", "confidence", "createdAt"
  ) VALUES (
    v_id, p_message_id, p_is_direct_message,
    p_target_lang, p_source_lang, p_translated_text,
    p_provider, p_confidence, now()
  )
  ON CONFLICT ("messageId", "targetLang")
  DO UPDATE SET
    "sourceLang" = p_source_lang,
    "translatedText" = p_translated_text,
    "provider" = p_provider,
    "confidence" = p_confidence,
    "createdAt" = now();

  RETURN json_build_object('success', true, 'translationId', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cache_translation(
  text, boolean, text, text, text, text, real
) TO authenticated;

-- Verification
SELECT 'MessageTranslation' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'MessageTranslation') AS exists;
SELECT 'fn_get_cached_translation' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_cached_translation') AS exists;
SELECT 'fn_cache_translation' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cache_translation') AS exists;
