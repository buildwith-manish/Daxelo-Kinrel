-- =============================================================================
-- Daxelo-Kinrel — Fix room-expiry sweep + orphaned chat cards + abandoned-in-progress
-- =============================================================================
-- ROOT CAUSE DIAGNOSIS (2026-10-04):
--
-- A room created on September 13th was still showing "LIVE NOW" today (Oct 4).
-- Investigation revealed THREE root causes:
--
-- 1. fn_sweep_expired_game_rooms() FAILS ON EVERY RUN
--    The function iterates over ALL game tables including ghost_painter_rounds,
--    but ghost_painter_rounds does NOT have cancelledAt/closedAt columns.
--    Every run fails with "ERROR: column "cancelledAt" does not exist" — the
--    entire function call is a single transaction, so NO rooms get swept from
--    ANY table. The cron job has been failing silently for 21+ days.
--
-- 2. fn_close_expired_rooms() DELETES game rows WITHOUT updating ChatMessage
--    The autoCloseDeadline-based sweep (runs every 30s) calls fn__hard_delete_room
--    which DELETEs the game row entirely. But it does NOT update the corresponding
--    ChatMessage rows. The AFTER UPDATE trigger never fires (it's a DELETE, not
--    UPDATE), so gameInviteStatus stays at 'pending' or 'accepted' forever.
--    Result: 21 orphaned ChatMessage rows showing "Waiting for players" or
--    "LIVE NOW" for game rooms that no longer exist.
--
-- 3. No abandoned-in-progress detection
--    Per the original design, in-progress rooms have expiresAt=NULL and are
--    NEVER swept. This is correct for actively-running games, but there's no
--    mechanism to detect an abandoned in-progress game (no player activity for
--    an extended period). A room that entered in-progress but then had no
--    activity stays "LIVE NOW" indefinitely.
--
-- FIX:
--   A. Recreate fn_sweep_expired_game_rooms to skip ghost_painter_rounds and
--      handle tables without cancelledAt/closedAt gracefully.
--   B. Add fn_cleanup_orphaned_chat_invites: transitions ChatMessage rows
--      whose gameId no longer exists in ANY game table to 'expired'.
--   C. Add abandoned-in-progress detection: in-progress rooms with no
--      lastActivityAt bump for 45 min → transition to expired.
--   D. Run a one-time cleanup of all existing stale ChatMessage rows.
-- =============================================================================

-- ── A. Recreate fn_sweep_expired_game_rooms ───────────────────────────────
-- Skip ghost_painter_rounds entirely (no cancelledAt/closedAt/lastActivityAt
-- columns — it uses a different lifecycle model). For all other tables,
-- check both pre-game expiry (expiresAt) AND abandoned-in-progress
-- (lastActivityAt older than 45 min).
CREATE OR REPLACE FUNCTION public.fn_sweep_expired_game_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_swept_count integer := 0;
    t text;
    r record;
    v_terminal_status text;
    v_unified_status text := 'expired';
    v_has_cancelled_col boolean;
    v_has_last_activity_col boolean;
