-- =====================================================================
-- 20260912120000_temporary_game_rooms.sql
--
-- Purpose: Implement a "temporary room" lifecycle for every multiplayer
-- game. A room is created fresh every time a user taps Play, never reused,
-- auto-expires after 5 minutes of inactivity while waiting, gets deleted
-- immediately if the host leaves before the game starts, and is removed
-- (along with all temporary player associations) shortly after the game
-- ends. Completed games are purged after 1 hour to give results screens
-- time to render.
--
-- Status naming variance handled:
--   • Most Pattern B games use 'waiting' / 'in_progress' / 'completed'.
--   • SOS and redlight use 'lobby' / 'active' / 'finished'.
--   • Chitmatch uses 'waiting' / 'setup' / 'in_progress' / 'completed'
--     (the 'setup' phase is also pre-game).
-- All pre-game states ('waiting', 'lobby', 'setup') and all completed
-- states ('completed', 'finished') are treated as equivalent by the
-- cleanup functions.
--
-- Tables covered:
--   Pattern B (with hostUserId + _players):
--     antakshari, chitmatch, bingo (no players table), ludo, sos,
--     dotsboxes, nameplace, truthordare, twotruths, redlight (uses
--     redlight_rounds as parent + redlight_players with roundId).
--   Pattern A (2-player direct challenge, no host column):
--     chess, tictactoe, checkers, carrom. Only post-game cleanup applies.
-- =====================================================================

-- =====================================================================
-- 1) Add `lastActivityAt` column to every game parent table.
-- =====================================================================

DO $$
DECLARE
    tbl text;
    all_tables text[] := ARRAY[
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ];
BEGIN
    FOREACH tbl IN ARRAY all_tables LOOP
        BEGIN
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS "lastActivityAt" timestamptz NOT NULL DEFAULT now();', tbl);
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I ("lastActivityAt");', 'idx_' || tbl || '_lastActivityAt', tbl);
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I ("status", "lastActivityAt");', 'idx_' || tbl || '_status_lastActivityAt', tbl);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skip lastActivityAt for %: %', tbl, SQLERRM;
        END;
    END LOOP;
END $$;

-- =====================================================================
-- 2) Add `isReady` + `readyAt` columns to every *_players table.
-- =====================================================================

DO $$
DECLARE
    tbl text;
    players_tables text[] := ARRAY[
        'antakshari_players', 'chitmatch_players', 'ludo_players',
        'sos_players', 'dotsboxes_players', 'nameplace_players',
        'truthordare_players', 'twotruths_players', 'redlight_players',
        'bingo_players'
    ];
BEGIN
    FOREACH tbl IN ARRAY players_tables LOOP
        BEGIN
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS "isReady" boolean NOT NULL DEFAULT false;', tbl);
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS "readyAt" timestamptz;', tbl);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skip isReady for %: %', tbl, SQLERRM;
        END;
    END LOOP;
END $$;

-- =====================================================================
-- 3) Status-classification helpers (handle naming variance).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_is_pre_game_status(p_status text)
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    AS $$ SELECT p_status IN ('waiting', 'lobby', 'setup') $$;

CREATE OR REPLACE FUNCTION public.fn_is_completed_status(p_status text)
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    AS $$ SELECT p_status IN ('completed', 'finished') $$;

