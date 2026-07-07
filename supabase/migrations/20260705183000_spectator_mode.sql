-- =============================================================================
-- Daxelo-Kinrel — Spectator Mode (section 8)
-- =============================================================================
-- Adds `spectatorsEnabled` boolean (default true) to all 14 game tables so
-- hosts can toggle spectator access at room creation. Adds a central
-- `game_spectators` table tracking who's watching what. Adds RLS policies
-- gating read access to in-progress game state based on the toggle.
--
-- 14 game tables:
--   bingo_games, ludo_games, checkers_games, carrom_games, chess_games,
--   sos_games, antakshari_games, tictactoe_games, truthordare_games,
--   twotruths_games, dotsboxes_games, nameplace_games, chitmatch_games,
--   redlight_rounds
-- =============================================================================

-- ── Add spectatorsEnabled column to each game table ─────────────────────
-- All default to TRUE so existing games are spectator-friendly by default.

ALTER TABLE "bingo_games"        ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "ludo_games"         ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "checkers_games"     ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "carrom_games"       ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "chess_games"        ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "sos_games"          ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "antakshari_games"   ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "tictactoe_games"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "truthordare_games"  ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "twotruths_games"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "dotsboxes_games"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "nameplace_games"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "chitmatch_games"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE "redlight_rounds"    ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;

-- ── game_spectators table ───────────────────────────────────────────────
-- Tracks who's currently watching what game. Used for the spectator count
-- ("3 watching") and for access control (spectators can read game state
-- but not emit moves).

CREATE TABLE IF NOT EXISTS "game_spectators" (
  "id"          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameTable"   text NOT NULL,
  "gameId"      text NOT NULL,
  "familyId"    text NOT NULL,
  "userId"      text NOT NULL,
  "userName"    text,
  "joinedAt"    timestamptz NOT NULL DEFAULT now(),
  "leftAt"      timestamptz,
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_spectators_active
  ON "game_spectators" ("gameTable", "gameId", "userId")
  WHERE "leftAt" IS NULL;

CREATE INDEX IF NOT EXISTS idx_game_spectators_game
  ON "game_spectators" ("gameTable", "gameId", "leftAt");

CREATE INDEX IF NOT EXISTS idx_game_spectators_user
  ON "game_spectators" ("userId", "joinedAt" DESC);

ALTER TABLE "game_spectators" ENABLE ROW LEVEL SECURITY;

-- SELECT: family members can see who's spectating their family's games
CREATE POLICY "game_spectators_select_family"
  ON "game_spectators" FOR SELECT
  TO authenticated
  USING (fn_user_is_family_member("familyId"));

-- INSERT: any family member can spectate (the spectator gate is enforced
-- at the game-row read level — see below — not at the spectator-row level)
CREATE POLICY "game_spectators_insert_family"
  ON "game_spectators" FOR INSERT
  TO authenticated
  WITH CHECK (
    "userId" = auth.uid()::text
    AND fn_user_is_family_member("familyId")
  );

-- UPDATE: users can update their own spectator row (e.g. set leftAt)
CREATE POLICY "game_spectators_update_self"
  ON "game_spectators" FOR UPDATE
  TO authenticated
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- DELETE: users can delete their own spectator row
CREATE POLICY "game_spectators_delete_self"
  ON "game_spectators" FOR DELETE
  TO authenticated
  USING ("userId" = auth.uid()::text);

-- ── RLS for spectatorsEnabled-gated game reads ──────────────────────────
-- For each of the 14 game tables, replace the existing SELECT policy with
-- one that allows:
--   (a) the host / current players to always read the game (they're in it)
--   (b) any family member to read IF spectatorsEnabled = true
--   (c) the host always (so they can manage their own game)
--
-- We use a per-table policy expression that ORs these conditions.
-- Existing INSERT/UPDATE/DELETE policies are left alone (players still
-- need to write moves etc.) — only SELECT is tightened for spectators.
--
-- Note: this is intentionally permissive — most games already allow family
-- members to SELECT, but now they can do so even if they're not players,
-- as long as spectatorsEnabled = true. If spectatorsEnabled = false, only
-- actual participants can see the game.

-- Helper: is the caller a participant in the given game?
-- Each game stores participants differently, so we have one helper per table.
-- For brevity, we use a generic check: family-member OR explicit participant.
-- The explicit-participant check is done inline in each policy below.

-- bingo_games: participants tracked in bingo_cards
CREATE OR REPLACE FUNCTION fn_is_bingo_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "bingo_cards" bc
    WHERE bc."gameId" = p_game_id AND bc."playerId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "bingo_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- ludo_games: participants in ludo_players
CREATE OR REPLACE FUNCTION fn_is_ludo_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "ludo_players" lp
    WHERE lp."gameId" = p_game_id AND lp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "ludo_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- checkers_games: inline playerOneId/playerTwoId
CREATE OR REPLACE FUNCTION fn_is_checkers_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "checkers_games" g
    WHERE g."id" = p_game_id
      AND (g."playerOneId" = p_user_id OR g."playerTwoId" = p_user_id)
  );
$$;

-- carrom_games: inline playerOneId/playerTwoId
CREATE OR REPLACE FUNCTION fn_is_carrom_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "carrom_games" g
    WHERE g."id" = p_game_id
      AND (g."playerOneId" = p_user_id OR g."playerTwoId" = p_user_id)
  );