BEGIN
    -- Tables that participate in the temporary-room lifecycle.
    -- ghost_painter_rounds is EXCLUDED: it lacks cancelledAt, closedAt,
    -- and lastActivityAt columns (different lifecycle model).
    FOREACH t IN ARRAY ARRAY[
        'chess_games', 'checkers_games', 'carrom_games', 'tictactoe_games',
        'flick_arena_games',
        'bingo_games', 'sos_games', 'ludo_games', 'antakshari_games',
        'chitmatch_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'tugofwar_games', 'memorymatch_games', 'ashta_chamma_games',
        'connect4_games', 'impostor_games', 'color_trap_games',
        'freeze_auction_games', 'secret_heist_games', 'mind_match_games',
        'word_forge_games', 'code_clues_games', 'night_falls_games',
        'sketch_telephone_games', 'stickman_heist_games',
        'crystal_bridge_games'
    ] LOOP
        -- Pick the terminal status for this table's vocabulary.
        v_terminal_status := CASE t
            WHEN 'tugofwar_games' THEN 'cancelled'
            WHEN 'memorymatch_games' THEN 'cancelled'
            WHEN 'ashta_chamma_games' THEN 'cancelled'
            WHEN 'connect4_games' THEN 'cancelled'
            WHEN 'impostor_games' THEN 'cancelled'
            WHEN 'color_trap_games' THEN 'cancelled'
            WHEN 'freeze_auction_games' THEN 'cancelled'
            WHEN 'secret_heist_games' THEN 'cancelled'
            WHEN 'mind_match_games' THEN 'cancelled'
            WHEN 'word_forge_games' THEN 'cancelled'
            WHEN 'code_clues_games' THEN 'cancelled'
            WHEN 'night_falls_games' THEN 'cancelled'
            WHEN 'sketch_telephone_games' THEN 'cancelled'
            WHEN 'stickman_heist_games' THEN 'cancelled'
            WHEN 'crystal_bridge_games' THEN 'cancelled'
            ELSE 'expired'
        END;

        -- Check which columns this table has (defensive — all tables in
        -- the list above have lastActivityAt + cancelledAt + closedAt, but
        -- guard against future schema drift).
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = t
              AND column_name = 'cancelledAt'
        ) INTO v_has_cancelled_col;
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = t
              AND column_name = 'lastActivityAt'
        ) INTO v_has_last_activity_col;

        -- ── A.1: Pre-game expiry (expiresAt-based, 15-min inactivity) ──
        IF v_has_cancelled_col THEN
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id, "familyId" AS family_id
                 FROM %I
                 WHERE "expiresAt" IS NOT NULL
                   AND "expiresAt" <= now()
                   AND COALESCE("cancelledAt", now() + interval ''1 second'') > now()
                   AND COALESCE("closedAt", now() + interval ''1 second'') > now()
                   AND (
                       "status" IN (''waiting'', ''lobby'', ''setup'', ''countdown'',
                                    ''drawing'', ''guessing'', ''open'')
                       OR "status" IS NULL
                   )
                 FOR UPDATE SKIP LOCKED',
                t
            ) LOOP
                EXECUTE format(
                    'UPDATE %I
                     SET "status" = $1,
                         "cancelledAt" = COALESCE("cancelledAt", now()),
                         "closedAt" = COALESCE("closedAt", now()),
                         "lastActivityAt" = now()
                     WHERE "id" = $2',
                    t
                ) USING v_terminal_status, r.game_id;

                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'expired', 'expiredAt', now(),
                                        'unifiedStatus', v_unified_status));

                PERFORM public.fn_sync_game_invite_status(
                    t, r.game_id, v_terminal_status, NULL, NULL
                );
                v_swept_count := v_swept_count + 1;
            END LOOP;
        END IF;

        -- ── A.2: Abandoned in-progress detection (45-min no activity) ──
        -- In-progress rooms have expiresAt=NULL (never expire on the pre-game
        -- timer). But if an in-progress room has had NO lastActivityAt bump
        -- for 45 minutes, it's abandoned — transition to expired.
        -- 45 min is longer than the 15-min pre-game window (actual games may
        -- have natural pauses) but still bounded.
        IF v_has_last_activity_col AND v_has_cancelled_col THEN
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id, "familyId" AS family_id
                 FROM %I
                 WHERE "status" IN (''in_progress'', ''active'')
                   AND "lastActivityAt" IS NOT NULL
                   AND "lastActivityAt" < now() - interval ''45 minutes''
                   AND COALESCE("cancelledAt", now() + interval ''1 second'') > now()
                   AND COALESCE("closedAt", now() + interval ''1 second'') > now()
                 FOR UPDATE SKIP LOCKED',
                t
            ) LOOP
                EXECUTE format(
                    'UPDATE %I
                     SET "status" = $1,
                         "cancelledAt" = COALESCE("cancelledAt", now()),
                         "closedAt" = COALESCE("closedAt", now()),
                         "lastActivityAt" = now()
                     WHERE "id" = $2',
                    t
                ) USING v_terminal_status, r.game_id;

                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'abandoned_in_progress',
                                        'expiredAt', now(),
                                        'unifiedStatus', v_unified_status));

                PERFORM public.fn_sync_game_invite_status(
                    t, r.game_id, v_terminal_status, NULL, NULL
                );
                v_swept_count := v_swept_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RETURN v_swept_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sweep_expired_game_rooms() TO authenticated;

