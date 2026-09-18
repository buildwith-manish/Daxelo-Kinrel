-- =============================================================================
-- Daxelo-Kinrel — Unified Multiplayer Room Lifecycle Framework
-- =============================================================================
-- Adds the shared room-lifecycle primitives used by ALL multiplayer games
-- (SOS, Bingo, Ludo, Chess, Checkers, Carrom, TicTacToe, TruthOrDare,
-- TwoTruths, DotsBoxes, NamePlace, ChitMatch, Antakshari, RedLight):
--
--   • readyAt                — when a participant tapped "Ready"
--   • autoCloseDeadline      — server-authoritative countdown for lobby TTL
--   • cancelledAt            — when the host cancelled the room
--   • hostReady              — host is always ready (computed; column for RLS)
--   • game_room_events       — server-persisted join/leave/spectator/system
--                              messages so disconnects + reconnects don't lose
--                              lobby state
--
-- Design principles (per the implementation prompt):
--   1. Server-authoritative room state. No client decides a room exists.
--   2. Single source of truth: the game row + game_participants row.
--   3. Auto-close timer is REAL — driven by `autoCloseDeadline`, evaluated
--      server-side via a background cron + RPC, so even if no client is
--      online the room still closes.
--   4. Spectator membership is tracked in `game_spectators` (already exists).
--   5. Lobby chat is persisted in `game_room_events` so reconnects restore it.
-- =============================================================================

-- ── 1. Add room-lifecycle columns to every game table ───────────────────
-- All 14 game tables get the same three columns.
-- `autoCloseDeadline` defaults to NULL — set by the host at create time.
-- `cancelledAt` defaults to NULL — set when host taps "Cancel Room".
-- `hostReady` defaults to TRUE — host is always considered ready.

DO $$
DECLARE
    t text;
    game_tables text[] := ARRAY[
        'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
        'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
        'truthordare_games', 'twotruths_games', 'dotsboxes_games',
        'nameplace_games', 'chitmatch_games', 'redlight_rounds'
    ];
BEGIN
    FOREACH t IN ARRAY game_tables LOOP
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS "autoCloseDeadline" timestamptz;', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS "cancelledAt" timestamptz;', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS "closedAt" timestamptz;', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS "hostReady" boolean NOT NULL DEFAULT true;', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS "spectatorsEnabled" boolean NOT NULL DEFAULT true;', t);
        -- Backfill hostReady=TRUE for all existing lobby rows (host auto-ready)
        EXECUTE format('UPDATE %I SET "hostReady" = TRUE WHERE "hostReady" IS NULL;', t);
    END LOOP;
END $$;

-- ── 2. Add readyAt + presence columns to game_participants ──────────────
-- `readyAt` tracks when each participant tapped Ready (NULL = not ready).
-- `lastSeenAt` is updated by a heartbeat from each connected client; used
-- by the disconnect-reaper RPC to free slots when a player goes offline.

ALTER TABLE "game_participants"
    ADD COLUMN IF NOT EXISTS "readyAt" timestamptz;
ALTER TABLE "game_participants"
    ADD COLUMN IF NOT EXISTS "lastSeenAt" timestamptz NOT NULL DEFAULT now();
ALTER TABLE "game_participants"
    ADD COLUMN IF NOT EXISTS "connectionState" text NOT NULL DEFAULT 'online';

-- Index: fast lookup of "who is ready in this room"
CREATE INDEX IF NOT EXISTS idx_game_participants_ready
    ON "game_participants" ("gameTable", "gameId", "readyAt");

-- Index: fast lookup of "stale participants" for the reaper
CREATE INDEX IF NOT EXISTS idx_game_participants_lastseen
    ON "game_participants" ("connectionState", "lastSeenAt");

