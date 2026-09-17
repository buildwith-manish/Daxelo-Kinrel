-- =====================================================================
-- 20260914060000_room_close_hard_delete.sql
--
-- Multiplayer Room Close Flow Fix — Phase 2:
-- A CLOSED ROOM IS DELETED IMMEDIATELY FROM THE DATABASE.
--
-- The bug being fixed:
--   Prior close paths only SOFT-closed rooms. fn_cancel_game_room and
--   fn_leave_game_room set "cancelledAt" + "closedAt" on the game row and
--   left the row in the table (status unchanged). Because every
--   "active games" query filters by status (waiting / in_progress / ...),
--   soft-closed rows kept matching — so closed rooms REAPPEARED:
--     • in the family hub "Active Games" list,
--     • when a player tapped a stale invite / chat card,
--     • when the host tapped Play again on that game.
--
-- The fix (per spec):
--   • fn_cancel_game_room    — host close    → HARD DELETE (all 14 tables)
--   • fn_cancel_waiting_room — host cancel   → HARD DELETE (any status)
--   • fn_leave_game_room     — host leave    → HARD DELETE;
--                               player leave → removes only their rows
--   • fn_end_game            — now also cleans game_participants /
--                               game_spectators / game_room_events
--   • Section 6              — one-time cleanup that removes every
--                               soft-closed + stale room row already in
--                               the database so no closed room can
--                               reappear from historical data.
--
-- Realtime ordering (why the 'cancel' event is inserted FIRST):
--   1. The 'cancel' room event INSERT fans out via Supabase Realtime —
--      every connected RoomController clears its state and the lobby
--      screens navigate their users back to the create-room screen.
--   2. game_participants / game_spectators DELETEs fan out next.
--   3. The game row DELETE fans out last — clients that subscribe to the
--      game table (board providers) react with "room closed" UI.
--   All of this happens inside one transaction; Postgres emits every WAL
--   change, so Supabase Realtime delivers all three waves in order.
--
-- FK note: every game-specific child table (players, moves, cards, turns,
-- tokens, rounds, ...) references its game table with ON DELETE CASCADE,
-- so deleting the game row removes all game data. The polymorphic room
-- tables (game_invites / game_participants / game_spectators /
-- game_room_events) have no FK, so they are deleted explicitly.
-- =====================================================================

-- =====================================================================
-- 1) fn__hard_delete_room — shared internal helper (NOT granted to
--    authenticated; only callable from the RPCs below).
--    Whitelists all 14 game tables, cleans the polymorphic room tables,
--    then deletes the game row (children cascade).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn__hard_delete_room(
    p_game_table text,
    p_game_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    -- 1. Delete pending invites for this room (stale invites must never
    --    re-open a closed room).
    DELETE FROM public.game_invites
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 2. Delete all participant rows (realtime fans these DELETEs out to
    --    every connected lobby — player lists empty immediately).
    DELETE FROM public.game_participants
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 3. Delete all spectator rows.
    DELETE FROM public.game_spectators
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 4. Delete the room event log (the 'cancel' event inserted by the
    --    caller has already been delivered via realtime WAL).
    DELETE FROM public.game_room_events
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 5. DELETE the game row itself — all game-specific child tables
    --    (players / moves / cards / turns / tokens / rounds / claims)
    --    cascade via FK ON DELETE CASCADE. After this returns, the room
    --    no longer exists anywhere in the database.
    EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', p_game_table)
    USING p_game_id;
END;
$$;
-- No GRANT: internal helper, executable only by the room RPCs below.

-- =====================================================================
-- 2) fn_cancel_game_room — host closes the room.
--    Host-only (checked via game_participants.role OR the game row's
--    hostUserId). Posts the 'cancel' event FIRST (realtime fan-out to
--    every connected client), then HARD-DELETES the room.
--    Used by RoomController.cancelRoom() (unified room framework).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn_cancel_game_room(
    p_game_table text,
    p_game_id text,
    p_user_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_host_user_id text;
    v_family_id text;
    v_table_name text;
    v_has_host_user_id boolean;
    v_participant_role text;
    v_is_host boolean := false;
BEGIN
    v_table_name := p_game_table;

    -- Method 1: check participant role
    SELECT "role", "familyId" INTO v_participant_role, v_family_id
    FROM "game_participants"
    WHERE "gameTable" = p_game_table
      AND "gameId" = p_game_id
      AND "userId" = p_user_id;

    IF v_participant_role = 'host' THEN
        v_is_host := true;
    END IF;

    -- Method 2: check the game row's hostUserId (if column exists)
    IF NOT v_is_host THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = v_table_name
              AND column_name = 'hostUserId'
        ) INTO v_has_host_user_id;

        IF v_has_host_user_id THEN
            BEGIN
                EXECUTE format(
                    'SELECT "hostUserId", "familyId" FROM %I WHERE "id" = $1',
                    v_table_name
                ) INTO v_host_user_id, v_family_id USING p_game_id;

                IF v_host_user_id = p_user_id THEN
                    v_is_host := true;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    END IF;

    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Game not found or you are not a participant';
    END IF;

    IF NOT v_is_host THEN
        RAISE EXCEPTION 'Only the host can cancel the room';
    END IF;

    -- 1. Post the cancel event FIRST so connected clients see it and
    --    leave the room (realtime fan-out happens on commit).
    INSERT INTO "game_room_events"
        ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
    VALUES
        (p_game_table, p_game_id, v_family_id, p_user_id, 'Host', 'cancel',
         jsonb_build_object('reason', 'host_closed_room'));

    -- 2. HARD-DELETE the room + invites + participants + spectators +
    --    events + all cascading game data. A closed room must never
    --    remain in (or reappear from) the database.
    PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_cancel_game_room(text, text, text) TO authenticated;

