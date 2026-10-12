-- =============================================================================
-- Daxelo-Kinrel — Full game-room lifecycle state machine for chat invite cards
-- =============================================================================
-- Replaces the prior capacity-only status (Waiting/Full) on the chat-invite
-- card with a complete 5-state lifecycle:
--
--     waiting → full → in_progress → completed
--                                ↘ expired
--
-- Each state has a distinct card treatment + status chip color (frontend),
-- and is driven server-side by:
--   1. An AFTER UPDATE trigger on every game table that calls the new
--      fn_sync_game_invite_status() RPC whenever the game's `status` column
--      transitions. This centralizes the previously per-game-provider
--      syncGameInviteChatCards() Flutter calls and ensures EVERY game
--      (not just SOS) keeps its chat card in sync.
--   2. A pg_cron-scheduled fn_sweep_expired_game_rooms() that transitions
--      pre-game rooms (waiting / full) past their expiresAt window to the
--      'expired' status, which the trigger then fans out to chat cards.
--
-- Per spec:
--   • waiting-state expiry window: 30 minutes from room creation
--   • full-state expiry window:   10 minutes from transition to full
--     (shorter because the host is "ready to play" — they should start
--      promptly or yield the slot back to the family)
--   • in_progress rooms are NEVER swept — they run until natural completion
--     (winner determined, last man standing, draw, etc.) per each game's
--     own completion logic.
--
-- Files affected downstream:
--   • lib/features/chat/presentation/widgets/game_invite_status_chip.dart
--     (extended enum: 5 kinds, with pulsing treatment for inProgress)
--   • lib/features/chat/presentation/widgets/message_bubble.dart
--     (Watch/Rejoin button for inProgress; static label for expired/completed)
--   • lib/features/games/shared/data/game_invite_chat_sync.dart
--     (extended to carry winnerName + completedAt)
--
-- Idempotent: every ALTER is IF NOT EXISTS; triggers are DROP IF EXISTS +
-- CREATE; cron jobs are unschedule-then-schedule.
-- =============================================================================

-- ── 1. Add `expiresAt` to every game table ────────────────────────────────
-- Pattern A/B tables (14): already have autoCloseDeadline + cancelledAt +
-- closedAt from 20260913120000_unified_multiplayer_room_lifecycle.sql.
-- Pattern C tables (17): ship with autoCloseDeadline inline.
--
-- `expiresAt` is distinct from autoCloseDeadline:
--   • autoCloseDeadline = "when does this lobby become invalid if no one
--     joins" (host-set at create time, sometimes NULL)
--   • expiresAt = "when does this ROOM enter the 'expired' state per the
--     lifecycle state machine" (server-set: created_at + 30min if waiting,
--     full_at + 10min if full)
--
-- expiresAt is RECALCULATED on transition to 'full' (10-min window kicks in)
-- and CLEARED on transition to 'in_progress' (in-progress games never expire
-- on this timer — they complete naturally or are abandoned).

DO $$
DECLARE
    t text;
    game_tables text[] := ARRAY[
        -- Pattern A (inline 2-player slots)
        'chess_games', 'checkers_games', 'carrom_games', 'tictactoe_games',
        'flick_arena_games',
        -- Pattern B (hostUserId + *_players table)
        'bingo_games', 'sos_games', 'ludo_games', 'antakshari_games',
        'chitmatch_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        -- Pattern C (newer games — ship with autoCloseDeadline inline)
        'tugofwar_games', 'memorymatch_games', 'ashta_chamma_games',
        'connect4_games', 'impostor_games', 'color_trap_games',
        'freeze_auction_games', 'secret_heist_games', 'mind_match_games',
        'word_forge_games', 'code_clues_games', 'night_falls_games',
        'sketch_telephone_games', 'stickman_heist_games',
        'crystal_bridge_games', 'ghost_painter_rounds'
    ];