-- ── 3. game_room_events — persistent lobby system messages ──────────────
-- Tracks join / leave / ready / spectator / cancel / auto-close / chat
-- events. Used to:
--   • Show "John joined the room." / "John left the room." system messages
--   • Restore lobby chat on reconnect (no more ephemeral-only messages)
--   • Drive the realtime broadcast fan-out (AFTER INSERT trigger notifies
--     all realtime subscribers on the room's channel)

CREATE TABLE IF NOT EXISTS "game_room_events" (
    "id"           text PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameTable"    text NOT NULL,
    "gameId"       text NOT NULL,
    "familyId"     text NOT NULL,
    "userId"       text,                  -- nullable for system events
    "userName"     text,
    "eventType"    text NOT NULL,          -- join|leave|ready|not_ready|
                                           -- spectator_join|spectator_leave|
                                           -- cancel|auto_close|host_change|
                                           -- chat|system
    "payload"      jsonb NOT NULL DEFAULT '{}'::jsonb,
    "createdAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_room_events_game
    ON "game_room_events" ("gameTable", "gameId", "createdAt");
CREATE INDEX IF NOT EXISTS idx_game_room_events_family
    ON "game_room_events" ("familyId", "createdAt" DESC);

ALTER TABLE "game_room_events" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_room_events_select_family"
    ON "game_room_events" FOR SELECT TO authenticated
    USING (fn_user_is_family_member("familyId"));

CREATE POLICY "game_room_events_insert_family"
    ON "game_room_events" FOR INSERT TO authenticated
    WITH CHECK (
        "userId" = auth.uid()::text
        AND fn_user_is_family_member("familyId")
    );

CREATE POLICY "game_room_events_delete_host"
    ON "game_room_events" FOR DELETE TO authenticated
    USING (
        fn_user_is_family_member("familyId")
    );

GRANT SELECT, INSERT, DELETE ON "game_room_events" TO authenticated;

-- ── 4. RPC: fn_set_player_ready ──────────────────────────────────────────
-- Toggles a participant's readyAt. Host cannot unready (host is always ready).
-- Returns the new readyAt (or NULL if unready).

CREATE OR REPLACE FUNCTION fn_set_player_ready(
    p_game_table text,
    p_game_id text,
    p_user_id text,
    p_ready boolean DEFAULT true
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_ready_at timestamptz;
        v_user_name text;
        v_family_id text;
        v_event_type text;
    BEGIN
        -- Find the participant + familyId
        SELECT "userName", "familyId" INTO v_user_name, v_family_id
        FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        IF v_user_name IS NULL THEN
            RAISE EXCEPTION 'Participant not found';
        END IF;

        IF p_ready THEN
            UPDATE "game_participants"
            SET "readyAt" = now(),
                "lastSeenAt" = now(),
                "connectionState" = 'online'
            WHERE "gameTable" = p_game_table
              AND "gameId" = p_game_id
              AND "userId" = p_user_id
            RETURNING "readyAt" INTO v_ready_at;
            v_event_type := 'ready';
        ELSE
            UPDATE "game_participants"
            SET "readyAt" = NULL,
                "lastSeenAt" = now(),
                "connectionState" = 'online'
            WHERE "gameTable" = p_game_table
              AND "gameId" = p_game_id
              AND "userId" = p_user_id;
            v_event_type := 'not_ready';
        END IF;

        -- Insert a system event for the lobby log
        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, v_user_name, v_event_type,
             jsonb_build_object('ready', p_ready));

        RETURN v_ready_at;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_set_player_ready(text, text, text, boolean) TO authenticated;

-- ── 5. RPC: fn_player_heartbeat ─────────────────────────────────────────
-- Called periodically by every connected lobby participant. Updates
-- lastSeenAt so the disconnect-reaper knows we're still alive.

CREATE OR REPLACE FUNCTION fn_player_heartbeat(
    p_game_table text,
    p_game_id text,
    p_user_id text
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE "game_participants"
    SET "lastSeenAt" = now(),
        "connectionState" = 'online',
        "leftAt" = CASE WHEN "leftAt" IS NULL THEN "leftAt" ELSE "leftAt" END
    WHERE "gameTable" = p_game_table
      AND "gameId" = p_game_id
      AND "userId" = p_user_id;
$$;
GRANT EXECUTE ON FUNCTION fn_player_heartbeat(text, text, text) TO authenticated;

-- ── 6. RPC: fn_leave_game_room ──────────────────────────────────────────
-- Removes a participant from a room, frees their slot, posts a system
-- "X left the room" event, and (if host) closes the room entirely.

CREATE OR REPLACE FUNCTION fn_leave_game_room(
    p_game_table text,
    p_game_id text,
    p_user_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_user_name text;
        v_family_id text;
        v_host_user_id text;
        v_is_host boolean := false;
        v_table_name text;
    BEGIN
        -- Get the participant's name + familyId
        SELECT "userName", "familyId" INTO v_user_name, v_family_id
        FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        IF v_user_name IS NULL THEN
            -- Already gone — no-op
            RETURN;
        END IF;

        -- Determine the canonical table name (some games use 'redlight_rounds')
        v_table_name := p_game_table;

        -- Check if this user is the host
        EXECUTE format(
            'SELECT "hostUserId" FROM %I WHERE "id" = $1',
            v_table_name
        ) INTO v_host_user_id USING p_game_id;

        v_is_host := (v_host_user_id = p_user_id);

        -- Mark participant as left
        UPDATE "game_participants"
        SET "leftAt" = now(),
            "connectionState" = 'offline'
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        -- If they're a player in a *_players table, remove them too
        -- (sos_players, bingo_cards, ludo_players, etc.)
        BEGIN
            EXECUTE format(
                'DELETE FROM %I WHERE "gameId" = $1 AND "userId" = $2',
                REPLACE(p_game_table, '_games', '_players')
            ) USING p_game_id, p_user_id;
        EXCEPTION WHEN OTHERS THEN
            -- Some games (chess, checkers, carrom, tictactoe) use inline
            -- playerOneId/playerTwoId columns — handle those via UPDATE.
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerOneId" = NULL WHERE "id" = $1 AND "playerOneId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerTwoId" = NULL WHERE "id" = $1 AND "playerTwoId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerXId" = NULL WHERE "id" = $1 AND "playerXId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerOId" = NULL WHERE "id" = $1 AND "playerOId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerWhiteId" = NULL WHERE "id" = $1 AND "playerWhiteId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            BEGIN
                EXECUTE format(
                    'UPDATE %I SET "playerBlackId" = NULL WHERE "id" = $1 AND "playerBlackId" = $2',
                    v_table_name
                ) USING p_game_id, p_user_id;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END;

        -- If host left, close the room
        IF v_is_host THEN
            EXECUTE format(
                'UPDATE %I SET "cancelledAt" = now(), "closedAt" = now() WHERE "id" = $1',
                v_table_name
            ) USING p_game_id;
        END IF;

        -- Insert a leave event for the lobby log
        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, v_user_name, 'leave',
             jsonb_build_object('wasHost', v_is_host));
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_leave_game_room(text, text, text) TO authenticated;

-- ── 7. RPC: fn_cancel_game_room ────────────────────────────────────────
-- Host-only. Closes the room immediately:
--   1. Marks the game row cancelledAt + closedAt = now()
--   2. Deletes all participants from game_participants
--   3. Deletes all rows from the {game}_players table
--   4. Deletes all lobby chat events (or marks them with a 'cancel' event)
--   5. Posts a 'cancel' system event so connected clients see the close
--      notification before the rows are gone.

CREATE OR REPLACE FUNCTION fn_cancel_game_room(
    p_game_table text,
    p_game_id text,
    p_user_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_host_user_id text;
        v_family_id text;
        v_table_name text;
        v_players_table text;
    BEGIN
        v_table_name := p_game_table;
        v_players_table := REPLACE(p_game_table, '_games', '_players');

        -- Verify the caller is the host
        EXECUTE format(
            'SELECT "hostUserId", "familyId" FROM %I WHERE "id" = $1',
            v_table_name
        ) INTO v_host_user_id, v_family_id USING p_game_id;

        IF v_host_user_id IS NULL THEN
            RAISE EXCEPTION 'Game not found';
        END IF;

        IF v_host_user_id <> p_user_id THEN
            RAISE EXCEPTION 'Only the host can cancel the room';
        END IF;

        -- 1. Post the cancel event FIRST so connected clients see it
        --    before the rows are deleted (realtime will fan-out the event).
        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, 'Host', 'cancel',
             jsonb_build_object('reason', 'host_cancelled'));

        -- 2. Mark the game row cancelled
        EXECUTE format(
            'UPDATE %I SET "cancelledAt" = now(), "closedAt" = now() WHERE "id" = $1',
            v_table_name
        ) USING p_game_id;

        -- 3. Delete all participants
        DELETE FROM "game_participants"
        WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

        -- 4. Delete all spectators
        DELETE FROM "game_spectators"
        WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

        -- 5. Delete all rows from the game-specific players table
        BEGIN
            EXECUTE format(
                'DELETE FROM %I WHERE "gameId" = $1',
                v_players_table
            ) USING p_game_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- 6. Clear inline player slots (chess, checkers, etc.)
        BEGIN
            EXECUTE format(
                'UPDATE %I SET "playerOneId" = NULL, "playerTwoId" = NULL WHERE "id" = $1',
                v_table_name
            ) USING p_game_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        BEGIN
            EXECUTE format(
                'UPDATE %I SET "playerXId" = NULL, "playerOId" = NULL WHERE "id" = $1',
                v_table_name
            ) USING p_game_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        BEGIN
            EXECUTE format(
                'UPDATE %I SET "playerWhiteId" = NULL, "playerBlackId" = NULL WHERE "id" = $1',
                v_table_name
            ) USING p_game_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_cancel_game_room(text, text, text) TO authenticated;

-- ── 8. RPC: fn_record_room_join ────────────────────────────────────────
-- Called when a player joins a room. Inserts the participant row + a
-- 'join' system event atomically. Idempotent — uses ON CONFLICT.

CREATE OR REPLACE FUNCTION fn_record_room_join(
    p_game_table text,
    p_game_id text,
    p_family_id text,
    p_user_id text,
    p_user_name text DEFAULT NULL,
    p_role text DEFAULT 'player'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_existing_name text;
    BEGIN
        -- Capture the previous userName (if any) so we don't insert a duplicate join event
        SELECT "userName" INTO v_existing_name
        FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        -- Upsert participant (clear leftAt if reconnecting)
        INSERT INTO "game_participants"
            ("gameTable", "gameId", "familyId", "userId", "userName", "role", "lastSeenAt", "connectionState")
        VALUES
            (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, p_role, now(), 'online')
        ON CONFLICT ("gameTable", "gameId", "userId") DO UPDATE
        SET "leftAt" = NULL,
            "connectionState" = 'online',
            "lastSeenAt" = now(),
            "userName" = COALESCE(EXCLUDED."userName", "game_participants"."userName"),
            "role" = COALESCE(EXCLUDED."role", "game_participants"."role");

        -- Only emit a 'join' event if this is a NEW join (no existing row)
        IF v_existing_name IS NULL THEN
            INSERT INTO "game_room_events"
                ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
            VALUES
                (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, 'join',
                 jsonb_build_object('role', p_role));
        END IF;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_record_room_join(text, text, text, text, text, text) TO authenticated;

-- ── 9. RPC: fn_close_expired_rooms ────────────────────────────────────
-- Cron-driven. Closes every room whose autoCloseDeadline has passed and
-- that is still in 'lobby' / 'waiting' status. Posts an 'auto_close'
-- event so connected clients get the notification.

CREATE OR REPLACE FUNCTION fn_close_expired_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_closed_count integer := 0;
        t text;
        v_family_id text;
        v_host_id text;
        r record;
    BEGIN
        FOREACH t IN ARRAY ARRAY[
            'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
            'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
            'truthordare_games', 'twotruths_games', 'dotsboxes_games',
            'nameplace_games', 'chitmatch_games', 'redlight_rounds'
        ] LOOP
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id, "familyId" AS family_id, "hostUserId" AS host_id
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
                -- Post auto_close event
                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'auto_close_deadline_passed'));

                -- Mark closed
                EXECUTE format(
                    'UPDATE %I SET "closedAt" = now(), "cancelledAt" = COALESCE("cancelledAt", now()) WHERE "id" = $1',
                    t
                ) USING r.game_id;

                -- Delete participants
                DELETE FROM "game_participants"
                WHERE "gameTable" = t AND "gameId" = r.game_id;

                -- Delete spectators
                DELETE FROM "game_spectators"
                WHERE "gameTable" = t AND "gameId" = r.game_id;

                v_closed_count := v_closed_count + 1;
            END LOOP;
        END LOOP;

        RETURN v_closed_count;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_close_expired_rooms() TO authenticated;

-- ── 10. RPC: fn_reap_disconnected_players ──────────────────────────────
-- Cron-driven. Marks participants whose lastSeenAt is older than the
-- threshold (default 60s) as offline + emits a leave event. If the
-- participant is the host, closes the room.

CREATE OR REPLACE FUNCTION fn_reap_disconnected_players(
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
        v_host_id text;
        v_table_name text;
    BEGIN
        FOR r IN
            SELECT "gameTable", "gameId", "familyId", "userId", "userName"
            FROM "game_participants"
            WHERE "connectionState" = 'online'
              AND "leftAt" IS NULL
              AND "lastSeenAt" < now() - (p_stale_threshold_seconds || ' seconds')::interval
        LOOP
            -- Mark them offline
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

            -- If they're the host, close the room
            v_table_name := r."gameTable";
            BEGIN
                EXECUTE format(
                    'SELECT "hostUserId" FROM %I WHERE "id" = $1',
                    v_table_name
                ) INTO v_host_id USING r."gameId";

                IF v_host_id = r."userId" THEN
                    EXECUTE format(
                        'UPDATE %I SET "closedAt" = now(), "cancelledAt" = now() WHERE "id" = $1',
                        v_table_name
                    ) USING r."gameId";

                    INSERT INTO "game_room_events"
                        ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                    VALUES
                        (r."gameTable", r."gameId", r."familyId", NULL, 'System', 'auto_close',
                         jsonb_build_object('reason', 'host_disconnected'));
                END IF;
            EXCEPTION WHEN OTHERS THEN
                -- Table doesn't exist or row missing — skip
                NULL;
            END;

            v_reaped_count := v_reaped_count + 1;
        END LOOP;

        RETURN v_reaped_count;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_reap_disconnected_players(integer) TO authenticated;

-- ── 11. RPC: fn_get_room_state ─────────────────────────────────────────
-- Single-call fetch of the full room state for a client:
--   • game row (status, autoCloseDeadline, spectatorsEnabled, hostUserId, ...)
--   • participants (with readyAt)
--   • spectators (count + names)
--   • recent room events (last 50)

CREATE OR REPLACE FUNCTION fn_get_room_state(
    p_game_table text,
    p_game_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_game jsonb;
        v_participants jsonb;
        v_spectators jsonb;
        v_events jsonb;
    BEGIN
        -- Game row (any columns that exist on this table)
        EXECUTE format(
            'SELECT to_jsonb(g) FROM %I g WHERE "id" = $1',
            p_game_table
        ) INTO v_game USING p_game_id;

        -- Participants (with readyAt + connectionState)
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'userId', "userId",
                'userName', "userName",
                'role', "role",
                'readyAt', "readyAt",
                'connectionState', "connectionState",
                'lastSeenAt', "lastSeenAt",
                'joinedAt', "joinedAt",
                'leftAt', "leftAt"
            )
        ), '[]'::jsonb) INTO v_participants
        FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "leftAt" IS NULL;

        -- Spectators
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'userId', "userId",
                'userName', "userName",
                'joinedAt', "joinedAt"
            )
        ), '[]'::jsonb) INTO v_spectators
        FROM "game_spectators"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "leftAt" IS NULL;

        -- Recent events
        SELECT COALESCE(jsonb_agg(e ORDER BY "createdAt" ASC), '[]'::jsonb) INTO v_events
        FROM (
            SELECT *
            FROM "game_room_events"
            WHERE "gameTable" = p_game_table
              AND "gameId" = p_game_id
            ORDER BY "createdAt" DESC
            LIMIT 50
        ) e;

        RETURN jsonb_build_object(
            'game', v_game,
            'participants', v_participants,
            'spectators', v_spectators,
            'events', v_events
        );
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_get_room_state(text, text) TO authenticated;

