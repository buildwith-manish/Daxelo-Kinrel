-- =============================================================================
-- Daxelo-Kinrel — Task 4 (round 2): auto-close paths must HARD-DELETE
-- =============================================================================
-- Context found during live E2E:
--
--   A chess game created via ChallengeLobbyScreen was auto-closed 79s
--   after creation by fn_reap_disconnected_players with reason
--   'host_disconnected', even though the host's browser was open. The
--   challenge lobby attaches the RoomController (which heartbeats
--   game_participants.lastSeenAt every 20s), but pushReplacement to the
--   board route unmounts the lobby → roomControllerProvider is
--   autoDispose → heartbeat timer disposed → lastSeenAt goes stale →
--   the reaper flags the host disconnected.
--
--   CLIENT fix (separate commit): board screens wrap their body in
--   RoomKeepAlive so the controller (and heartbeat) survives the
--   lobby → board navigation.
--
--   THIS migration fixes the SERVER side so both auto-close paths are
--   consistent with the Task A hard-delete contract ("once a room is
--   closed it is deleted from the database immediately"):
--
--   1. fn_reap_disconnected_players — host-disconnect branch used to
--      only SET closedAt/cancelledAt (soft close). That left a stale
--      game row in the DB that could never be played again, and the
--      remaining player's board (which only reacts to the game-row
--      DELETE realtime event) hung on a dead game forever. Now the
--      branch posts the 'auto_close' event first (realtime fan-out to
--      every connected client) and then PERFORMs fn__hard_delete_room,
--      which removes invites / participants / spectators / events and
--      the game row itself (children cascade).
--
--   2. fn_close_expired_rooms — the deadline path already deleted
--      participants + spectators but left the game row + event log.
--      Now it posts the 'auto_close' event and calls
--      fn__hard_delete_room as well, so expired never-started rooms
--      leave zero rows behind.
-- =====================================================================

-- ── 1) fn_reap_disconnected_players → hard-delete on host disconnect ──
--    Host detection mirrors 20260913130000: game_participants.role='host'
--    first (board games have NO hostUserId column — a hostUserId-only
--    check silently skips chess/checkers/tictactoe/carrom rooms), with
--    the game-row hostUserId column as fallback for older rows.
CREATE OR REPLACE FUNCTION public.fn_reap_disconnected_players(
    p_stale_threshold_seconds integer DEFAULT 60
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_reaped_count integer := 0;
        r record;
        v_host_user_id text;
        v_table_name text;
        v_is_host boolean := false;
        v_has_host_col boolean := false;
    BEGIN
        FOR r IN
            SELECT "gameTable", "gameId", "familyId", "userId", "userName", "role"
            FROM "game_participants"
            WHERE "connectionState" = 'online'
              AND "leftAt" IS NULL
              AND "lastSeenAt" < now() - (p_stale_threshold_seconds || ' seconds')::interval
        LOOP
            -- Mark them offline (row is removed entirely below when the
            -- host is the stale one, but non-host frees need this).
            UPDATE "game_participants"
            SET "connectionState" = 'offline',
                "leftAt" = now()
            WHERE "gameTable" = r."gameTable"
              AND "gameId" = r."gameId"
              AND "userId" = r."userId";

            -- Post a leave event
            INSERT INTO "game_room_events"
                ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
            VALUES
                (r."gameTable", r."gameId", r."familyId", r."userId", r."userName", 'leave',
                 jsonb_build_object('reason', 'disconnected'));

            -- Host? role first, hostUserId column fallback.
            v_table_name := r."gameTable";
            v_is_host := (r."role" = 'host');
            IF NOT v_is_host THEN
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = v_table_name
                      AND column_name = 'hostUserId'
                ) INTO v_has_host_col;
                IF v_has_host_col THEN
                    BEGIN
                        EXECUTE format(
                            'SELECT "hostUserId" FROM %I WHERE "id" = $1',
                            v_table_name
                        ) INTO v_host_user_id USING r."gameId";
                        v_is_host := (v_host_user_id = r."userId");
                    EXCEPTION WHEN OTHERS THEN
                        v_is_host := false;
                    END;
                END IF;
            END IF;

            -- If they're the host, close the room — HARD delete, same
            -- contract as fn_cancel_game_room: post the event first
            -- (realtime WAL delivers it to every connected client),
            -- then remove the room from the database entirely.
            IF v_is_host THEN
                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (r."gameTable", r."gameId", r."familyId", NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'host_disconnected'));

                PERFORM public.fn__hard_delete_room(r."gameTable", r."gameId");
            END IF;

            v_reaped_count := v_reaped_count + 1;
        END LOOP;

        RETURN v_reaped_count;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_reap_disconnected_players(integer) TO authenticated;

-- ── 2) fn_close_expired_rooms → hard-delete on deadline ──────────────
CREATE OR REPLACE FUNCTION public.fn_close_expired_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_closed_count integer := 0;
        t text;
        r record;
    BEGIN
        FOREACH t IN ARRAY ARRAY[
            'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
            'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
            'truthordare_games', 'twotruths_games', 'dotsboxes_games',
            'nameplace_games', 'chitmatch_games', 'redlight_rounds'
        ] LOOP
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id, "familyId" AS family_id
                 FROM %I
                 WHERE "autoCloseDeadline" IS NOT NULL
                   AND "autoCloseDeadline" <= now()
                   AND "cancelledAt" IS NULL
                   AND "closedAt" IS NULL
                   AND (
                       "status" IN (''lobby'', ''waiting'')
                       OR "status" IS NULL
                   )',
                t
            ) LOOP
                -- Post the auto_close event FIRST so realtime clients
                -- (waiting rooms, boards) receive it via WAL before the
                -- rows vanish.
                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'auto_close_deadline_passed'));

                -- Remove the room entirely (invites, participants,
                -- spectators, events + game row; children cascade).
                BEGIN
                    PERFORM public.fn__hard_delete_room(t, r.game_id);
                EXCEPTION WHEN OTHERS THEN
                    -- Unknown table whitelist miss — fall back to soft close.
                    EXECUTE format(
                        'UPDATE %I SET "closedAt" = now(), "cancelledAt" = COALESCE("cancelledAt", now()) WHERE "id" = $1',
                        t
                    ) USING r.game_id;
                    DELETE FROM "game_participants"
                    WHERE "gameTable" = t AND "gameId" = r.game_id;
                    DELETE FROM "game_spectators"
                    WHERE "gameTable" = t AND "gameId" = r.game_id;
                END;

                v_closed_count := v_closed_count + 1;
            END LOOP;
        END LOOP;

        RETURN v_closed_count;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_close_expired_rooms() TO authenticated;

-- ── 3) One-time cleanup of soft-closed leftovers ─────────────────────
--     Rooms already soft-closed by the old reaper/expiry logic (closedAt
--     or cancelledAt set) can never be played again — delete them now so
--     Play taps never see them.
DO $$
DECLARE
    t text;
    r record;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
        'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
        'truthordare_games', 'twotruths_games', 'dotsboxes_games',
        'nameplace_games', 'chitmatch_games', 'redlight_rounds'
    ] LOOP
        BEGIN
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id FROM %I
                 WHERE "cancelledAt" IS NOT NULL OR "closedAt" IS NOT NULL',
                t
            ) LOOP
                BEGIN
                    PERFORM public.fn__hard_delete_room(t, r.game_id);
                EXCEPTION WHEN OTHERS THEN
                    EXECUTE format('DELETE FROM %I WHERE "id" = $1', t)
                    USING r.game_id;
                END;
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;
END $$;