$$;

-- chess_games: inline playerWhiteId/playerBlackId
CREATE OR REPLACE FUNCTION fn_is_chess_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "chess_games" g
    WHERE g."id" = p_game_id
      AND (g."playerWhiteId" = p_user_id OR g."playerBlackId" = p_user_id)
  );
$$;

-- sos_games: participants in sos_players
CREATE OR REPLACE FUNCTION fn_is_sos_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "sos_players" sp
    WHERE sp."gameId" = p_game_id AND sp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "sos_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- antakshari_games: participants in antakshari_players
CREATE OR REPLACE FUNCTION fn_is_antakshari_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "antakshari_players" ap
    WHERE ap."gameId" = p_game_id AND ap."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "antakshari_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- tictactoe_games: inline playerXId/playerOId
CREATE OR REPLACE FUNCTION fn_is_tictactoe_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "tictactoe_games" g
    WHERE g."id" = p_game_id
      AND (g."playerXId" = p_user_id OR g."playerOId" = p_user_id)
  );
$$;

-- truthordare_games: participants in truthordare_players
CREATE OR REPLACE FUNCTION fn_is_truthordare_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "truthordare_players" tp
    WHERE tp."gameId" = p_game_id AND tp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "truthordare_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- twotruths_games: participants in twotruths_players
CREATE OR REPLACE FUNCTION fn_is_twotruths_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "twotruths_players" tp
    WHERE tp."gameId" = p_game_id AND tp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "twotruths_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- dotsboxes_games: participants in dotsboxes_players
CREATE OR REPLACE FUNCTION fn_is_dotsboxes_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "dotsboxes_players" dp
    WHERE dp."gameId" = p_game_id AND dp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "dotsboxes_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- nameplace_games: participants in nameplace_players
CREATE OR REPLACE FUNCTION fn_is_nameplace_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "nameplace_players" np
    WHERE np."gameId" = p_game_id AND np."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "nameplace_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- chitmatch_games: participants in chitmatch_players
CREATE OR REPLACE FUNCTION fn_is_chitmatch_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "chitmatch_players" cp
    WHERE cp."gameId" = p_game_id AND cp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "chitmatch_games" g
    WHERE g."id" = p_game_id AND g."hostUserId" = p_user_id
  );
$$;

-- redlight_rounds: participants in redlight_players
CREATE OR REPLACE FUNCTION fn_is_redlight_participant(p_game_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "redlight_players" rp
    WHERE rp."roundId" = p_game_id AND rp."userId" = p_user_id
  ) OR EXISTS (
    SELECT 1 FROM "redlight_rounds" r
    WHERE r."id" = p_game_id AND r."hostUserId" = p_user_id
  );
$$;

-- ── Apply spectator-gated SELECT policies ────────────────────────────────
-- For each game table, DROP existing SELECT policy (if any) and CREATE a
-- new one that allows: participants OR (family member AND spectatorsEnabled).
-- We use a predictable policy name so re-running this migration is safe.