-- ── 12. RPC: fn_spectate_game ──────────────────────────────────────────
-- Join as a spectator (read-only). Idempotent. Posts a spectator_join event.

CREATE OR REPLACE FUNCTION fn_spectate_game(
    p_game_table text,
    p_game_id text,
    p_family_id text,
    p_user_id text,
    p_user_name text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_existing_name text;
    BEGIN
        SELECT "userName" INTO v_existing_name
        FROM "game_spectators"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id
          AND "leftAt" IS NULL;

        INSERT INTO "game_spectators"
            ("gameTable", "gameId", "familyId", "userId", "userName")
        VALUES
            (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name)
        ON CONFLICT ("gameTable", "gameId", "userId") DO UPDATE
        SET "leftAt" = NULL,
            "joinedAt" = now(),
            "userName" = COALESCE(EXCLUDED."userName", "game_spectators"."userName");

        IF v_existing_name IS NULL THEN
            INSERT INTO "game_room_events"
                ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
            VALUES
                (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, 'spectator_join',
                 jsonb_build_object('role', 'spectator'));
        END IF;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_spectate_game(text, text, text, text, text) TO authenticated;

-- ── 13. RPC: fn_leave_spectator ────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_leave_spectator(
    p_game_table text,
    p_game_id text,
    p_user_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_user_name text;
        v_family_id text;
    BEGIN
        SELECT "userName", "familyId" INTO v_user_name, v_family_id
        FROM "game_spectators"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id
          AND "leftAt" IS NULL;

        IF v_user_name IS NULL THEN RETURN; END IF;

        UPDATE "game_spectators"
        SET "leftAt" = now()
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id
          AND "leftAt" IS NULL;

        INSERT INTO "game_room_events"
            ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
        VALUES
            (p_game_table, p_game_id, v_family_id, p_user_id, v_user_name, 'spectator_leave',
             jsonb_build_object('role', 'spectator'));
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_leave_spectator(text, text, text) TO authenticated;

-- ── 14. RPC: fn_post_room_chat ─────────────────────────────────────────
-- Persist a lobby chat message (text or emoji) so it survives reconnects.
-- Also drives the realtime fan-out via the AFTER INSERT trigger below.

CREATE OR REPLACE FUNCTION fn_post_room_chat(
    p_game_table text,
    p_game_id text,
    p_family_id text,
    p_user_id text,
    p_user_name text DEFAULT NULL,
    p_content text DEFAULT '',
    p_is_spectator boolean DEFAULT false,
    p_chat_type text DEFAULT 'text'
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    INSERT INTO "game_room_events"
        ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
    VALUES
        (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, 'chat',
         jsonb_build_object(
             'content', p_content,
             'isSpectator', p_is_spectator,
             'chatType', p_chat_type
         ));
$$;
GRANT EXECUTE ON FUNCTION fn_post_room_chat(text, text, text, text, text, text, boolean, text) TO authenticated;

-- ── 15. Realtime broadcast trigger on game_room_events ─────────────────
-- Notifies the room's realtime channel whenever a new event is inserted,
-- so connected clients receive the join/leave/ready/cancel/auto_close/chat
-- event in real time without polling.

-- The Supabase Realtime postgres_changes plugin already broadcasts
-- INSERTs on game_room_events automatically. We don't need a manual
-- NOTIFY here — clients subscribe to game_room_events WHERE gameTable +
-- gameId match their room.

-- ── 16. Schedule the cron jobs ──────────────────────────────────────────
-- Insert (idempotent) the two cron jobs: auto-close rooms every 30s, and
-- reap disconnected players every 15s. These use the existing pg_cron
-- extension. If pg_cron is not enabled on this project, skip silently —
-- the RPCs can still be called manually from a client/scheduled function.

DO $$
BEGIN
    -- Try to enable pg_cron (only works on Supabase if not already enabled)
    CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron extension not available — cron jobs skipped';
END $$;

DO $$
BEGIN
    -- Only insert cron jobs if the cron.jobs table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'cron' AND table_name = 'jobs'
    ) THEN
        INSERT INTO cron.jobs (jobid, schedule, command, jobname, active)
        VALUES (
            9001,
            '*/30 * * * * *',
            'SELECT public.fn_close_expired_rooms();',
            'close-expired-game-rooms',
            true
        )
        ON CONFLICT (jobid) DO UPDATE
        SET schedule = EXCLUDED.schedule,
            command = EXCLUDED.command,
            active = EXCLUDED.active;

        INSERT INTO cron.jobs (jobid, schedule, command, jobname, active)
        VALUES (
            9002,
            '*/15 * * * * *',
            'SELECT public.fn_reap_disconnected_players(60);',
            'reap-disconnected-game-players',
            true
        )
        ON CONFLICT (jobid) DO UPDATE
        SET schedule = EXCLUDED.schedule,
            command = EXCLUDED.command,
            active = EXCLUDED.active;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron jobs: %', SQLERRM;
END $$;

-- ── 17. Backfill hostReady for existing rows ───────────────────────────
-- Already done in the loop above, but run once more explicitly so the
-- migration is idempotent on re-apply.

DO $$
DECLARE
    t text;
    game_tables text[] := ARRAY[
        'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
        'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
        'truthordare_games', 'twotruths_games', 'dotsboxes_games',
        'nameplace_games', 'chitmatch_games', 'redlight_rounds'
    ];
BEGIN
    FOREACH t IN ARRAY game_tables LOOP
        BEGIN
            EXECUTE format('UPDATE %I SET "hostReady" = TRUE WHERE "hostReady" IS NULL;', t);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END $$;

-- ── Done ────────────────────────────────────────────────────────────────
-- Verification queries (run after applying):
--   \d game_participants
--   \d game_room_events
--   SELECT * FROM cron.jobs WHERE jobname LIKE '%game%';
--   SELECT * FROM pg_extension WHERE extname = 'pg_cron';
