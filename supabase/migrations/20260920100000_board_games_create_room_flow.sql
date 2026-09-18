-- =============================================================================
-- Daxelo-Kinrel — Create Room flow for the 4 board games
-- =============================================================================
-- Chess, Checkers, Carrom and Tic-Tac-Toe previously used a "challenge"
-- flow: the creator had to pick a specific opponent BEFORE the game row
-- was inserted (playerTwo/playerBlack/playerO NOT NULL at creation).
--
-- The new flow matches every other multiplayer game in the app:
--   1. User taps "Create Room" → the room is created immediately with
--      ONLY the host attached (status 'waiting').
--   2. The host lands in the shared lobby and invites family members
--      (or shares the room code).
--   3. The first family member to join takes the opponent slot
--      automatically; both players ready up; the host starts the match.
--
-- Schema changes needed:
--   • The 4 tables get the same host columns the Pattern B tables have
--     (hostUserId / hostUserName) — used for host detection, host-leave
--     room close and the invite surfaces.
--   • The opponent columns become NULLABLE (a waiting room has no
--     opponent yet): chess.playerBlackId, checkers.playerTwoId,
--     tictactoe.playerOId, carrom.playerTwoId.
--   • Backfill hostUserId from the creator's slot for existing rows so
--     in-progress games keep working.
--
-- RPC changes:
--   • fn_cancel_waiting_room: add the 4 board tables (they now have
--     hostUserId) AND tugofwar_games / memorymatch_games (which were
--     missing from the allowlist — their host-close path silently
--     no-op'd). Host + waiting → the room row is hard-deleted for
--     everyone, exactly like the other games.
-- =============================================================================

-- ── 1. Host columns on the 4 board-game tables ──────────────────────────

ALTER TABLE "chess_games"      ADD COLUMN IF NOT EXISTS "hostUserId" TEXT;
ALTER TABLE "chess_games"      ADD COLUMN IF NOT EXISTS "hostUserName" TEXT;
ALTER TABLE "checkers_games"   ADD COLUMN IF NOT EXISTS "hostUserId" TEXT;
ALTER TABLE "checkers_games"   ADD COLUMN IF NOT EXISTS "hostUserName" TEXT;
ALTER TABLE "carrom_games"     ADD COLUMN IF NOT EXISTS "hostUserId" TEXT;
ALTER TABLE "carrom_games"     ADD COLUMN IF NOT EXISTS "hostUserName" TEXT;
ALTER TABLE "tictactoe_games"  ADD COLUMN IF NOT EXISTS "hostUserId" TEXT;
ALTER TABLE "tictactoe_games"  ADD COLUMN IF NOT EXISTS "hostUserName" TEXT;

-- ── 2. Opponent slots become nullable (waiting rooms have no opponent) ──
-- DROP NOT NULL is idempotent: re-running on an already-nullable column
-- is a silent no-op.

ALTER TABLE "chess_games"      ALTER COLUMN "playerBlackId" DROP NOT NULL;
ALTER TABLE "checkers_games"   ALTER COLUMN "playerTwoId"   DROP NOT NULL;
ALTER TABLE "carrom_games"     ALTER COLUMN "playerTwoId"   DROP NOT NULL;
ALTER TABLE "tictactoe_games"  ALTER COLUMN "playerOId"     DROP NOT NULL;

-- ── 3. Backfill hostUserId for existing rows ────────────────────────────
-- The creator of a challenge game is always the first player
-- (White / One / X). Rows created by the new Create Room flow already
-- carry hostUserId, so the COALESCE keeps them untouched.

UPDATE "chess_games"      SET "hostUserId"   = COALESCE("hostUserId", "playerWhiteId"),
                              "hostUserName" = COALESCE("hostUserName", "playerWhiteName");
UPDATE "checkers_games"   SET "hostUserId"   = COALESCE("hostUserId", "playerOneId"),
                              "hostUserName" = COALESCE("hostUserName", "playerOneName");
UPDATE "carrom_games"     SET "hostUserId"   = COALESCE("hostUserId", "playerOneId"),
                              "hostUserName" = COALESCE("hostUserName", "playerOneName");
UPDATE "tictactoe_games"  SET "hostUserId"   = COALESCE("hostUserId", "playerXId"),
                              "hostUserName" = COALESCE("hostUserName", "playerXName");

-- ── 4. fn_cancel_waiting_room — extended allowlist ──────────────────────
-- Adds: chess_games, checkers_games, carrom_games, tictactoe_games
-- (host columns now exist) + tugofwar_games, memorymatch_games
-- (were missing — host-close silently no-op'd for both).
-- Host + pre-game status → delete invites, delete the room row (cascade
-- to moves/rounds/turns + game_participants via FK/ON DELETE).

CREATE OR REPLACE FUNCTION public.fn_cancel_waiting_room(
    p_game_table text,
    p_game_id text,
    p_user_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_host text;
    v_status text;
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'checkers_games', 'carrom_games', 'tictactoe_games',
        'tugofwar_games', 'memorymatch_games'
    ) THEN
        RETURN;
    END IF;

    EXECUTE format(
        'SELECT "hostUserId", "status" FROM public.%I WHERE "id" = $1;',
        p_game_table
    ) INTO v_host, v_status USING p_game_id;

    IF v_host IS NULL OR v_status IS NULL THEN
        RETURN;
    END IF;

    IF v_host = p_user_id AND public.fn_is_pre_game_status(v_status) THEN
        DELETE FROM public.game_invites WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;
        DELETE FROM public.game_participants WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;
        DELETE FROM public.game_spectators WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;
        EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', p_game_table) USING p_game_id;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_cancel_waiting_room(text, text, text) TO authenticated;

-- ── 5. Room columns for tugofwar / memorymatch hostUserId backfill ──────
-- Both tables were created with hostUserId already; nothing to do here.
-- (Kept as a comment so the migration is self-documenting.)