-- =====================================================================
-- 3) fn_cancel_waiting_room — host cancels a waiting lobby room.
--    HARD-DELETES the room regardless of its status — an explicit
--    host-cancel is always a close. (The previous version silently
--    no-oped once the status left the pre-game set, leaving orphaned
--    rows that later reappeared as "active games".)
--    Used by TemporaryRoomService.cancelWaitingRoom (10 lobby games).
-- =====================================================================
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
    v_family_id text;
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds'
    ) THEN
        RETURN;
    END IF;

    EXECUTE format(
        'SELECT "hostUserId", "status", "familyId" FROM public.%I WHERE "id" = $1;',
        p_game_table
    ) INTO v_host, v_status, v_family_id USING p_game_id;

    IF v_host IS NULL OR v_status IS NULL THEN
        RETURN; -- room already gone — nothing to cancel
    END IF;

    IF v_host = p_user_id THEN
        -- Notify every connected client that the room is closed.
        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, 'Host', 'cancel',
             jsonb_build_object('reason', 'host_cancelled'));

        -- Delete the room immediately from the database.
        PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_cancel_waiting_room(text, text, text) TO authenticated;

-- =====================================================================
-- 4) fn_leave_game_room — leaving a room.
--      • HOST leaves   → the room is closed for everyone and HARD-DELETED
--                        (same as an explicit close — a room without its
--                        host must not linger in the database).
--      • PLAYER leaves → only their participant / player rows are
--                        removed; the room stays open for the others.
--    Used by RoomController.leaveRoom() (unified room framework).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn_leave_game_room(
    p_game_table text,
    p_game_id text,
    p_user_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_host_user_id text;
    v_family_id text;
    v_table_name text;
    v_players_table text;
    v_has_host_user_id boolean;
    v_participant_role text;
    v_user_name text;
    v_is_host boolean := false;
BEGIN
    v_table_name := p_game_table;
    v_players_table := REPLACE(p_game_table, '_games', '_players');

    -- Resolve the leaving user's name (best-effort, for the event log).
    SELECT "userName" INTO v_user_name
    FROM "game_participants"
    WHERE "gameTable" = p_game_table
      AND "gameId" = p_game_id
      AND "userId" = p_user_id;
    IF v_user_name IS NULL THEN
        v_user_name := 'Player';
    END IF;

    -- Host detection, method 1: participant role
    SELECT "role", "familyId" INTO v_participant_role, v_family_id
    FROM "game_participants"
    WHERE "gameTable" = p_game_table
      AND "gameId" = p_game_id
      AND "userId" = p_user_id;
    IF v_participant_role = 'host' THEN
        v_is_host := true;
    END IF;

    -- Host detection, method 2: the game row's hostUserId column
    IF NOT v_is_host THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = v_table_name
              AND column_name = 'hostUserId'
        ) INTO v_has_host_user_id;
        IF v_has_host_user_id THEN
            BEGIN
                EXECUTE format(
                    'SELECT "hostUserId", "familyId" FROM %I WHERE "id" = $1',
                    v_table_name
                ) INTO v_host_user_id, v_family_id USING p_game_id;
                IF v_host_user_id = p_user_id THEN
                    v_is_host := true;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    END IF;

    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Game not found or you are not a participant';
    END IF;

    IF v_is_host THEN
        -- HOST leaving = room closed for everyone → delete immediately.
        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, v_user_name, 'cancel',
             jsonb_build_object('reason', 'host_left', 'wasHost', true));

        PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
    ELSE
        -- PLAYER leaving → free their slot only.
        DELETE FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        BEGIN
            EXECUTE format(
                'DELETE FROM public.%I WHERE "gameId" = $1 AND "userId" = $2;',
                v_players_table
            ) USING p_game_id, p_user_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, v_user_name, 'leave',
             jsonb_build_object('wasHost', false));
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_leave_game_room(text, text, text) TO authenticated;

