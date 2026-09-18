-- =============================================================================
-- Daxelo-Kinrel — Fix multiplayer RPC issues found in production testing
-- =============================================================================
-- 1. fn_close_expired_rooms: don't SELECT hostUserId (4 tables don't have it:
--    checkers_games, carrom_games, chess_games, tictactoe_games — they use
--    inline playerOneId/playerTwoId columns instead).
-- 2. fn_spectate_game: the existing game_spectators unique index is PARTIAL
--    (WHERE "leftAt" IS NULL), so ON CONFLICT can't use it without the
--    WHERE clause. Rewrite as SELECT-then-INSERT-or-UPDATE.
-- 3. fn_cancel_game_room: same hostUserId issue — only call it on tables
--    that have it (the 10 tables above). For the 4 inline-player tables,
--    the cancel just sets cancelledAt + clears the player columns.
-- 4. fn_leave_game_room: same hostUserId issue when checking if the leaving
--    user is the host.
-- =============================================================================

-- ── 1. Fix fn_close_expired_rooms ────────────────────────────────────────
-- Drop + recreate with a safer SELECT that doesn't reference hostUserId
-- (not all tables have it). We only need id + familyId + status for the
-- auto-close logic.

CREATE OR REPLACE FUNCTION fn_close_expired_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_closed_count integer := 0;
        t text;
        r record;
        v_has_host_user_id boolean;
    BEGIN
        FOREACH t IN ARRAY ARRAY[
            'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
            'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
            'truthordare_games', 'twotruths_games', 'dotsboxes_games',
            'nameplace_games', 'chitmatch_games', 'redlight_rounds'
        ] LOOP
            -- Check if this table has a hostUserId column
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = t
                  AND column_name = 'hostUserId'
            ) INTO v_has_host_user_id;

            -- Build the SELECT dynamically based on which columns exist.
            -- We need at minimum: id + familyId. hostUserId is optional.
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

-- ── 2. Fix fn_spectate_game ──────────────────────────────────────────────
-- Rewrite without ON CONFLICT (the unique index is partial).

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
        v_existing record;
    BEGIN
        -- Find any existing spectator row for this user (active OR left)
        SELECT * INTO v_existing
        FROM "game_spectators"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id
        LIMIT 1;

        IF v_existing IS NULL THEN
            -- New spectator — insert
            INSERT INTO "game_spectators"
                ("gameTable", "gameId", "familyId", "userId", "userName")
            VALUES
                (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name);

            -- Post spectator_join event
            INSERT INTO "game_room_events"
                ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
            VALUES
                (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, 'spectator_join',
                 jsonb_build_object('role', 'spectator'));
        ELSE
            -- Existing spectator — clear leftAt if they were left
            IF v_existing."leftAt" IS NOT NULL THEN
                UPDATE "game_spectators"
                SET "leftAt" = NULL,
                    "joinedAt" = now(),
                    "userName" = COALESCE(p_user_name, "userName")
                WHERE "id" = v_existing."id";

                -- Post spectator_join event (re-join)
                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (p_game_table, p_game_id, p_family_id, p_user_id, p_user_name, 'spectator_join',
                     jsonb_build_object('role', 'spectator'));
            END IF;
            -- If they're already an active spectator, no-op (no duplicate event)
        END IF;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_spectate_game(text, text, text, text, text) TO authenticated;

-- ── 3. Fix fn_leave_game_room ───────────────────────────────────────────
-- Some tables (checkers, carrom, chess, tictactoe) don't have hostUserId.
-- For those, we can't determine host status from the game row, so we
-- check the game_participants table's role column instead.

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
        v_has_host_user_id boolean;
        v_participant_role text;
    BEGIN
        -- Get the participant's name + familyId + role
        SELECT "userName", "familyId", "role" INTO v_user_name, v_family_id, v_participant_role
        FROM "game_participants"
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        IF v_user_name IS NULL THEN
            -- Already gone — no-op
            RETURN;
        END IF;

        v_table_name := p_game_table;

        -- Determine if this user is the host.
        -- Method 1: check the participant's role column (most reliable)
        IF v_participant_role = 'host' THEN
            v_is_host := true;
        ELSE
            -- Method 2: check the game row's hostUserId column (if it exists)
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = v_table_name
                  AND column_name = 'hostUserId'
            ) INTO v_has_host_user_id;

            IF v_has_host_user_id THEN
                BEGIN
                    EXECUTE format(
                        'SELECT "hostUserId" FROM %I WHERE "id" = $1',
                        v_table_name
                    ) INTO v_host_user_id USING p_game_id;
                    IF v_host_user_id = p_user_id THEN
                        v_is_host := true;
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
        END IF;

        -- Mark participant as left
        UPDATE "game_participants"
        SET "leftAt" = now(),
            "connectionState" = 'offline'
        WHERE "gameTable" = p_game_table
          AND "gameId" = p_game_id
          AND "userId" = p_user_id;

        -- If they're a player in a *_players table, remove them too
        BEGIN
            EXECUTE format(
                'DELETE FROM %I WHERE "gameId" = $1 AND "userId" = $2',
                REPLACE(p_game_table, '_games', '_players')
            ) USING p_game_id, p_user_id;
        EXCEPTION WHEN OTHERS THEN
            -- Inline-player games (chess, checkers, carrom, tictactoe)
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

-- ── 4. Fix fn_cancel_game_room ──────────────────────────────────────────
-- Same hostUserId issue — check via game_participants.role OR the game row.

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
        v_has_host_user_id boolean;
        v_participant_role text;
        v_is_host boolean := false;
    BEGIN
        v_table_name := p_game_table;
        v_players_table := REPLACE(p_game_table, '_games', '_players');

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

        -- 1. Post the cancel event FIRST so connected clients see it
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

-- ── 5. Fix fn_reap_disconnected_players ─────────────────────────────────
-- Same hostUserId issue when checking if the disconnected user is the host.

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
        v_host_user_id text;
        v_table_name text;
        v_has_host_user_id boolean;
        v_participant_role text;
    BEGIN
        FOR r IN
            SELECT "gameTable", "gameId", "familyId", "userId", "userName", "role"
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

            -- If they're the host (by role), close the room
            v_table_name := r."gameTable";
            IF r."role" = 'host' THEN
                EXECUTE format(
                    'UPDATE %I SET "closedAt" = now(), "cancelledAt" = now() WHERE "id" = $1',
                    v_table_name
                ) USING r."gameId";

                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (r."gameTable", r."gameId", r."familyId", NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'host_disconnected'));
            ELSE
                -- Also check via game row's hostUserId column (for older
                -- participant rows that might not have role='host')
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = v_table_name
                      AND column_name = 'hostUserId'
                ) INTO v_has_host_user_id;

                IF v_has_host_user_id THEN
                    BEGIN
                        EXECUTE format(
                            'SELECT "hostUserId" FROM %I WHERE "id" = $1',
                            v_table_name
                        ) INTO v_host_user_id USING r."gameId";

                        IF v_host_user_id = r."userId" THEN
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
                        NULL;
                    END;
                END IF;
            END IF;

            v_reaped_count := v_reaped_count + 1;
        END LOOP;

        RETURN v_reaped_count;
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_reap_disconnected_players(integer) TO authenticated;