GRANT EXECUTE ON FUNCTION public.fn_is_pre_game_status(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_is_completed_status(text) TO authenticated, anon;

-- =====================================================================
-- 4) fn_touch_game_activity(p_game_table, p_game_id)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(
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
    EXECUTE format(
        'UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;',
        p_game_table
    ) USING p_game_id;
END;
$$;

-- =====================================================================
-- 5) fn_set_player_ready
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_set_player_ready(
    p_player_table text,
    p_game_table text,
    p_game_id text,
    p_user_id text,
    p_is_ready boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_player_table NOT IN (
        'antakshari_players', 'chitmatch_players', 'ludo_players',
        'sos_players', 'dotsboxes_players', 'nameplace_players',
        'truthordare_players', 'twotruths_players', 'redlight_players',
        'bingo_players'
    ) THEN
        RAISE EXCEPTION 'Unknown player table: %', p_player_table;
    END IF;
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    IF p_player_table = 'redlight_players' THEN
        EXECUTE format(
            'UPDATE public.%I SET "isReady" = $1, "readyAt" = CASE WHEN $1 THEN now() ELSE NULL END
             WHERE "roundId" = $2 AND "userId" = $3;',
            p_player_table
        ) USING p_is_ready, p_game_id, p_user_id;
    ELSE
        EXECUTE format(
            'UPDATE public.%I SET "isReady" = $1, "readyAt" = CASE WHEN $1 THEN now() ELSE NULL END
             WHERE "gameId" = $2 AND "userId" = $3;',
            p_player_table
        ) USING p_is_ready, p_game_id, p_user_id;
    END IF;

    PERFORM public.fn_touch_game_activity(p_game_table, p_game_id);
END;
$$;

-- =====================================================================
-- 6) fn_cancel_waiting_room — treats 'waiting'/'lobby'/'setup' as pre-game
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
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds'
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
        EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', p_game_table) USING p_game_id;
    END IF;
END;
$$;

-- =====================================================================
-- 7) fn_end_game — hard-delete game + invites (any status)
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
    DELETE FROM public.game_invites WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;
    EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', p_game_table) USING p_game_id;
END;
$$;

-- =====================================================================
-- 8) fn_expire_stale_game_rooms — 5-min inactivity cleanup (pre-game states)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_expire_stale_game_rooms()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    tbl text;
    all_tables text[] := ARRAY[
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ];
BEGIN
    FOREACH tbl IN ARRAY all_tables LOOP
        BEGIN
            EXECUTE format(
                'DELETE FROM public.game_invites
                 WHERE "gameTable" = $1
                   AND "status" = ''pending''
                   AND "gameId" IN (
                     SELECT "id" FROM public.%I
                     WHERE public.fn_is_pre_game_status("status")
                       AND "lastActivityAt" < now() - interval ''5 minutes''
                   );',
                tbl
            ) USING tbl;
            EXECUTE format(
                'DELETE FROM public.%I
                 WHERE public.fn_is_pre_game_status("status")
                   AND "lastActivityAt" < now() - interval ''5 minutes'';',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'fn_expire_stale_game_rooms: skip %: %', tbl, SQLERRM;
        END;
    END LOOP;
END;
$$;

-- =====================================================================
-- 9) fn_cleanup_completed_games — 1-hour post-completion cleanup.
--    Splits tables into two batches: those using completedAt (12 games)
--    and those using finishedAt (sos_games + redlight_rounds). COALESCE
--    approach failed silently when one of the columns didn't exist.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_cleanup_completed_games()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    tbl text;
    completed_tables text[] := ARRAY[
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'dotsboxes_games', 'nameplace_games', 'truthordare_games',
        'twotruths_games', 'chess_games', 'tictactoe_games',
        'checkers_games', 'carrom_games'
    ];
    finished_tables text[] := ARRAY['sos_games', 'redlight_rounds'];