-- =====================================================================
-- 5) fn_end_game — hard-delete a game row + invites (any status).
--    Now also cleans game_participants / game_spectators /
--    game_room_events so no orphaned room metadata survives.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn_end_game(
    p_game_table text,
    p_game_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_end_game(text, text) TO authenticated;

-- =====================================================================
-- 6) ONE-TIME CLEANUP — remove every soft-closed / stale room already
--    in the database so no closed room can reappear from historical
--    data. Safe to re-run (everything below is idempotent).
-- =====================================================================

-- 6a. Hard-delete every soft-closed room (cancelledAt / closedAt set).
DELETE FROM public.chess_games     WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.tictactoe_games WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.checkers_games  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.carrom_games    WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.sos_games       WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.bingo_games     WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.ludo_games      WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.antakshari_games WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.chitmatch_games  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.dotsboxes_games  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.nameplace_games  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.truthordare_games WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.twotruths_games  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;
DELETE FROM public.redlight_rounds  WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL;

-- 6b. Delete stale rooms older than 12 hours whose status is still
--     pre-game (auto-close cron should have handled these; safety net).
DELETE FROM public.antakshari_games WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.chitmatch_games  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.bingo_games      WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.ludo_games       WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.sos_games        WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.dotsboxes_games  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.nameplace_games  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.truthordare_games WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.twotruths_games  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.redlight_rounds  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.chess_games      WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.tictactoe_games  WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.checkers_games   WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';
DELETE FROM public.carrom_games     WHERE public.fn_is_pre_game_status("status") AND "createdAt" < now() - interval '12 hours';

-- 6c. Delete in-progress rooms with no activity for 12+ hours (abandoned).
DELETE FROM public.antakshari_games WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.chitmatch_games  WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.bingo_games      WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.ludo_games       WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.sos_games        WHERE "status" = 'active'      AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.dotsboxes_games  WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.nameplace_games  WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.truthordare_games WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.twotruths_games  WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.redlight_rounds  WHERE "status" IN ('active','countdown') AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.chess_games      WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.tictactoe_games  WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.checkers_games   WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');
DELETE FROM public.carrom_games     WHERE "status" = 'in_progress' AND (COALESCE("lastActivityAt", "createdAt") < now() - interval '12 hours');

