-- =============================================================================
-- Daxelo-Kinrel — game_participants central cross-game registry
-- =============================================================================
-- Foundation table for: Recent Players (section 3), Leaderboards (section 5),
-- and Badges (section 6). Single source of truth for "who played what with
-- whom" across all 14 game tables.
--
-- Populated by an AFTER INSERT trigger on each {game}_players table (and by
-- the lobby join flow for inline-player games like checkers/chess/carrom/
-- tictactoe where there's no separate _players table).
-- =============================================================================

CREATE TABLE IF NOT EXISTS "game_participants" (
  "id"            text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameTable"     text NOT NULL,   -- e.g. 'bingo_games', 'ludo_games', 'redlight_rounds'
  "gameId"        text NOT NULL,   -- FK to the specific game row (not enforced via FK since 14 different tables)
  "familyId"      text NOT NULL,
  "userId"        text NOT NULL,
  "userName"      text,            -- denormalized for fast recent-players display
  "role"          text NOT NULL DEFAULT 'player',  -- player | host | spectator
  "result"        text,            -- win | loss | draw (nullable until game completes)
  "joinedAt"      timestamptz NOT NULL DEFAULT now(),
  "leftAt"        timestamptz,
  "completedAt"   timestamptz,    -- set when the game ends, used for badge/streak calc
  "createdAt"     timestamptz NOT NULL DEFAULT now()
);

-- Indexes for the hot paths:
-- 1. Recent players lookup: WHERE userId = ? AND familyId = ? ORDER BY joinedAt DESC
CREATE INDEX IF NOT EXISTS idx_game_participants_user_joined
  ON "game_participants" ("userId", "familyId", "joinedAt" DESC);

-- 2. Leaderboard lookup: WHERE familyId = ? [AND gameTable = ?] GROUP BY userId
CREATE INDEX IF NOT EXISTS idx_game_participants_family_game
  ON "game_participants" ("familyId", "gameTable");

-- 3. Per-game lookup: WHERE gameTable = ? AND gameId = ?
CREATE INDEX IF NOT EXISTS idx_game_participants_game
  ON "game_participants" ("gameTable", "gameId");

-- 4. Badge "played-5-games-week" lookup: WHERE userId = ? AND joinedAt >= now() - interval '7 days'
CREATE INDEX IF NOT EXISTS idx_game_participants_user_recent
  ON "game_participants" ("userId", "joinedAt" DESC);

-- Unique constraint: one participant row per (gameTable, gameId, userId)
-- Prevents double-counting if a trigger fires twice.
CREATE UNIQUE INDEX IF NOT EXISTS uq_game_participants_game_user
  ON "game_participants" ("gameTable", "gameId", "userId");

-- Enable RLS — family members can read their family's participants; users
-- can insert/update their own rows.
ALTER TABLE "game_participants" ENABLE ROW LEVEL SECURITY;

-- Helper: is the caller a member of the given family?
-- Note: this function may already exist from the chat migration with the
-- same signature. CREATE OR REPLACE works as long as the param NAME is
-- compatible. If the existing function uses a different param name, the
-- caller (RLS policies) doesn't care — they call by position, not by name.
-- We use a param name that doesn't conflict.
DO $_outer_$
BEGIN
  BEGIN
    CREATE OR REPLACE FUNCTION fn_user_is_family_member(p_family_id text)
    RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
      SELECT EXISTS (
        SELECT 1 FROM "FamilyMember" fm
        WHERE fm."familyId" = p_family_id
          AND fm."userId" = auth.uid()::text
      );
    $$;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'fn_user_is_family_member already exists with different param name — keeping existing definition';
  END;
END $_outer_$;

-- SELECT: family members can read their own family's participants
CREATE POLICY "game_participants_select_family_members"
  ON "game_participants" FOR SELECT
  TO authenticated
  USING (fn_user_is_family_member("familyId"));

-- INSERT: any authenticated user can insert their own participant row
CREATE POLICY "game_participants_insert_self"
  ON "game_participants" FOR INSERT
  TO authenticated
  WITH CHECK ("userId" = auth.uid()::text);

-- UPDATE: users can update their own row (e.g. set result/leftAt)
CREATE POLICY "game_participants_update_self"
  ON "game_participants" FOR UPDATE
  TO authenticated
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- =============================================================================
-- RPC: fn_get_recent_playmates
-- =============================================================================
-- Returns the 5 most recent DISTINCT co-players the current user has played
-- with in the given family, across all game tables. Used by the invite sheet
-- "Recently Played With" section.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_recent_playmates(
  p_user_id text,
  p_family_id text,
  p_limit int DEFAULT 5,
  p_days_back int DEFAULT 30
)
RETURNS TABLE(
  "userId" text,
  "userName" text,
  "lastPlayedAt" timestamptz,
  "gamesPlayed" bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    other."userId",
    MAX(other."userName") AS "userName",
    MAX(other."joinedAt") AS "lastPlayedAt",
    COUNT(*) AS "gamesPlayed"
  FROM "game_participants" mine
  INNER JOIN "game_participants" other
    ON other."gameTable" = mine."gameTable"
    AND other."gameId" = mine."gameId"
    AND other."userId" <> p_user_id
  WHERE mine."userId" = p_user_id
    AND mine."familyId" = p_family_id
    AND mine."joinedAt" >= now() - (p_days_back || ' days')::interval
    AND other."familyId" = p_family_id
    AND other."role" = 'player'
  GROUP BY other."userId"
  ORDER BY "lastPlayedAt" DESC
  LIMIT LEAST(p_limit, 20);
$$;

GRANT EXECUTE ON FUNCTION fn_get_recent_playmates(text, text, int, int) TO authenticated;

-- =============================================================================
-- RPC: fn_get_family_leaderboard
-- =============================================================================
-- Per-family leaderboard, optionally filtered to one game type.
-- Returns per-user win/loss/draw counts and win rate.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_family_leaderboard(
  p_family_id text,
  p_game_table text DEFAULT NULL
)
RETURNS TABLE(
  "userId" text,
  "userName" text,
  "wins" bigint,
  "losses" bigint,
  "draws" bigint,
  "gamesPlayed" bigint,
  "winRate" numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    "userId",
    MAX("userName") AS "userName",
    COUNT(*) FILTER (WHERE "result" = 'win') AS "wins",
    COUNT(*) FILTER (WHERE "result" = 'loss') AS "losses",
    COUNT(*) FILTER (WHERE "result" = 'draw') AS "draws",
    COUNT(*) FILTER (WHERE "result" IS NOT NULL) AS "gamesPlayed",
    CASE
      WHEN COUNT(*) FILTER (WHERE "result" IS NOT NULL) = 0 THEN 0
      ELSE ROUND(
        COUNT(*) FILTER (WHERE "result" = 'win')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE "result" IS NOT NULL), 0)::numeric,
        3
      )
    END AS "winRate"
  FROM "game_participants"
  WHERE "familyId" = p_family_id
    AND "role" = 'player'
    AND (p_game_table IS NULL OR "gameTable" = p_game_table)
    AND "result" IS NOT NULL
  GROUP BY "userId"
  ORDER BY "wins" DESC, "winRate" DESC, "gamesPlayed" DESC;
$$;

GRANT EXECUTE ON FUNCTION fn_get_family_leaderboard(text, text) TO authenticated;

-- =============================================================================
-- RPC: fn_record_game_participant
-- =============================================================================
-- Convenience RPC called from Flutter when a player joins any game's lobby.
-- Idempotent — uses ON CONFLICT to skip if already recorded.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_record_game_participant(
  p_game_table text,
  p_game_id text,
  p_family_id text,
  p_user_id text,
  p_user_name text DEFAULT NULL,
  p_role text DEFAULT 'player'
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO "game_participants"
    ("gameTable", "gameId", "familyId", "userId", "userName", "role")
  VALUES
    (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, p_role)
  ON CONFLICT ("gameTable", "gameId", "userId") DO NOTHING;
$$;

GRANT EXECUTE ON FUNCTION fn_record_game_participant(text, text, text, text, text, text) TO authenticated;

-- =============================================================================
-- RPC: fn_set_game_result
-- =============================================================================
-- Called when a game completes to set each participant's result
-- (win/loss/draw). The Flutter board screen calls this once per participant.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_set_game_result(
  p_game_table text,
  p_game_id text,
  p_user_id text,
  p_result text,
  p_completed_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE "game_participants"
  SET "result" = p_result,
      "completedAt" = p_completed_at,
      "leftAt" = COALESCE("leftAt", p_completed_at)
  WHERE "gameTable" = p_game_table
    AND "gameId" = p_game_id
    AND "userId" = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION fn_set_game_result(text, text, text, text, timestamptz) TO authenticated;