BEGIN
    FOREACH tbl IN ARRAY completed_tables LOOP
        BEGIN
            EXECUTE format(
                'DELETE FROM public.game_invites
                 WHERE "gameTable" = $1
                   AND "gameId" IN (
                     SELECT "id" FROM public.%I
                     WHERE public.fn_is_completed_status("status")
                       AND "completedAt" IS NOT NULL
                       AND "completedAt" < now() - interval ''1 hour''
                   );',
                tbl
            ) USING tbl;
            EXECUTE format(
                'DELETE FROM public.%I
                 WHERE public.fn_is_completed_status("status")
                   AND "completedAt" IS NOT NULL
                   AND "completedAt" < now() - interval ''1 hour'';',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'fn_cleanup_completed_games: skip %: %', tbl, SQLERRM;
        END;
    END LOOP;

    FOREACH tbl IN ARRAY finished_tables LOOP
        BEGIN
            EXECUTE format(
                'DELETE FROM public.game_invites
                 WHERE "gameTable" = $1
                   AND "gameId" IN (
                     SELECT "id" FROM public.%I
                     WHERE public.fn_is_completed_status("status")
                       AND "finishedAt" IS NOT NULL
                       AND "finishedAt" < now() - interval ''1 hour''
                   );',
                tbl
            ) USING tbl;
            EXECUTE format(
                'DELETE FROM public.%I
                 WHERE public.fn_is_completed_status("status")
                   AND "finishedAt" IS NOT NULL
                   AND "finishedAt" < now() - interval ''1 hour'';',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'fn_cleanup_completed_games: skip %: %', tbl, SQLERRM;
        END;
    END LOOP;
END;
$$;

-- =====================================================================
-- 10) fn_get_room_summary — returns JSON state for lobby UI
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_get_room_summary(
    p_game_table text,
    p_player_table text,
    p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status text;
    v_host_id text;
    v_started_at timestamptz;
    v_completed_at timestamptz;
    v_max_players int;
    v_player_count int;
    v_ready_count int;
    v_all_ready boolean;
    v_players jsonb;
    v_finished_only boolean;
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds'
    ) THEN
        RETURN jsonb_build_object('error', 'unsupported game table');
    END IF;
    IF p_player_table NOT IN (
        'antakshari_players', 'chitmatch_players', 'ludo_players',
        'sos_players', 'dotsboxes_players', 'nameplace_players',
        'truthordare_players', 'twotruths_players', 'redlight_players',
        'bingo_players'
    ) THEN
        RETURN jsonb_build_object('error', 'unsupported player table');
    END IF;

    -- sos_games and redlight_rounds use finishedAt; the rest use completedAt.
    v_finished_only := p_game_table IN ('sos_games', 'redlight_rounds');

    IF v_finished_only THEN
        EXECUTE format(
            'SELECT "status", "hostUserId", "startedAt", "finishedAt"
             FROM public.%I WHERE "id" = $1;',
            p_game_table
        ) INTO v_status, v_host_id, v_started_at, v_completed_at USING p_game_id;
    ELSE
        EXECUTE format(
            'SELECT "status", "hostUserId", "startedAt", "completedAt", "maxPlayers"
             FROM public.%I WHERE "id" = $1;',
            p_game_table
        ) INTO v_status, v_host_id, v_started_at, v_completed_at, v_max_players USING p_game_id;
    END IF;

    IF p_player_table = 'redlight_players' THEN
        EXECUTE format(
            'SELECT count(*)::int, coalesce(sum(("isReady")::int)::int, 0)
             FROM public.%I WHERE "roundId" = $1;',
            p_player_table
        ) INTO v_player_count, v_ready_count USING p_game_id;
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(jsonb_build_object(
                ''userId'', "userId",
                ''userName'', "userName",
                ''isReady'', "isReady",
                ''readyAt'', "readyAt",
                ''joinedAt'', "joinedAt"
            ) ORDER BY "joinedAt"), ''[]''::jsonb)
             FROM public.%I WHERE "roundId" = $1;',
            p_player_table
        ) INTO v_players USING p_game_id;
    ELSE
        EXECUTE format(
            'SELECT count(*)::int, coalesce(sum(("isReady")::int)::int, 0)
             FROM public.%I WHERE "gameId" = $1;',
            p_player_table
        ) INTO v_player_count, v_ready_count USING p_game_id;
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(jsonb_build_object(
                ''userId'', "userId",
                ''userName'', "userName",
                ''isReady'', "isReady",
                ''readyAt'', "readyAt",
                ''joinedAt'', "joinedAt"
            ) ORDER BY "joinedAt"), ''[]''::jsonb)
             FROM public.%I WHERE "gameId" = $1;',
            p_player_table
        ) INTO v_players USING p_game_id;
    END IF;

    v_all_ready := (v_player_count >= 2 AND v_ready_count = v_player_count);

    RETURN jsonb_build_object(
        'gameTable', p_game_table,
        'gameId', p_game_id,
        'status', v_status,
        'hostUserId', v_host_id,
        'startedAt', v_started_at,
        'completedAt', v_completed_at,
        'maxPlayers', v_max_players,
        'playerCount', v_player_count,
        'readyCount', v_ready_count,
        'allReady', v_all_ready,
        'players', v_players
    );