-- ── B. fn_cleanup_orphaned_chat_invites ───────────────────────────────────
-- Transitions ChatMessage rows whose gameId no longer exists in ANY game
-- table to 'expired'. This handles the case where fn_close_expired_rooms
-- (or fn_cleanup_completed_games) hard-deleted the game row without updating
-- the ChatMessage. Called by the sweep cron job every 5 min.
CREATE OR REPLACE FUNCTION public.fn_cleanup_orphaned_chat_invites()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cleaned_count integer := 0;
    v_row_count integer;
    v_game_id text;
    v_table_exists boolean;
    t text;
BEGIN
    -- Find all gameInvite ChatMessage rows that are NOT in a terminal state
    -- (i.e., still 'pending', 'in_progress', 'accepted', 'active').
    -- For each, check if the referenced game row still exists in ANY game
    -- table. If not, transition to 'expired'.
    FOR v_game_id IN
        SELECT DISTINCT "gameId"
        FROM "ChatMessage"
        WHERE "messageType" = 'gameInvite'
          AND "gameId" IS NOT NULL
          AND "gameInviteStatus" IN ('pending', 'in_progress', 'accepted', 'active')
    LOOP
        v_table_exists := false;

        -- Check each game table to see if this gameId still exists
        FOREACH t IN ARRAY ARRAY[
            'chess_games', 'checkers_games', 'carrom_games', 'tictactoe_games',
            'flick_arena_games',
            'bingo_games', 'sos_games', 'ludo_games', 'antakshari_games',
            'chitmatch_games', 'dotsboxes_games', 'nameplace_games',
            'truthordare_games', 'twotruths_games', 'redlight_rounds',
            'tugofwar_games', 'memorymatch_games', 'ashta_chamma_games',
            'connect4_games', 'impostor_games', 'color_trap_games',
            'freeze_auction_games', 'secret_heist_games', 'mind_match_games',
            'word_forge_games', 'code_clues_games', 'night_falls_games',
            'sketch_telephone_games', 'stickman_heist_games',
            'crystal_bridge_games', 'ghost_painter_rounds'
        ] LOOP
            BEGIN
                EXECUTE format(
                    'SELECT EXISTS (SELECT 1 FROM %I WHERE "id" = $1)',
                    t
                ) INTO v_table_exists USING v_game_id;
            EXCEPTION WHEN OTHERS THEN
                v_table_exists := false;
            END;

            IF v_table_exists THEN
                EXIT; -- Found in this table — not orphaned
            END IF;
        END LOOP;

        -- If the game row doesn't exist in ANY table, the ChatMessage is orphaned
        IF NOT v_table_exists THEN
            UPDATE "ChatMessage"
            SET "gameInviteStatus" = 'expired'
            WHERE "messageType" = 'gameInvite'
              AND "gameId" = v_game_id
              AND "gameInviteStatus" IN ('pending', 'in_progress', 'accepted', 'active');

            GET DIAGNOSTICS v_row_count = ROW_COUNT;
            v_cleaned_count := v_cleaned_count + v_row_count;
        END IF;
    END LOOP;

    RETURN v_cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cleanup_orphaned_chat_invites() TO authenticated;

COMMENT ON FUNCTION public.fn_cleanup_orphaned_chat_invites() IS
'Transitions ChatMessage game-invite rows whose gameId no longer exists in ANY
game table to the expired state. Handles the orphan case where fn_close_expired_rooms
or fn_cleanup_completed_games hard-deleted the game row without updating the
ChatMessage. Called by the sweep cron job every 5 min.';

-- ── C. Update the cron job to also call the orphan cleanup ────────────────
-- Reschedule the sweep job to call BOTH functions in sequence.
SELECT cron.unschedule('sweep-expired-game-rooms-lifecycle');
SELECT cron.schedule(
    'sweep-expired-game-rooms-lifecycle',
    '*/5 * * * *',  -- every 5 minutes
    $$
        SELECT public.fn_sweep_expired_game_rooms();
        SELECT public.fn_cleanup_orphaned_chat_invites();
    $$
);

-- ── D. One-time cleanup of all existing stale ChatMessage rows ────────────
-- Run the orphan cleanup immediately to fix the 21 existing stale cards
-- (4 showing "LIVE NOW" via 'accepted' status, 17 showing "Waiting for players"
-- via 'pending' status — all with deleted game rows).
SELECT public.fn_cleanup_orphaned_chat_invites() AS orphaned_cards_cleaned;
