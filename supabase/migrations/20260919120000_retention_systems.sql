-- =============================================================================
-- 20260919120000_retention_systems.sql
--
-- Four Roblox-inspired retention systems for the Kinrel Games module:
--   1. Shared Economy — "Family Coins" currency across all games
--   2. Player-Created Content — family-authored questions/cards
--   3. Live Social Presence — (no new tables; uses Supabase Realtime)
--   4. Seasonal/Event Reskins — periodic fresh-coat for the Games tab
--
-- All systems tie into existing infrastructure: game categories, K-Graph
-- relationship data, Family Moments feed, existing games, and the
-- match-completion/challenge-completion code paths.
-- =============================================================================

-- =============================================================================
-- SYSTEM 1: SHARED ECONOMY — Family Coins
-- =============================================================================

CREATE TABLE IF NOT EXISTS "family_coin_ledger" (
  id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"        TEXT NOT NULL,
  "familyId"      TEXT NOT NULL,
  amount          INTEGER NOT NULL,  -- positive = earned, negative = spent
  reason          TEXT NOT NULL,     -- match_complete | win_streak | challenge_complete | cup_placement | new_game_bonus | reward_redeem
  "referenceId"   TEXT,              -- optional: game_id, challenge_slug, reward_id
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fcl_user_family ON "family_coin_ledger" ("userId", "familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_fcl_family ON "family_coin_ledger" ("familyId", "createdAt" DESC);

ALTER TABLE "family_coin_ledger" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "family_coin_ledger_select_family" ON "family_coin_ledger"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

CREATE POLICY "family_coin_ledger_insert_self" ON "family_coin_ledger"
  FOR INSERT TO authenticated
  WITH CHECK ("userId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));

-- Coin balances — a simple table updated by trigger for fast reads.
CREATE TABLE IF NOT EXISTS "family_coin_balances" (
  "userId"        TEXT NOT NULL,
  "familyId"      TEXT NOT NULL,
  balance         INTEGER NOT NULL DEFAULT 0,
  "totalEarned"   INTEGER NOT NULL DEFAULT 0,
  "totalSpent"    INTEGER NOT NULL DEFAULT 0,
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("userId", "familyId")
);

ALTER TABLE "family_coin_balances" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "family_coin_balances_select_family" ON "family_coin_balances"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

-- Trigger: auto-update balance on ledger insert
CREATE OR REPLACE FUNCTION public.fn__update_coin_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO "family_coin_balances" ("userId", "familyId", balance, "totalEarned", "totalSpent", "updatedAt")
  VALUES (NEW."userId", NEW."familyId", NEW.amount,
    CASE WHEN NEW.amount > 0 THEN NEW.amount ELSE 0 END,
    CASE WHEN NEW.amount < 0 THEN ABS(NEW.amount) ELSE 0 END,
    now())
  ON CONFLICT ("userId", "familyId") DO UPDATE SET
    balance = "family_coin_balances".balance + NEW.amount,
    "totalEarned" = "family_coin_balances"."totalEarned" + CASE WHEN NEW.amount > 0 THEN NEW.amount ELSE 0 END,
    "totalSpent" = "family_coin_balances"."totalSpent" + CASE WHEN NEW.amount < 0 THEN ABS(NEW.amount) ELSE 0 END,
    "updatedAt" = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_coin_balance ON "family_coin_ledger";
CREATE TRIGGER trg_update_coin_balance
  AFTER INSERT ON "family_coin_ledger"
  FOR EACH ROW
  EXECUTE FUNCTION public.fn__update_coin_balance();

-- Unlockable rewards catalog
CREATE TABLE IF NOT EXISTS "unlockable_rewards" (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  type            TEXT NOT NULL,  -- board_skin | reaction_pack | trophy_frame | naming_right
  category        TEXT NOT NULL DEFAULT 'general',
  cost            INTEGER NOT NULL DEFAULT 100,
  "iconEmoji"     TEXT NOT NULL DEFAULT '🎁',
  "isActive"      BOOLEAN NOT NULL DEFAULT true,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE "unlockable_rewards" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "unlockable_rewards_select_all" ON "unlockable_rewards"
  FOR SELECT TO authenticated USING (true);

-- User unlocked rewards
CREATE TABLE IF NOT EXISTS "user_unlocked_rewards" (
  id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"        TEXT NOT NULL,
  "familyId"      TEXT NOT NULL,
  "rewardId"      TEXT NOT NULL REFERENCES "unlockable_rewards"(id),
  "unlockedAt"    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("userId", "rewardId")
);

ALTER TABLE "user_unlocked_rewards" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_unlocked_rewards_select_family" ON "user_unlocked_rewards"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

CREATE POLICY "user_unlocked_rewards_insert_self" ON "user_unlocked_rewards"
  FOR INSERT TO authenticated
  WITH CHECK ("userId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));

-- RPC: award_coins
CREATE OR REPLACE FUNCTION public.award_coins(
  p_user_id text,
  p_family_id text,
  p_amount int,
  p_reason text,
  p_reference_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Apply seasonal coin multiplier if active (System 4 integration)
  DECLARE
    v_multiplier float := 1.0;
    v_final_amount int;
  BEGIN
    SELECT COALESCE(MAX("coinMultiplier"), 1.0) INTO v_multiplier
    FROM "seasonal_themes"
    WHERE "isActive" = true
      AND now() >= "startDate"
      AND now() <= "endDate";

    v_final_amount := GREATEST(1, ROUND(p_amount * v_multiplier))::int;

    INSERT INTO "family_coin_ledger" ("userId", "familyId", amount, reason, "referenceId")
    VALUES (p_user_id, p_family_id, v_final_amount, p_reason, p_reference_id);

    RETURN jsonb_build_object('ok', true, 'awarded', v_final_amount, 'multiplier', v_multiplier);
  END;
END;
$$;
GRANT EXECUTE ON FUNCTION public.award_coins(text, text, int, text, text) TO authenticated;

-- RPC: redeem_reward
CREATE OR REPLACE FUNCTION public.redeem_reward(
  p_user_id text,
  p_family_id text,
  p_reward_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reward record;
  v_balance int;
BEGIN
  SELECT * INTO v_reward FROM "unlockable_rewards" WHERE id = p_reward_id AND "isActive" = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reward_not_found');
  END IF;

  SELECT COALESCE(balance, 0) INTO v_balance
  FROM "family_coin_balances"
  WHERE "userId" = p_user_id AND "familyId" = p_family_id;

  IF v_balance < v_reward.cost THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'insufficient_balance', 'balance', v_balance, 'cost', v_reward.cost);
  END IF;

  -- Check if already unlocked
  IF EXISTS (SELECT 1 FROM "user_unlocked_rewards" WHERE "userId" = p_user_id AND "rewardId" = p_reward_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_unlocked');
  END IF;

  -- Deduct coins
  INSERT INTO "family_coin_ledger" ("userId", "familyId", amount, reason, "referenceId")
  VALUES (p_user_id, p_family_id, -v_reward.cost, 'reward_redeem', p_reward_id);

  -- Grant reward
  INSERT INTO "user_unlocked_rewards" ("userId", "familyId", "rewardId")
  VALUES (p_user_id, p_family_id, p_reward_id);

  RETURN jsonb_build_object('ok', true, 'rewardId', p_reward_id, 'remainingBalance', v_balance - v_reward.cost);
END;
$$;
GRANT EXECUTE ON FUNCTION public.redeem_reward(text, text, text) TO authenticated;

-- RPC: get_coin_balance
CREATE OR REPLACE FUNCTION public.get_coin_balance(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'balance', COALESCE(b.balance, 0),
    'totalEarned', COALESCE(b."totalEarned", 0),
    'totalSpent', COALESCE(b."totalSpent", 0),
    'familyTreasury', COALESCE((
      SELECT SUM(b2.balance) FROM "family_coin_balances" b2
      WHERE b2."familyId" = p_family_id
    ), 0)
  )
  FROM "family_coin_balances" b
  WHERE b."userId" = p_user_id AND b."familyId" = p_family_id;
$$;
GRANT EXECUTE ON FUNCTION public.get_coin_balance(text, text) TO authenticated;

-- Seed initial rewards
INSERT INTO "unlockable_rewards" ("id", "name", "description", "type", "category", "cost", "iconEmoji") VALUES
  ('reward-festive-ludo', 'Festive Ludo Board', 'Diwali-themed Ludo board skin', 'board_skin', 'board_skins', 200, '🎲'),
  ('reward-wood-chess', 'Wood-Texture Chess Set', 'Classic wood-grain chess board', 'board_skin', 'board_skins', 150, '♟️'),
  ('reward-neon-ttt', 'Neon Tic-Tac-Toe', 'Glowing neon grid for Tic-Tac-Toe', 'board_skin', 'board_skins', 100, '✨'),
  ('reward-reaction-pack-1', 'Festive Reaction Pack', '🪔🎉🤗🎊 emoji reactions for Family Moments', 'reaction_pack', 'reaction_packs', 120, '🪔'),
  ('reward-reaction-pack-2', 'Animal Reaction Pack', '🐶🐱🦁🦊 emoji reactions for Family Moments', 'reaction_pack', 'reaction_packs', 120, '🐶'),
  ('reward-trophy-frame-gold', 'Gold Trophy Frame', 'Golden frame for your badge display', 'trophy_frame', 'trophy_frames', 300, '🖼️'),
  ('reward-naming-right-season', 'Season Naming Right', 'Name the current Family Cup season — shown to your whole family!', 'naming_right', 'naming_rights', 500, '✏️')
ON CONFLICT ("id") DO NOTHING;

-- =============================================================================
-- SYSTEM 2: PLAYER-CREATED CONTENT — Family-authored questions/cards
-- =============================================================================

CREATE TABLE IF NOT EXISTS "family_custom_content" (
  id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"      TEXT NOT NULL,
  "gameType"      TEXT NOT NULL,  -- 'twotruths' | 'truthordare'
  "contentJson"   JSONB NOT NULL, -- game-specific structure
  "createdBy"     TEXT NOT NULL,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
  "isActive"      BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_fcc_family_game ON "family_custom_content" ("familyId", "gameType", "isActive");

ALTER TABLE "family_custom_content" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "family_custom_content_select_family" ON "family_custom_content"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

CREATE POLICY "family_custom_content_insert_family" ON "family_custom_content"
  FOR INSERT TO authenticated
  WITH CHECK (public.fn_user_is_family_member("familyId") AND "createdBy" = auth.uid()::text);

CREATE POLICY "family_custom_content_update_owner" ON "family_custom_content"
  FOR UPDATE TO authenticated
  USING ("createdBy" = auth.uid()::text);

CREATE POLICY "family_custom_content_delete_owner" ON "family_custom_content"
  FOR DELETE TO authenticated
  USING ("createdBy" = auth.uid()::text);

-- RPC: get_game_content — merges default pool + active custom content
CREATE OR REPLACE FUNCTION public.get_game_content(
  p_family_id text,
  p_game_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_custom jsonb;
  v_result jsonb;
BEGIN
  -- Fetch active custom content for this family + game type
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY random()), '[]'::jsonb) INTO v_custom
  FROM (
    SELECT
      c."contentJson",
      true AS "isCustom",
      c.id AS "contentId"
    FROM "family_custom_content" c
    WHERE c."familyId" = p_family_id
      AND c."gameType" = p_game_type
      AND c."isActive" = true
  ) t;

  -- Return custom content; the Flutter layer merges with its own default pool.
  -- Custom entries are marked isCustom=true so the UI can show
  -- "Someone in your family wrote this..." attribution.
  RETURN jsonb_build_object('customContent', v_custom);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_game_content(text, text) TO authenticated;

-- =============================================================================
-- SYSTEM 3: LIVE SOCIAL PRESENCE
-- =============================================================================
-- No new tables needed — uses Supabase Realtime presence channels.
-- The existing "MemberPresence" table (used by fn_get_family_presence)
-- already tracks lastSeenAt + status. We add a helper RPC for the
-- "last online" fallback display.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_family_last_seen(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'userId', mp."userId",
      'userName', COALESCE(u."name", 'Family Member'),
      'status', mp."status",
      'lastSeenAt', mp."lastSeenAt",
      'isOnline', mp."lastSeenAt" > now() - interval '90 seconds' AND mp."status" IS NOT NULL AND mp."status" <> 'away'
    ) ORDER BY mp."lastSeenAt" DESC NULLS LAST)
    FROM "MemberPresence" mp
    LEFT JOIN "User" u ON u."id" = mp."userId"
    WHERE mp."familyId" = p_family_id
      AND mp."lastSeenAt" > now() - interval '24 hours'
    LIMIT 20
  ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_family_last_seen(text) TO authenticated;

-- =============================================================================
-- SYSTEM 4: SEASONAL/EVENT RESKINS
-- =============================================================================

CREATE TABLE IF NOT EXISTS "seasonal_themes" (
  id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name            TEXT NOT NULL,
  "startDate"     TIMESTAMPTZ NOT NULL,
  "endDate"       TIMESTAMPTZ NOT NULL,
  "accentColor"   TEXT NOT NULL DEFAULT '#E8612A',
  "bannerAssetUrl" TEXT,
  "coinMultiplier" FLOAT NOT NULL DEFAULT 1.0,
  "iconEmoji"     TEXT NOT NULL DEFAULT '🎉',
  "isActive"      BOOLEAN NOT NULL DEFAULT true,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE "seasonal_themes" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "seasonal_themes_select_all" ON "seasonal_themes"
  FOR SELECT TO authenticated USING (true);

-- RPC: get_active_seasonal_theme
CREATE OR REPLACE FUNCTION public.get_active_seasonal_theme()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  FROM (
    SELECT id, name, "startDate", "endDate", "accentColor",
           "bannerAssetUrl", "coinMultiplier", "iconEmoji"
    FROM "seasonal_themes"
    WHERE "isActive" = true
      AND now() >= "startDate"
      AND now() <= "endDate"
    ORDER BY "startDate" ASC
    LIMIT 1
  ) t;
$$;
GRANT EXECUTE ON FUNCTION public.get_active_seasonal_theme() TO authenticated;

-- Seed seasonal themes — Diwali, Holi, New Year, Birthday Month
INSERT INTO "seasonal_themes" ("id", "name", "startDate", "endDate", "accentColor", "coinMultiplier", "iconEmoji") VALUES
  ('theme-diwali-2026', 'Diwali Game Night', '2026-10-20T00:00:00Z', '2026-11-05T23:59:59Z', '#F59E0B', 1.5, '🪔'),
  ('theme-holi-2027', 'Holi Game Night', '2027-03-14T00:00:00Z', '2027-03-16T23:59:59Z', '#EC4899', 1.5, '🎨'),
  ('theme-newyear-2027', 'New Year Game Night', '2026-12-31T00:00:00Z', '2027-01-02T23:59:59Z', '#8B5CF6', 2.0, '🎊'),
  ('theme-birthday-month', 'Family Birthday Month', '2026-01-01T00:00:00Z', '2026-12-31T23:59:59Z', '#EF4444', 1.25, '🎂')
ON CONFLICT ("id") DO NOTHING;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE "family_coin_ledger" IS 'Shared economy ledger — every coin earn/spend across all games. Trigger-updates family_coin_balances.';
COMMENT ON TABLE "family_coin_balances" IS 'Per-user, per-family coin balance. Updated by trigger on family_coin_ledger.';
COMMENT ON TABLE "unlockable_rewards" IS 'Catalog of non-avatar rewards unlockable with Family Coins.';
COMMENT ON TABLE "user_unlocked_rewards" IS 'Rewards a user has unlocked via coin redemption.';
COMMENT ON TABLE "family_custom_content" IS 'Family-authored questions/cards for Two Truths and a Lie, Truth or Dare. Private to the owning family.';
COMMENT ON TABLE "seasonal_themes" IS 'Periodic visual/content reskins for the Games tab (Diwali, Holi, New Year, Birthday Month).';