END;
$$;

-- =====================================================================
-- 11) Triggers: bump lastActivityAt + host-leave cleanup
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_bump_game_activity()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_game_table text;
    v_game_id text;
BEGIN
    v_game_table := CASE TG_TABLE_NAME
        WHEN 'antakshari_players' THEN 'antakshari_games'
        WHEN 'chitmatch_players'  THEN 'chitmatch_games'
        WHEN 'ludo_players'       THEN 'ludo_games'
        WHEN 'sos_players'         THEN 'sos_games'
        WHEN 'dotsboxes_players'   THEN 'dotsboxes_games'
        WHEN 'nameplace_players'   THEN 'nameplace_games'
        WHEN 'truthordare_players' THEN 'truthordare_games'
        WHEN 'twotruths_players'   THEN 'twotruths_games'
        WHEN 'redlight_players'    THEN 'redlight_rounds'
        WHEN 'bingo_players'       THEN 'bingo_games'
    END;

    IF v_game_table IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_TABLE_NAME = 'redlight_players' THEN
        v_game_id := COALESCE(NEW."roundId", OLD."roundId");
    ELSE
        v_game_id := COALESCE(NEW."gameId", OLD."gameId");
    END IF;

    IF v_game_id IS NOT NULL THEN
        BEGIN
            EXECUTE format(
                'UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;',
                v_game_table
            ) USING v_game_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'bump_game_activity: %', SQLERRM;
        END;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_host_leave_cancels_waiting()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_game_table text;
    v_game_id text;
    v_host text;
    v_status text;
    v_other_players int;
BEGIN
    v_game_table := CASE TG_TABLE_NAME
        WHEN 'antakshari_players' THEN 'antakshari_games'
        WHEN 'chitmatch_players'  THEN 'chitmatch_games'
        WHEN 'ludo_players'       THEN 'ludo_games'
        WHEN 'sos_players'         THEN 'sos_games'
        WHEN 'dotsboxes_players'   THEN 'dotsboxes_games'
        WHEN 'nameplace_players'   THEN 'nameplace_games'
        WHEN 'truthordare_players' THEN 'truthordare_games'
        WHEN 'twotruths_players'   THEN 'twotruths_games'
        WHEN 'redlight_players'    THEN 'redlight_rounds'
        WHEN 'bingo_players'       THEN 'bingo_games'
    END;

    IF v_game_table IS NULL THEN
        RETURN OLD;
    END IF;

    IF TG_TABLE_NAME = 'redlight_players' THEN
        v_game_id := OLD."roundId";
    ELSE
        v_game_id := OLD."gameId";
    END IF;

    IF v_game_id IS NULL THEN
        RETURN OLD;
    END IF;

    BEGIN
        EXECUTE format(
            'SELECT "hostUserId", "status" FROM public.%I WHERE "id" = $1;',
            v_game_table
        ) INTO v_host, v_status USING v_game_id;

        -- Only act if the deleted row's user was the host AND the room
        -- is still in a pre-game state.
        IF v_host = OLD."userId" AND public.fn_is_pre_game_status(v_status) THEN
            -- Count OTHER player rows still in this room (excluding the
            -- one being deleted). If there are any, close the room —
            -- they shouldn't be stuck in a lobby with no host. If there
            -- are none, leave the room alive for the host to rejoin.
            IF TG_TABLE_NAME = 'redlight_players' THEN
                SELECT count(*)::int INTO v_other_players
                FROM public.redlight_players
                WHERE "roundId" = v_game_id
                  AND "userId" <> OLD."userId";
            ELSE
                EXECUTE format(
                    'SELECT count(*)::int FROM public.%I
                     WHERE "gameId" = $1 AND "userId" <> $2;',
                    TG_TABLE_NAME
                ) INTO v_other_players USING v_game_id, OLD."userId";
            END IF;

            IF v_other_players > 0 THEN
                -- Other players still in the room — close it.
                DELETE FROM public.game_invites WHERE "gameTable" = v_game_table AND "gameId" = v_game_id;
                EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', v_game_table) USING v_game_id;
            END IF;
            -- Else: host was alone. Leave the room alive for rejoin.
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'host_leave_cancels_waiting: %', SQLERRM;
    END;

    RETURN OLD;
