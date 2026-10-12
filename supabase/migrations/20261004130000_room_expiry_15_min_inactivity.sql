-- =============================================================================
-- Daxelo-Kinrel — 15-minute inactivity-based room expiry
-- =============================================================================
-- Replaces the prior 30-minute creation-time-based expiry with a 15-minute
-- INACTIVITY-based expiry per the user-facing spec:
--
--   "If no one joins the room, or if the host goes offline, the room should
--    automatically expire after 15 minutes."
--
-- Mechanism:
--   • fn_touch_game_activity (called on every lobby action — join, ready
--     toggle, heartbeat, etc.) now ALSO refreshes expiresAt = now() + 15 min
--     for pre-game rooms. So any activity resets the 15-min countdown.
--   • fn_sweep_expired_game_rooms (pg_cron every 5 min) transitions rooms
--     past their expiresAt to the terminal 'expired'/'cancelled' status.
--   • The existing AFTER UPDATE OF status, expiresAt trigger fans out the
--     status change to chat-invite cards via fn_sync_game_invite_status.
--   • In-progress rooms NEVER expire (expiresAt is NULL) — they complete
--     naturally.
--
-- Result: a room that sees NO activity for 15 minutes automatically closes.
-- The host going offline (no heartbeats) → no lastActivityAt bumps → no
-- expiresAt refreshes → room expires after 15 min.
--
-- Companion Flutter changes:
--   • game_invite_status_chip.dart: "Expired" → "Closed • Expired" with
--     a door icon (clearer "this room is closed" semantics per spec)
--   • message_bubble.dart: action button label "Expired" → "Closed • Expired"
-- =============================================================================

-- ── 1. Recreate fn_touch_game_activity to also refresh expiresAt ──────────
-- The function now bumps lastActivityAt AND refreshes expiresAt for pre-game
-- rooms. This makes the 15-min expiry INACTIVITY-based: any lobby action
-- (join, ready, heartbeat, etc.) resets the countdown.
--
-- For rooms already in_progress / completed / cancelled, we leave expiresAt
-- alone (in_progress rooms have expiresAt = NULL — never expire; completed/
-- cancelled rooms are already terminal).
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(
    p_game_table text,
    p_game_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_status text;
    v_is_pre_game boolean;
    v_has_last_activity_col boolean;
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games',
        'dotsboxes_games','nameplace_games','truthordare_games','twotruths_games',
        'redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games',
        'tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds',
        'connect4_games','impostor_games','color_trap_games','freeze_auction_games',
        'flick_arena_games','secret_heist_games','mind_match_games','code_clues_games',
        'night_falls_games','sketch_telephone_games','word_forge_games','stickman_heist_games',
        'crystal_bridge_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    -- Check whether this table has a lastActivityAt column (ghost_painter_rounds
    -- doesn't — it uses a different lifecycle model). For tables without the
    -- column, we silently no-op (the caller's heartbeat is best-effort anyway).
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = p_game_table
          AND column_name = 'lastActivityAt'
    ) INTO v_has_last_activity_col;

    IF NOT v_has_last_activity_col THEN
        -- Table doesn't participate in the temporary-room lifecycle (e.g.
        -- ghost_painter_rounds). Nothing to bump.
        RETURN;
    END IF;

    -- Read the current status so we know whether to refresh expiresAt.
    -- Pre-game statuses get the 15-min refresh; in_progress / terminal
    -- statuses are left alone (in_progress has NULL expiresAt, terminal
    -- is already closed).
    EXECUTE format(
        'SELECT "status" FROM public.%I WHERE "id" = $1',
        p_game_table
    ) INTO v_current_status USING p_game_id;

    v_is_pre_game := v_current_status IS NULL
        OR v_current_status IN (
            'waiting', 'lobby', 'setup', 'countdown',
            'drawing', 'guessing', 'open'
        );

    -- Bump lastActivityAt + refresh expiresAt (15 min from now) for
    -- pre-game rooms. The 15-min window is the inactivity timeout per
    -- the user-facing spec.
    IF v_is_pre_game THEN
        EXECUTE format(
            'UPDATE public.%I
             SET "lastActivityAt" = now(),
                 "expiresAt" = now() + interval ''15 minutes''
             WHERE "id" = $1',
            p_game_table
        ) USING p_game_id;
    ELSE
        -- In-progress / terminal: just bump lastActivityAt (no expiresAt
        -- refresh — in_progress rooms have NULL expiresAt, terminal rooms
        -- are already closed).
        EXECUTE format(
            'UPDATE public.%I
             SET "lastActivityAt" = now()
             WHERE "id" = $1',
            p_game_table
        ) USING p_game_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated;

