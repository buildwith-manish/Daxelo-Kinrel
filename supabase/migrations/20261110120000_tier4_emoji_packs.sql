-- =============================================================================
-- Daxelo Kinrel — Tier 4 Feature 4.6: Custom emoji packs
-- =============================================================================
-- Lets a user install custom emoji packs (PNG or Lottie). Each pack has
-- up to 50 emoji. Installed packs show in the emoji picker + reaction tray.
--
-- Schema:
--   • EmojiPack       — id, name, thumbUrl, isAnimated, isOfficial,
--     publisherName, createdAt.
--   • EmojiPackItem   — id, packId (FK CASCADE), emojiName, imageUrl,
--     lottieUrl (nullable), keywords (text[] for search), createdAt.
--   • UserEmojiPackInstall — join table tracking which packs a user has
--     installed (so the picker only shows installed packs).
--
-- Unlike UserStickerPack (which is per-user owned content), EmojiPacks are
-- GLOBAL catalog rows (any user can install them). The "install" relation
-- is per-user.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "EmojiPack" (
  "id"            text PRIMARY KEY,
  "name"          text NOT NULL,
  "thumbUrl"      text,
  "isAnimated"    boolean NOT NULL DEFAULT false,
  "isOfficial"    boolean NOT NULL DEFAULT false,   -- true for built-in packs
  "publisherName" text,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "EmojiPack_official_idx" ON "EmojiPack"("isOfficial", "name");

CREATE TABLE IF NOT EXISTS "EmojiPackItem" (
  "id"          text PRIMARY KEY,
  "packId"      text NOT NULL REFERENCES "EmojiPack"(id) ON DELETE CASCADE,
  "emojiName"   text NOT NULL,                  -- e.g. "party_parrot"
  "imageUrl"    text NOT NULL,                   -- static PNG/WebP
  "lottieUrl"   text,                            -- when isAnimated=true
  "keywords"    text[] NOT NULL DEFAULT '{}',   -- for picker search
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "EmojiPackItem_pack_idx"  ON "EmojiPackItem"("packId");
CREATE INDEX IF NOT EXISTS "EmojiPackItem_keywords_idx" ON "EmojiPackItem" USING GIN ("keywords");

CREATE TABLE IF NOT EXISTS "UserEmojiPackInstall" (
  "id"        text PRIMARY KEY,
  "userId"    text NOT NULL,
  "packId"    text NOT NULL REFERENCES "EmojiPack"(id) ON DELETE CASCADE,
  "installedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("userId", "packId")
);

CREATE INDEX IF NOT EXISTS "UserEmojiPackInstall_user_idx" ON "UserEmojiPackInstall"("userId", "installedAt" DESC);

-- RLS.
-- EmojiPack is publicly readable (it's a global catalog).
ALTER TABLE "EmojiPack" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "EmojiPack select" ON "EmojiPack";
CREATE POLICY "EmojiPack select" ON "EmojiPack"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "EmojiPack insert" ON "EmojiPack";
CREATE POLICY "EmojiPack insert" ON "EmojiPack"
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "EmojiPack update" ON "EmojiPack";
CREATE POLICY "EmojiPack update" ON "EmojiPack"
  FOR UPDATE TO authenticated USING (true);

ALTER TABLE "EmojiPackItem" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "EmojiPackItem select" ON "EmojiPackItem";
CREATE POLICY "EmojiPackItem select" ON "EmojiPackItem"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "EmojiPackItem insert" ON "EmojiPackItem";
CREATE POLICY "EmojiPackItem insert" ON "EmojiPackItem"
  FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE "UserEmojiPackInstall" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "UserEmojiPackInstall select own" ON "UserEmojiPackInstall";
CREATE POLICY "UserEmojiPackInstall select own" ON "UserEmojiPackInstall"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserEmojiPackInstall insert own" ON "UserEmojiPackInstall";
CREATE POLICY "UserEmojiPackInstall insert own" ON "UserEmojiPackInstall"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserEmojiPackInstall delete own" ON "UserEmojiPackInstall";
CREATE POLICY "UserEmojiPackInstall delete own" ON "UserEmojiPackInstall"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Realtime on UserEmojiPackInstall so installs/uninstalls sync across devices.
ALTER TABLE "UserEmojiPackInstall" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'UserEmojiPackInstall'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "UserEmojiPackInstall";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_install_emoji_pack — idempotent install
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_install_emoji_pack(p_pack_id text)
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
  IF NOT EXISTS (SELECT 1 FROM "EmojiPack" WHERE id = p_pack_id) THEN
    RETURN json_build_object('success', false, 'error', 'pack_not_found');
  END IF;

  INSERT INTO "UserEmojiPackInstall" ("id", "userId", "packId", "installedAt")
  VALUES ('uepi_' || p_pack_id || '_' || v_user_id, v_user_id, p_pack_id, now())
  ON CONFLICT ("userId", "packId") DO NOTHING;

  RETURN json_build_object('success', true, 'packId', p_pack_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_install_emoji_pack(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_uninstall_emoji_pack
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_uninstall_emoji_pack(p_pack_id text)
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
  DELETE FROM "UserEmojiPackInstall"
    WHERE "userId" = v_user_id AND "packId" = p_pack_id;
  RETURN json_build_object('success', true, 'packId', p_pack_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_uninstall_emoji_pack(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_installed_emoji_packs — returns the caller's installed packs +
-- their items in a single query (the Flutter picker loads everything
-- at once).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_installed_emoji_packs()
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
      'id', p."id",
      'name', p."name",
      'thumbUrl', p."thumbUrl",
      'isAnimated', p."isAnimated",
      'isOfficial', p."isOfficial",
      'publisherName', p."publisherName",
      'installedAt', to_char(i."installedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'items', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', it."id",
          'packId', it."packId",
          'emojiName', it."emojiName",
          'imageUrl', it."imageUrl",
          'lottieUrl', it."lottieUrl",
          'keywords', it."keywords"
        ) ORDER BY it."createdAt" ASC)
        FROM "EmojiPackItem" it
        WHERE it."packId" = p."id"
      ), '[]'::jsonb)
    ) ORDER BY i."installedAt" DESC)
    FROM "EmojiPack" p
    JOIN "UserEmojiPackInstall" i ON i."packId" = p."id"
    WHERE i."userId" = v_user_id
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_installed_emoji_packs() TO authenticated;

-- Verification
SELECT 'EmojiPack' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'EmojiPack') AS exists;
SELECT 'EmojiPackItem' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'EmojiPackItem') AS exists;
SELECT 'UserEmojiPackInstall' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserEmojiPackInstall') AS exists;
SELECT 'fn_install_emoji_pack' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_install_emoji_pack') AS exists;
SELECT 'fn_uninstall_emoji_pack' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_uninstall_emoji_pack') AS exists;
SELECT 'fn_get_installed_emoji_packs' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_installed_emoji_packs') AS exists;