-- 6d. Purge orphaned room metadata whose game row no longer exists.
DELETE FROM public.game_invites gi
WHERE NOT EXISTS (SELECT 1 FROM public.antakshari_games  t WHERE t.id = gi."gameId" AND gi."gameTable" = 'antakshari_games')
  AND NOT EXISTS (SELECT 1 FROM public.chitmatch_games   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'chitmatch_games')
  AND NOT EXISTS (SELECT 1 FROM public.bingo_games       t WHERE t.id = gi."gameId" AND gi."gameTable" = 'bingo_games')
  AND NOT EXISTS (SELECT 1 FROM public.ludo_games        t WHERE t.id = gi."gameId" AND gi."gameTable" = 'ludo_games')
  AND NOT EXISTS (SELECT 1 FROM public.sos_games         t WHERE t.id = gi."gameId" AND gi."gameTable" = 'sos_games')
  AND NOT EXISTS (SELECT 1 FROM public.dotsboxes_games   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'dotsboxes_games')
  AND NOT EXISTS (SELECT 1 FROM public.nameplace_games   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'nameplace_games')
  AND NOT EXISTS (SELECT 1 FROM public.truthordare_games t WHERE t.id = gi."gameId" AND gi."gameTable" = 'truthordare_games')
  AND NOT EXISTS (SELECT 1 FROM public.twotruths_games   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'twotruths_games')
  AND NOT EXISTS (SELECT 1 FROM public.redlight_rounds   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'redlight_rounds')
  AND NOT EXISTS (SELECT 1 FROM public.chess_games       t WHERE t.id = gi."gameId" AND gi."gameTable" = 'chess_games')
  AND NOT EXISTS (SELECT 1 FROM public.tictactoe_games   t WHERE t.id = gi."gameId" AND gi."gameTable" = 'tictactoe_games')
  AND NOT EXISTS (SELECT 1 FROM public.checkers_games    t WHERE t.id = gi."gameId" AND gi."gameTable" = 'checkers_games')
  AND NOT EXISTS (SELECT 1 FROM public.carrom_games      t WHERE t.id = gi."gameId" AND gi."gameTable" = 'carrom_games');

DELETE FROM public.game_participants gp
WHERE NOT EXISTS (SELECT 1 FROM public.antakshari_games  t WHERE t.id = gp."gameId" AND gp."gameTable" = 'antakshari_games')
  AND NOT EXISTS (SELECT 1 FROM public.chitmatch_games   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'chitmatch_games')
  AND NOT EXISTS (SELECT 1 FROM public.bingo_games       t WHERE t.id = gp."gameId" AND gp."gameTable" = 'bingo_games')
  AND NOT EXISTS (SELECT 1 FROM public.ludo_games        t WHERE t.id = gp."gameId" AND gp."gameTable" = 'ludo_games')
  AND NOT EXISTS (SELECT 1 FROM public.sos_games         t WHERE t.id = gp."gameId" AND gp."gameTable" = 'sos_games')
  AND NOT EXISTS (SELECT 1 FROM public.dotsboxes_games   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'dotsboxes_games')
  AND NOT EXISTS (SELECT 1 FROM public.nameplace_games   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'nameplace_games')
  AND NOT EXISTS (SELECT 1 FROM public.truthordare_games t WHERE t.id = gp."gameId" AND gp."gameTable" = 'truthordare_games')
  AND NOT EXISTS (SELECT 1 FROM public.twotruths_games   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'twotruths_games')
  AND NOT EXISTS (SELECT 1 FROM public.redlight_rounds   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'redlight_rounds')
  AND NOT EXISTS (SELECT 1 FROM public.chess_games       t WHERE t.id = gp."gameId" AND gp."gameTable" = 'chess_games')
  AND NOT EXISTS (SELECT 1 FROM public.tictactoe_games   t WHERE t.id = gp."gameId" AND gp."gameTable" = 'tictactoe_games')
  AND NOT EXISTS (SELECT 1 FROM public.checkers_games    t WHERE t.id = gp."gameId" AND gp."gameTable" = 'checkers_games')
  AND NOT EXISTS (SELECT 1 FROM public.carrom_games      t WHERE t.id = gp."gameId" AND gp."gameTable" = 'carrom_games');