COMMENT ON FUNCTION public.fn_touch_game_activity(text, text) IS
'Bumps lastActivityAt on the game room AND refreshes expiresAt = now() + 15 min
for pre-game rooms. Called on every lobby action (join, ready toggle, heartbeat,
etc.) so the 15-min inactivity timeout resets whenever there is activity.

For in-progress / terminal rooms, only lastActivityAt is bumped (expiresAt is
NULL for in_progress, already in the past for terminal).';

-- ── 2. Backfill: refresh expiresAt on existing pre-game rooms ─────────────
-- Existing waiting rooms had expiresAt = createdAt + 30 min (from the prior
-- migration). Re-set to COALESCE(lastActivityAt, createdAt) + 15 min so the
-- 15-min inactivity window applies immediately. Rooms that are already past
-- the new 15-min window will be swept on the next cron tick (within 5 min).
--
-- NOTE: ghost_painter_rounds is EXCLUDED from this backfill because it lacks
-- both lastActivityAt AND cancelledAt columns (it uses a different lifecycle
-- model — drawing/guessing/completed without the temporary-room lifecycle).
-- It's still covered by the AFTER UPDATE trigger + sweep for the tables that
-- DO have the columns; ghost_painter_rounds simply won't get the 15-min
-- inactivity refresh. This is acceptable because ghost_painter_rounds rooms
-- are short-lived drawing rounds, not persistent lobby rooms.
DO $$
DECLARE
    t text;
BEGIN
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
        -- ghost_painter_rounds excluded: no lastActivityAt / cancelledAt columns
    ] LOOP
        -- Pre-game rooms: expiresAt = COALESCE(lastActivityAt, createdAt) + 15 min.
        -- Use COALESCE so rooms that never had lastActivityAt bumped (legacy)
        -- fall back to createdAt. Filter out already-cancelled/closed rooms.
        EXECUTE format(
            'UPDATE %I
             SET "expiresAt" = COALESCE("lastActivityAt", "createdAt") + interval ''15 minutes''
             WHERE (
                   "status" IN (''waiting'', ''lobby'', ''setup'', ''countdown'',
                                ''drawing'', ''guessing'', ''open'')
                   OR "status" IS NULL
               )
               AND "cancelledAt" IS NULL
               AND "closedAt" IS NULL',
            t
        );
        -- In-progress rooms: clear expiresAt so they're never swept.
        EXECUTE format(
            'UPDATE %I
             SET "expiresAt" = NULL
             WHERE "status" IN (''in_progress'', ''active'')',
            t
        );
    END LOOP;
END $$;

-- ── 3. Documentation comment on the sweep function ────────────────────────
-- The fn_sweep_expired_game_rooms function is unchanged — it still uses
-- expiresAt to find rooms to sweep. But now expiresAt is refreshed on every
-- lobby action (by fn_touch_game_activity), so the sweep effectively enforces
-- a 15-min INACTIVITY timeout instead of a 30-min creation-time timeout.
COMMENT ON FUNCTION public.fn_sweep_expired_game_rooms() IS
'Sweeps pre-game rooms past their expiresAt deadline every 5 min (pg_cron).

With the 20261004130000 migration, expiresAt is now refreshed on every lobby
action by fn_touch_game_activity (15-min window). So this sweep enforces a
15-min INACTIVITY timeout: a room that sees no activity for 15 min gets
transitioned to expired/cancelled.

In-progress rooms have expiresAt = NULL and are never swept. Terminal rooms
(expired/cancelled/completed) are already closed and skipped by the
cancelledAt/closedAt IS NULL filter.';