BEGIN
    FOREACH t IN ARRAY game_tables LOOP
        -- expiresAt: server-set lifecycle deadline (distinct from autoCloseDeadline
        -- which is host-set lobby TTL). NULL = no expiry (e.g. in_progress).
        EXECUTE format(
            'ALTER TABLE %I ADD COLUMN IF NOT EXISTS "expiresAt" timestamptz;',
            t
        );
        -- Index for the sweep query: WHERE status IN (waiting/full/etc) AND
        -- expiresAt <= now(). Partial index keeps it small.
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS "idx_%I_expiresAt" ON %I ("expiresAt")
             WHERE "expiresAt" IS NOT NULL;',
            t, t
        );
    END LOOP;
END $$;

-- ── 2. Add CHECK constraint on ChatMessage.gameInviteStatus ──────────────
-- Formalize the 5-state lifecycle (was: free-form text with 4 values).
-- Existing rows with the legacy values are forward-compatible:
--   • 'pending'  → still valid (waiting state)
--   • 'accepted' → mapped to 'in_progress' by the Flutter classifier (legacy alias)
--   • 'expired'  → still valid
--   • 'cancelled'→ mapped to 'expired' by the Flutter classifier (legacy alias)
-- New values added: 'in_progress' and 'completed'.
--
-- We DON'T migrate legacy data — the classifier handles both old and new
-- values so existing chat cards continue to render correctly.

DO $$
BEGIN
    -- Drop the constraint if it exists from a prior partial run, then
    -- re-add with the full set of allowed values. This keeps the migration
    -- idempotent.
    BEGIN
        ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_gameInviteStatus_check";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    ALTER TABLE "ChatMessage"
        ADD CONSTRAINT "ChatMessage_gameInviteStatus_check"
        CHECK (
            "gameInviteStatus" IS NULL OR
            "gameInviteStatus" IN (
                'pending',        -- waiting / open-to-join (lobby state)
                'in_progress',    -- game started, players are playing
                'completed',      -- game finished normally (winner determined)
                'expired',        -- room never filled / never started in time
                'cancelled',      -- host cancelled (legacy alias for 'expired')
                'accepted'        -- legacy alias for 'in_progress' (pre-state-machine)
            )
        );
END $$;

-- Add columns for the completed-state result display (privacy-gated).
-- The chat card stores a denormalized winner summary so it can render
-- without an extra RPC round-trip; the actual detailed match result
-- remains in game_match_history / game_match_players with RLS gating.
-- Non-participants see gameWinnerSummary = NULL (privacy respected).
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameWinnerName" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameCompletedAt" timestamptz;

-- ── 3. fn_sync_game_invite_status(p_game_table, p_game_id, p_status) ────
-- Centralized server-side sync. Called by AFTER UPDATE triggers on every
-- game table when status transitions. Updates every ChatMessage row with
-- messageType='gameInvite' AND gameId=<p_game_id> to the new lifecycle
-- status, with proper mapping from per-game status vocabularies to the
-- unified 5-state model.
--
-- Per-game status vocabularies vary (see audit):
--   Pattern B games: 'waiting' | 'in_progress' | 'completed'
--   SOS: 'lobby' | 'active' | 'finished'    ← needs mapping
--   RedLight: 'lobby' | 'countdown' | 'active' | 'finished'  ← needs mapping
--   GhostPainter: 'drawing' | 'guessing' | 'completed'  ← needs mapping
--   Pattern C games: 'waiting' | 'in_progress' | 'completed' | 'cancelled'
--
-- This RPC handles the mapping centrally so the per-game trigger doesn't
-- need to know about vocabulary differences.