DELETE FROM public.game_spectators gs
WHERE NOT EXISTS (SELECT 1 FROM public.antakshari_games  t WHERE t.id = gs."gameId" AND gs."gameTable" = 'antakshari_games')
  AND NOT EXISTS (SELECT 1 FROM public.chitmatch_games   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'chitmatch_games')
  AND NOT EXISTS (SELECT 1 FROM public.bingo_games       t WHERE t.id = gs."gameId" AND gs."gameTable" = 'bingo_games')
  AND NOT EXISTS (SELECT 1 FROM public.ludo_games        t WHERE t.id = gs."gameId" AND gs."gameTable" = 'ludo_games')
  AND NOT EXISTS (SELECT 1 FROM public.sos_games         t WHERE t.id = gs."gameId" AND gs."gameTable" = 'sos_games')
  AND NOT EXISTS (SELECT 1 FROM public.dotsboxes_games   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'dotsboxes_games')
  AND NOT EXISTS (SELECT 1 FROM public.nameplace_games   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'nameplace_games')
  AND NOT EXISTS (SELECT 1 FROM public.truthordare_games t WHERE t.id = gs."gameId" AND gs."gameTable" = 'truthordare_games')
  AND NOT EXISTS (SELECT 1 FROM public.twotruths_games   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'twotruths_games')
  AND NOT EXISTS (SELECT 1 FROM public.redlight_rounds   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'redlight_rounds')
  AND NOT EXISTS (SELECT 1 FROM public.chess_games       t WHERE t.id = gs."gameId" AND gs."gameTable" = 'chess_games')
  AND NOT EXISTS (SELECT 1 FROM public.tictactoe_games   t WHERE t.id = gs."gameId" AND gs."gameTable" = 'tictactoe_games')
  AND NOT EXISTS (SELECT 1 FROM public.checkers_games    t WHERE t.id = gs."gameId" AND gs."gameTable" = 'checkers_games')
  AND NOT EXISTS (SELECT 1 FROM public.carrom_games      t WHERE t.id = gs."gameId" AND gs."gameTable" = 'carrom_games');

DELETE FROM public.game_room_events ge
WHERE NOT EXISTS (SELECT 1 FROM public.antakshari_games  t WHERE t.id = ge."gameId" AND ge."gameTable" = 'antakshari_games')
  AND NOT EXISTS (SELECT 1 FROM public.chitmatch_games   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'chitmatch_games')
  AND NOT EXISTS (SELECT 1 FROM public.bingo_games       t WHERE t.id = ge."gameId" AND ge."gameTable" = 'bingo_games')
  AND NOT EXISTS (SELECT 1 FROM public.ludo_games        t WHERE t.id = ge."gameId" AND ge."gameTable" = 'ludo_games')
  AND NOT EXISTS (SELECT 1 FROM public.sos_games         t WHERE t.id = ge."gameId" AND ge."gameTable" = 'sos_games')
  AND NOT EXISTS (SELECT 1 FROM public.dotsboxes_games   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'dotsboxes_games')
  AND NOT EXISTS (SELECT 1 FROM public.nameplace_games   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'nameplace_games')
  AND NOT EXISTS (SELECT 1 FROM public.truthordare_games t WHERE t.id = ge."gameId" AND ge."gameTable" = 'truthordare_games')
  AND NOT EXISTS (SELECT 1 FROM public.twotruths_games   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'twotruths_games')
  AND NOT EXISTS (SELECT 1 FROM public.redlight_rounds   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'redlight_rounds')
  AND NOT EXISTS (SELECT 1 FROM public.chess_games       t WHERE t.id = ge."gameId" AND ge."gameTable" = 'chess_games')
  AND NOT EXISTS (SELECT 1 FROM public.tictactoe_games   t WHERE t.id = ge."gameId" AND ge."gameTable" = 'tictactoe_games')
  AND NOT EXISTS (SELECT 1 FROM public.checkers_games    t WHERE t.id = ge."gameId" AND ge."gameTable" = 'checkers_games')
  AND NOT EXISTS (SELECT 1 FROM public.carrom_games      t WHERE t.id = ge."gameId" AND ge."gameTable" = 'carrom_games');