END;
$$;

-- Attach both triggers to each player table
DO $$
DECLARE
    tbl text;
    players_tables text[] := ARRAY[
        'antakshari_players', 'chitmatch_players', 'ludo_players',
        'sos_players', 'dotsboxes_players', 'nameplace_players',
        'truthordare_players', 'twotruths_players', 'redlight_players',
        'bingo_players'
    ];
BEGIN
    FOREACH tbl IN ARRAY players_tables LOOP
        BEGIN
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I;', 'trg_' || tbl || '_bump_activity', tbl);
            EXECUTE format(
                'CREATE TRIGGER %I
                 AFTER INSERT OR UPDATE OR DELETE ON public.%I
                 FOR EACH ROW EXECUTE FUNCTION public.fn_bump_game_activity();',
                'trg_' || tbl || '_bump_activity',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'trigger skip %: %', tbl, SQLERRM;
        END;
    END LOOP;

    FOREACH tbl IN ARRAY players_tables LOOP
        BEGIN
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I;', 'trg_' || tbl || '_host_leave_cancel', tbl);
            EXECUTE format(
                'CREATE TRIGGER %I
                 AFTER DELETE ON public.%I
                 FOR EACH ROW EXECUTE FUNCTION public.fn_host_leave_cancels_waiting();',
                'trg_' || tbl || '_host_leave_cancel',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'host-leave trigger skip %: %', tbl, SQLERRM;
        END;
    END LOOP;
END $$;

-- =====================================================================
-- 12) Grants
-- =====================================================================
GRANT EXECUTE ON FUNCTION public.fn_is_pre_game_status(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_is_completed_status(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_set_player_ready(text, text, text, text, boolean) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_cancel_waiting_room(text, text, text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_end_game(text, text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_expire_stale_game_rooms() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_cleanup_completed_games() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_room_summary(text, text, text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_bump_game_activity() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_host_leave_cancels_waiting() TO authenticated, anon;

-- =====================================================================
-- 13) pg_cron jobs
-- =====================================================================
DO $_$
BEGIN
    BEGIN
        PERFORM cron.schedule(
            'expire-stale-game-rooms',
            '*/5 * * * *',
            'SELECT public.fn_expire_stale_game_rooms();'
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cron expire-stale-game-rooms: %', SQLERRM;
    END;

    BEGIN
        PERFORM cron.schedule(
            'cleanup-completed-games',
            '0 * * * *',
            'SELECT public.fn_cleanup_completed_games();'
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cron cleanup-completed-games: %', SQLERRM;
    END;
END $_$;

-- =====================================================================
-- 14) Backfill lastActivityAt = createdAt for any existing rows so they
--     don't immediately expire under the new policy.
-- =====================================================================
DO $$
DECLARE
    tbl text;
    all_tables text[] := ARRAY[
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ];
BEGIN
    FOREACH tbl IN ARRAY all_tables LOOP
        BEGIN
            EXECUTE format(
                'UPDATE public.%I SET "lastActivityAt" = "createdAt"
                 WHERE "lastActivityAt" IS NULL;',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'backfill skip %: %', tbl, SQLERRM;
        END;
    END LOOP;
END $$;