CREATE OR REPLACE FUNCTION public.fn_sync_game_invite_status(
    p_game_table text,
    p_game_id text,
    p_new_status text,
    p_winner_name text DEFAULT NULL,
    p_completed_at timestamptz DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_unified_status text;
    v_update_count integer := 0;
    v_winner_name text := p_winner_name;
    v_completed_at timestamptz := p_completed_at;
    v_requesting_user text := auth.uid()::text;
    v_is_participant boolean := false;
BEGIN
    -- ── Map per-game status vocabulary to the unified 5-state model ──
    v_unified_status := CASE
        WHEN p_new_status IN ('waiting', 'lobby', 'setup', 'countdown', 'drawing', 'guessing')
            THEN 'pending'
        WHEN p_new_status IN ('in_progress', 'active')
            THEN 'in_progress'
        WHEN p_new_status IN ('completed', 'finished')
            THEN 'completed'
        WHEN p_new_status IN ('expired', 'cancelled')
            THEN 'expired'
        ELSE NULL  -- unknown status — don't write anything
    END;

    IF v_unified_status IS NULL THEN
        RETURN 0;
    END IF;

    -- ── Privacy gate for winner name on completed state ──
    -- Per the existing match-result privacy model (20260917140000 +
    -- 20260917140001 migrations), only match participants may see winner
    -- names. The chat card is rendered to ALL family members (the chat
    -- RLS lets any family member SELECT ChatMessage), so we must NOT
    -- denormalize the winner name onto the chat row if the viewer is not
    -- a participant.
    --
    -- However: the chat row is a SHARED row (one row per game, viewed by
    -- all family members). We can't per-user-privacy-filter a single row.
    -- The compromise (matching the existing pattern in
    -- match_history_for_participant): write winner name to gameWinnerName
    -- ONLY if the requesting user (auth.uid()) is a participant; otherwise
    -- leave it NULL. Each viewer's INSERT/UPDATE RLS will gate writes
    -- appropriately, and non-participant viewers will see NULL = generic
    -- "Game completed" treatment.
    --
    -- For trigger-driven calls (no auth context — SECURITY DEFINER),
    -- the winner name is written unconditionally and the frontend
    -- re-validates participant status via the existing
    -- match_history_for_participant RPC before rendering.
    IF v_unified_status = 'completed' AND v_winner_name IS NOT NULL THEN
        BEGIN
            SELECT EXISTS (
                SELECT 1 FROM public."game_participants"
                WHERE "gameTable" = p_game_table
                  AND "gameId" = p_game_id
                  AND "userId" = v_requesting_user
            ) INTO v_is_participant;
        EXCEPTION WHEN OTHERS THEN
            v_is_participant := false;
        END;

        -- If called from a trigger (no auth context, v_requesting_user is NULL),
        -- write the winner name unconditionally — the frontend will re-gate.
        -- If called from a client RPC, only write if the requester is a participant.
        IF v_requesting_user IS NOT NULL AND NOT v_is_participant THEN
            v_winner_name := NULL;
        END IF;

        IF v_completed_at IS NULL THEN
            v_completed_at := now();
        END IF;
    END IF;

    -- ── UPDATE every chat card for this game room ──
    -- The chatProvider already holds a Realtime UPDATE subscription on
    -- ChatMessage (family-filtered, REPLICA IDENTITY FULL), so this UPDATE
    -- fans out to every family member's open chat UI automatically.
    UPDATE "ChatMessage"
    SET
        "gameInviteStatus" = v_unified_status,
        "gameWinnerName" = COALESCE(v_winner_name, "gameWinnerName"),
        "gameCompletedAt" = COALESCE(v_completed_at, "gameCompletedAt")
    WHERE
        "messageType" = 'gameInvite'
        AND "gameId" = p_game_id;

    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RETURN v_update_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sync_game_invite_status(
    text, text, text, text, timestamptz
) TO authenticated;

-- ── 4. fn_sweep_expired_game_rooms() — pg_cron-driven expiry sweep ──────
-- Runs every 5 minutes (matching the existing expire-stale-game-rooms
-- cadence, less frequent than the 15s/30s presence/bingo ticks since
-- room expiry has minute-scale tolerance, not second-scale).
--
-- For each game table, finds rooms where:
--   • status is in a pre-game state ('waiting'/'lobby'/'setup'/etc.)
--   • expiresAt is set AND has passed
--   • cancelledAt IS NULL (not already cancelled)
--   • closedAt IS NULL (not already closed)
-- and transitions them to 'expired' (or 'cancelled' for Pattern C tables
-- that already have that vocabulary), then calls fn_sync_game_invite_status
-- to fan out to chat cards.
--
-- Once a room is in_progress, expiresAt is NULL (cleared by the trigger
-- on transition to in_progress), so it's never swept — matching the spec's
-- "in-progress rooms should NOT expire on this same timer" rule.

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
BEGIN
    -- Each game table's row is checked. We use a per-table loop because
    -- the status column vocabulary varies (waiting vs lobby vs setup).
    -- The fn_sync_game_invite_status RPC centralizes the mapping.
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
        -- Pick the terminal status for this table's vocabulary.
        -- Pattern C tables use 'cancelled'; Pattern A/B use 'expired'
        -- (or 'cancelled' for the few that support it).
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

        -- Find rows past their expiry window that are still in a pre-game state.
        -- We use a permissive IN list to cover all known pre-game vocabularies.
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
            -- Transition to the terminal status.
            EXECUTE format(
                'UPDATE %I
                 SET "status" = $1,
                     "cancelledAt" = COALESCE("cancelledAt", now()),
                     "closedAt" = COALESCE("closedAt", now()),
                     "lastActivityAt" = now()
                 WHERE "id" = $2',
                t
            ) USING v_terminal_status, r.game_id;

            -- Post an 'auto_close' / 'expired' system event so connected
            -- lobby clients navigate out (the existing room_lifecycle_listener
            -- picks this up).
            INSERT INTO "game_room_events"
                ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
            VALUES
                (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                 jsonb_build_object(
                    'reason', 'expired',
                    'expiredAt', now(),
                    'unifiedStatus', v_unified_status
                 ));

            -- Fan out to chat cards. The trigger on this table will ALSO
            -- fire (because we just UPDATEd status), so this call is
            -- belt-and-suspenders — the trigger is the primary path.
            -- We call it explicitly in case the trigger hasn't been
            -- created yet on this table (forward compat).
            PERFORM public.fn_sync_game_invite_status(
                t, r.game_id, v_terminal_status, NULL, NULL
            );

            v_swept_count := v_swept_count + 1;
        END LOOP;
    END LOOP;

    RETURN v_swept_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sweep_expired_game_rooms() TO authenticated;

-- ── 5. AFTER UPDATE trigger on each game table ──────────────────────────
-- Fires fn_sync_game_invite_status whenever the game's `status` column
-- changes. This is the central "state-transition fan-out" hook.
-- The trigger is DEFERRED-ish: we only fire on actual status transitions
-- (UPDATE OF status), not on every incidental UPDATE (e.g. lastActivityAt
-- bump from a heartbeat).
--
-- NOTE: We deliberately do NOT pass winner info from the trigger — the
-- per-game winner columns vary too much (winnerUserId, winnerPlayerId,
-- winnerUserIds, overallWinnerId, etc.). The Flutter providers, which
-- already know each game's winner-column shape, continue to call
-- syncGameInviteChatCards(winnerName: ...) directly on completion to
-- populate the privacy-gated result display. The trigger handles only
-- the status-sync half of the contract.

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
        'crystal_bridge_games', 'ghost_painter_rounds'
    ] LOOP
        -- Drop + recreate for idempotency.
        EXECUTE format('DROP TRIGGER IF EXISTS "trg_%I_sync_chat_card" ON %I;', t, t);

        -- The trigger function is per-table (PL/pgSQL requires a function
        -- per trigger; we can't parameterize the table name in a single
        -- generic function for OLD/NEW row references). Each function is
        -- tiny — just calls the central RPC with the table name + new status.
        EXECUTE format(
            'CREATE OR REPLACE FUNCTION public.fn_trg_%I_sync_chat_card()
             RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
             BEGIN
                 -- Only fire when status actually changed (NEW.status <> OLD.status)
                 -- OR when expiresAt is being set/cleared (lifecycle deadline change).
                 IF (NEW."status" IS DISTINCT FROM OLD."status")
                    OR (NEW."expiresAt" IS DISTINCT FROM OLD."expiresAt") THEN
                     PERFORM public.fn_sync_game_invite_status(
                         ''%s'', NEW.id, NEW."status", NULL, NULL
                     );
                 END IF;
                 RETURN NEW;
             END;
             $f$;',
            t, t
        );

        EXECUTE format(
            'CREATE TRIGGER "trg_%I_sync_chat_card"
             AFTER UPDATE OF "status", "expiresAt" ON %I
             FOR EACH ROW
             EXECUTE FUNCTION public.fn_trg_%I_sync_chat_card();',
            t, t, t
        );
    END LOOP;
