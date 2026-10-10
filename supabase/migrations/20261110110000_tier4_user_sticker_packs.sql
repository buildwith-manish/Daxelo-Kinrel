-- =============================================================================
-- Daxelo Kinrel — Tier 4 Features 4.4 + 4.5: Sticker packs from photos + Animated stickers
-- =============================================================================
-- Lets a user create custom sticker packs from their own photos. Each pack
-- can contain a mix of static (PNG/WebP) and animated (Lottie JSON/TGS)
-- stickers. Packs sync across the user's devices via Supabase Realtime.
--
-- Schema:
--   • UserStickerPack  — id, ownerId, name, thumbUrl, isAnimated, createdAt
--   • UserStickerItem  — id, packId (FK CASCADE), stickerName, imageUrl,
--     isAnimated, lottieUrl (nullable, for animated stickers), emoji
--     (the shortcut emoji that triggers this sticker in the picker),
--     createdAt.
--   • RLS: only the owner can SELECT/UPDATE/DELETE their packs + items.
--   • Realtime publication on UserStickerPack + UserStickerItem so the
--     user's other devices see new packs/items live.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "UserStickerPack" (
  "id"          text PRIMARY KEY,
  "ownerId"     text NOT NULL,
  "name"        text NOT NULL,
  "thumbUrl"    text,
  "isAnimated"  boolean NOT NULL DEFAULT false,   -- true if the pack is all-animated
  "isDefault"   boolean NOT NULL DEFAULT false,    -- true for the "My Stickers" auto-pack
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  "updatedAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "UserStickerPack_owner_idx" ON "UserStickerPack"("ownerId", "createdAt" DESC);
CREATE UNIQUE INDEX IF NOT EXISTS "UserStickerPack_owner_default_uniq"
  ON "UserStickerPack"("ownerId") WHERE "isDefault" = true;

CREATE TABLE IF NOT EXISTS "UserStickerItem" (
  "id"          text PRIMARY KEY,
  "packId"      text NOT NULL REFERENCES "UserStickerPack"(id) ON DELETE CASCADE,
  "stickerName" text NOT NULL,                     -- admin-facing label like "Diwali diya"
  "imageUrl"    text NOT NULL,                     -- static PNG/WebP URL OR the Lottie thumbnail
  "isAnimated"  boolean NOT NULL DEFAULT false,
  "lottieUrl"   text,                              -- when isAnimated=true, the Lottie JSON URL
  "emoji"       text,                              -- optional shortcut emoji (e.g. "🪔")
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "UserStickerItem_pack_idx"  ON "UserStickerItem"("packId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "UserStickerItem_owner_idx" ON "UserStickerItem"("emoji") WHERE "emoji" IS NOT NULL;

ALTER TABLE "UserStickerPack" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "UserStickerPack select own" ON "UserStickerPack";
CREATE POLICY "UserStickerPack select own" ON "UserStickerPack"
  FOR SELECT TO authenticated USING ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserStickerPack insert own" ON "UserStickerPack";
CREATE POLICY "UserStickerPack insert own" ON "UserStickerPack"
  FOR INSERT TO authenticated WITH CHECK ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserStickerPack update own" ON "UserStickerPack";
CREATE POLICY "UserStickerPack update own" ON "UserStickerPack"
  FOR UPDATE TO authenticated USING ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserStickerPack delete own" ON "UserStickerPack";
CREATE POLICY "UserStickerPack delete own" ON "UserStickerPack"
  FOR DELETE TO authenticated USING ("ownerId" = auth.uid()::text);

-- UserStickerItem: RLS via the parent pack's ownerId (subquery).
ALTER TABLE "UserStickerItem" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "UserStickerItem select owner" ON "UserStickerItem";
CREATE POLICY "UserStickerItem select owner" ON "UserStickerItem"
  FOR SELECT TO authenticated USING (
    "packId" IN (SELECT id FROM "UserStickerPack" WHERE "ownerId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "UserStickerItem insert owner" ON "UserStickerItem";
CREATE POLICY "UserStickerItem insert owner" ON "UserStickerItem"
  FOR INSERT TO authenticated WITH CHECK (
    "packId" IN (SELECT id FROM "UserStickerPack" WHERE "ownerId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "UserStickerItem delete owner" ON "UserStickerItem";
CREATE POLICY "UserStickerItem delete owner" ON "UserStickerItem"
  FOR DELETE TO authenticated USING (
    "packId" IN (SELECT id FROM "UserStickerPack" WHERE "ownerId" = auth.uid()::text)
  );

-- Realtime: the user's other devices see pack + item changes live.
ALTER TABLE "UserStickerPack" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'UserStickerPack'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "UserStickerPack";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

ALTER TABLE "UserStickerItem" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'UserStickerItem'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "UserStickerItem";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_my_sticker_packs — returns all of the caller's packs + items
-- joined in a single query (the Flutter picker loads everything at once
-- on first open). Returns JSON: [{...pack, items: [...]}].
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_my_sticker_packs()
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
      'ownerId', p."ownerId",
      'name', p."name",
      'thumbUrl', p."thumbUrl",
      'isAnimated', p."isAnimated",
      'isDefault', p."isDefault",
      'createdAt', to_char(p."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'items', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', i."id",
          'packId', i."packId",
          'stickerName', i."stickerName",
          'imageUrl', i."imageUrl",
          'isAnimated', i."isAnimated",
          'lottieUrl', i."lottieUrl",
          'emoji', i."emoji",
          'createdAt', to_char(i."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        ) ORDER BY i."createdAt" ASC)
        FROM "UserStickerItem" i
        WHERE i."packId" = p."id"
      ), '[]'::jsonb)
    ) ORDER BY p."isDefault" DESC, p."createdAt" ASC)
    FROM "UserStickerPack" p
    WHERE p."ownerId" = v_user_id
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_my_sticker_packs() TO authenticated;

-- Verification
SELECT 'UserStickerPack' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserStickerPack') AS exists;
SELECT 'UserStickerItem' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserStickerItem') AS exists;
SELECT 'fn_get_my_sticker_packs' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_my_sticker_packs') AS exists;