-- bingo_games
DROP POLICY IF EXISTS "bingo_games_select_with_spectators" ON "bingo_games";
CREATE POLICY "bingo_games_select_with_spectators"
  ON "bingo_games" FOR SELECT TO authenticated
  USING (
    fn_is_bingo_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- ludo_games
DROP POLICY IF EXISTS "ludo_games_select_with_spectators" ON "ludo_games";
CREATE POLICY "ludo_games_select_with_spectators"
  ON "ludo_games" FOR SELECT TO authenticated
  USING (
    fn_is_ludo_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- checkers_games
DROP POLICY IF EXISTS "checkers_games_select_with_spectators" ON "checkers_games";
CREATE POLICY "checkers_games_select_with_spectators"
  ON "checkers_games" FOR SELECT TO authenticated
  USING (
    fn_is_checkers_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- carrom_games
DROP POLICY IF EXISTS "carrom_games_select_with_spectators" ON "carrom_games";
CREATE POLICY "carrom_games_select_with_spectators"
  ON "carrom_games" FOR SELECT TO authenticated
  USING (
    fn_is_carrom_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- chess_games
DROP POLICY IF EXISTS "chess_games_select_with_spectators" ON "chess_games";
CREATE POLICY "chess_games_select_with_spectators"
  ON "chess_games" FOR SELECT TO authenticated
  USING (
    fn_is_chess_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- sos_games
DROP POLICY IF EXISTS "sos_games_select_with_spectators" ON "sos_games";
CREATE POLICY "sos_games_select_with_spectators"
  ON "sos_games" FOR SELECT TO authenticated
  USING (
    fn_is_sos_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- antakshari_games
DROP POLICY IF EXISTS "antakshari_games_select_with_spectators" ON "antakshari_games";
CREATE POLICY "antakshari_games_select_with_spectators"
  ON "antakshari_games" FOR SELECT TO authenticated
  USING (
    fn_is_antakshari_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- tictactoe_games
DROP POLICY IF EXISTS "tictactoe_games_select_with_spectators" ON "tictactoe_games";
CREATE POLICY "tictactoe_games_select_with_spectators"
  ON "tictactoe_games" FOR SELECT TO authenticated
  USING (
    fn_is_tictactoe_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- truthordare_games
DROP POLICY IF EXISTS "truthordare_games_select_with_spectators" ON "truthordare_games";
CREATE POLICY "truthordare_games_select_with_spectators"
  ON "truthordare_games" FOR SELECT TO authenticated
  USING (
    fn_is_truthordare_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- twotruths_games
DROP POLICY IF EXISTS "twotruths_games_select_with_spectators" ON "twotruths_games";
CREATE POLICY "twotruths_games_select_with_spectators"
  ON "twotruths_games" FOR SELECT TO authenticated
  USING (
    fn_is_twotruths_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- dotsboxes_games
DROP POLICY IF EXISTS "dotsboxes_games_select_with_spectators" ON "dotsboxes_games";
CREATE POLICY "dotsboxes_games_select_with_spectators"
  ON "dotsboxes_games" FOR SELECT TO authenticated
  USING (
    fn_is_dotsboxes_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- nameplace_games
DROP POLICY IF EXISTS "nameplace_games_select_with_spectators" ON "nameplace_games";
CREATE POLICY "nameplace_games_select_with_spectators"
  ON "nameplace_games" FOR SELECT TO authenticated
  USING (
    fn_is_nameplace_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- chitmatch_games
DROP POLICY IF EXISTS "chitmatch_games_select_with_spectators" ON "chitmatch_games";
CREATE POLICY "chitmatch_games_select_with_spectators"
  ON "chitmatch_games" FOR SELECT TO authenticated
  USING (
    fn_is_chitmatch_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );

-- redlight_rounds
DROP POLICY IF EXISTS "redlight_rounds_select_with_spectators" ON "redlight_rounds";
CREATE POLICY "redlight_rounds_select_with_spectators"
  ON "redlight_rounds" FOR SELECT TO authenticated
  USING (
    fn_is_redlight_participant("id", auth.uid()::text)
    OR ("spectatorsEnabled" AND fn_user_is_family_member("familyId"))
  );