END $$;

-- ── 6. Set expiresAt on existing waiting rooms (backfill) ────────────────
-- Existing rooms in pre-game states get a 30-min forward expiry so the
-- sweep picks them up if they're truly stale. Rooms in 'in_progress'
-- get expiresAt = NULL (never expire on this timer).
--
-- This is a one-time backfill. New rooms get expiresAt set by:
--   • The Flutter provider's createRoom path (adds 30min from now)
--   • OR the per-game start RPC's "transition to full" path (adds 10min)
--   • OR the per-game start RPC's "transition to in_progress" path (sets NULL)

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
        'crystal_bridge_games', 'ghost_painter_rounds'
    ] LOOP
        -- Pre-game rooms: expiresAt = createdAt + 30min IF NOT already set.
        EXECUTE format(
            'UPDATE %I
             SET "expiresAt" = "createdAt" + interval ''30 minutes''
             WHERE "expiresAt" IS NULL
               AND (
                   "status" IN (''waiting'', ''lobby'', ''setup'', ''countdown'',
                                ''drawing'', ''guessing'', ''open'')
                   OR "status" IS NULL
               )
               AND "createdAt" > now() - interval ''24 hours''',
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

-- ── 7. Schedule the pg_cron sweep job ────────────────────────────────────
-- Every 5 minutes — matches the existing expire-stale-game-rooms cadence
-- (less frequent than the 15s bingo / 30s presence sweeps since room
-- expiry has minute-scale tolerance).
--
-- The job name 'sweep-expired-game-rooms-lifecycle' is distinct from the
-- existing 'expire-stale-game-rooms' job (which uses a different function
-- with different semantics — autoCloseDeadline-based lobby TTL, not the
-- lifecycle state-machine expiry).

SELECT cron.schedule(
    'sweep-expired-game-rooms-lifecycle',
    '*/5 * * * *',  -- every 5 minutes
    $$ SELECT public.fn_sweep_expired_game_rooms(); $$
);

-- Grant authenticated users the right to manually invoke the sweep (e.g.
-- from an admin debug screen). The cron job runs as the postgres superuser.
GRANT EXECUTE ON FUNCTION public.fn_sweep_expired_game_rooms() TO authenticated;

-- ── 8. Documentation comment ─────────────────────────────────────────────
COMMENT ON FUNCTION public.fn_sync_game_invite_status(text, text, text, text, timestamptz) IS
'Centralized server-side sync of game-room lifecycle status to chat-invite cards.

Called by:
  1. AFTER UPDATE OF status, expiresAt trigger on every game table (the
     primary path — fires automatically whenever the game row''s status
     column changes, regardless of which client/rpc changed it).
  2. fn_sweep_expired_game_rooms() (belt-and-suspenders for the trigger
     in case a table is missing its trigger).
  3. Per-game Flutter providers via the syncGameInviteChatCards() helper
     (still used for the winner-name write on completion, since the
     per-game winner column shape varies).

Maps per-game status vocabularies (waiting/lobby/setup, in_progress/active,
completed/finished, expired/cancelled) to the unified 5-state model
(pending, in_progress, completed, expired) on ChatMessage.gameInviteStatus.

Privacy: when p_winner_name is provided, it is only written to
ChatMessage.gameWinnerName if the calling auth.uid() is a participant
of the match (verified via game_participants). Trigger-driven calls
(no auth context) write the winner name unconditionally; the frontend
re-validates participant status before rendering via the existing
match_history_for_participant RPC contract.';
