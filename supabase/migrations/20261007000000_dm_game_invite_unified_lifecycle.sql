-- =============================================================================
-- Daxelo-Kinrel — Unified game-invite lifecycle for DM (pin-to-pin group parity)
-- =============================================================================
-- GOAL: a game-invite card in a DIRECT MESSAGE must look and behave exactly
-- like the same card in the FAMILY/GROUP chat. Same widget (already shared:
-- MessageBubble._buildGameInviteCard), same 5-state lifecycle, same live
-- player counts, same winner/completed display, same spectators flag, and
-- — most importantly — the SAME server-side state machine driving it.
--
-- BEFORE this migration, the two chat types used DIFFERENT logic:
--   • Group chat: server-side. fn_sync_game_invite_status (called by AFTER
--     UPDATE triggers on every game table) + fn_sweep_expired_game_rooms +
--     fn_cleanup_orphaned_chat_invites write ChatMessage.gameInviteStatus /
--     gameWinnerName / gameCompletedAt / gameCurrentPlayers /
--     gameSpectatorsEnabled. Realtime UPDATEs fan out to every client.
--   • DM: client-side. The Flutter dm_invite_status_provider queried each
--     game table directly per card and overrode the status in the adapter.
--     Player counts were frozen at invite-send time, winner was never
--     shown, spectators was never synced, and — critically — when a room
--     was HARD-DELETED (host cancel / auto-close) the game row vanished,
--     the client-side query returned nothing, and the DM card stayed
--     "Waiting for players" with a live Join button forever, while the
--     group card correctly showed "Expired".
--
-- AFTER this migration, both surfaces are driven by the SAME server-side
-- functions:
--   1. fn_sync_dm_game_invites(p_game_id, ...)  — new shared helper that
--      writes status / currentPlayers / winnerName / completedAt /
--      spectatorsEnabled into the DirectMessage invite payload JSON.
--   2. fn_sync_game_invite_status  — extended: after updating ChatMessage
--      rows it now ALSO fans out to DirectMessage rows. One trigger,
--      both surfaces.
--   3. fn_sync_game_spectators     — extended the same way.
--   4. fn_cleanup_orphaned_chat_invites — extended: orphaned DM invites
--      (game row hard-deleted) transition to 'expired' exactly like
--      orphaned ChatMessage rows. "Room closed → Expired" for ALL chats.
--   5. One-time backfill: every existing DirectMessage invite payload is
--      reconciled against the live game tables (expired / completed /
--      in_progress), and invites whose game row no longer exists are
--      marked 'expired' — fixing every stale "Waiting for players" DM
--      card in production.
--
-- The Flutter client (companion change, same branch) then reads all live
-- fields from the payload exactly the way the group path reads them from
-- ChatMessage columns, and the client-side dm_invite_status_provider
-- (the "different logic") is removed.
--
-- Idempotent: CREATE OR REPLACE + IF NOT EXISTS everywhere.
-- =============================================================================

-- ── 1. fn_safe_jsonb — NULL-safe JSONB cast ───────────────────────────────
-- DirectMessage.content is a TEXT column. Game-invite DMs hold a JSON blob
-- (Dart jsonEncode) but legacy/hand-typed rows may hold plain text. A bare
-- `content::jsonb` in a WHERE clause would abort the whole statement on the
-- first invalid row — this helper returns NULL instead so those rows are
-- simply skipped by the filters below.
CREATE OR REPLACE FUNCTION public.fn_safe_jsonb(p_text text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN p_text::jsonb;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- ── 2. fn_sync_dm_game_invites — the DM twin of the ChatMessage sync ──────
-- Updates the invite payload JSON of every DirectMessage row whose payload
-- gameId matches p_game_id. Only the provided (non-NULL) params are merged
-- into the payload — NULL params leave the existing value untouched
-- (jsonb_strip_nulls drops the absent keys before the || merge).
--
-- Payload keys (read by the Flutter adapter — must stay in sync with
-- direct_message_adapter.dart):
--   status, currentPlayers, winnerName, completedAt, spectatorsEnabled
--
-- Winner privacy gate mirrors fn_sync_game_invite_status: when called with
-- an auth context (Flutter client), the winner name is only written if the
-- caller is a participant of the match; trigger/cron calls (no auth.uid())
-- write it unconditionally and the frontend re-gates at render time.
-- gameId is a UUID unique across all game tables, so the participant check
-- matches on gameId + userId alone (no gameTable needed).
CREATE OR REPLACE FUNCTION public.fn_sync_dm_game_invites(
    p_game_id text,
    p_status text DEFAULT NULL,
    p_current_players integer DEFAULT NULL,
    p_winner_name text DEFAULT NULL,
    p_completed_at timestamptz DEFAULT NULL,
    p_spectators_enabled boolean DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_update_count integer := 0;
    v_requesting_user text := auth.uid()::text;
    v_is_participant boolean := false;
    v_winner_name text := p_winner_name;
    v_completed_at timestamptz := p_completed_at;
BEGIN
    IF p_game_id IS NULL OR p_game_id = '' THEN
        RETURN 0;
    END IF;

    -- ── Privacy gate for winner name (mirrors fn_sync_game_invite_status) ──
    IF v_winner_name IS NOT NULL AND v_requesting_user IS NOT NULL THEN
        BEGIN
            SELECT EXISTS (
                SELECT 1 FROM public."game_participants"
                WHERE "gameId" = p_game_id
                  AND "userId" = v_requesting_user
            ) INTO v_is_participant;
        EXCEPTION WHEN OTHERS THEN
            v_is_participant := false;
        END;

        -- Client-context caller who is not a participant → no winner write.
        -- Trigger/cron calls (v_requesting_user NULL) write unconditionally.
        IF NOT v_is_participant THEN
            v_winner_name := NULL;
        END IF;
    END IF;

    IF v_winner_name IS NOT NULL
       AND v_completed_at IS NULL
       AND p_status = 'completed' THEN
        v_completed_at := now();
    END IF;

    -- ── UPDATE every DM invite card for this game room ──────────────────
    -- DirectMessage is in the supabase_realtime publication with
    -- REPLICA IDENTITY FULL, so this UPDATE fans out to both the sender's
    -- and the receiver's open DM screens automatically — the same realtime
    -- fan-out the group chat gets from its ChatMessage subscription.
    UPDATE "DirectMessage" AS dm
    SET "content" = (
            public.fn_safe_jsonb(dm."content")
            || jsonb_strip_nulls(jsonb_build_object(
                'status', p_status,
                'currentPlayers', p_current_players,
                'winnerName', v_winner_name,
                'completedAt', v_completed_at,
                'spectatorsEnabled', p_spectators_enabled
            ))
        )::text,
        "updatedAt" = now()
    WHERE dm."messageType" = 'gameInvite'
      AND public.fn_safe_jsonb(dm."content") ->> 'gameId' = p_game_id;

    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RETURN v_update_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sync_dm_game_invites(
    text, text, integer, text, timestamptz, boolean
) TO authenticated;

COMMENT ON FUNCTION public.fn_sync_dm_game_invites(text, text, integer, text, timestamptz, boolean) IS
'Writes live game-room state (status / currentPlayers / winnerName / completedAt /
spectatorsEnabled) into the invite payload JSON of every DirectMessage game-invite
row for p_game_id. The DM twin of the ChatMessage sync in fn_sync_game_invite_status
— both are called by the same game-table triggers and sweeps so the DM card and the
group card always render the same lifecycle state.';

-- Partial expression index for the payload gameId lookup (best-effort —
-- some Postgres versions reject plpgsql expressions in indexes; the
-- sequential scan is fine at this table size).
DO $$
BEGIN
    CREATE INDEX IF NOT EXISTS "DM_gameInviteGameId_idx"
    ON "DirectMessage" ((public.fn_safe_jsonb("content") ->> 'gameId'))
    WHERE "messageType" = 'gameInvite';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping DM_gameInviteGameId_idx: %', SQLERRM;
END $$;

-- ── 3. fn_sync_game_invite_status — extended to fan out to DMs too ────────
-- Identical to the 20261004100000 version except for the final section:
-- after updating ChatMessage rows, it now ALSO syncs the matching
-- DirectMessage invite payloads through the SAME unified status, winner
-- and completedAt values. One trigger on the game table → both surfaces.
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
    -- leave it NULL.
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

    -- ── UPDATE every chat card for this game room (GROUP chat) ──
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

    -- ── UPDATE every DM invite card for this game room (1:1 chat) ──
    -- Pin-to-pin group parity: the same trigger that keeps the group card
    -- in sync now also keeps the DM card in sync. The DM payloads are
    -- watched by the DirectMessage realtime channel, so both the sender's
    -- and the receiver's open DM screens re-render. Winner gating inside
    -- fn_sync_dm_game_invites mirrors the gate above.
    PERFORM public.fn_sync_dm_game_invites(
        p_game_id,
        v_unified_status,
        NULL,
        v_winner_name,
        v_completed_at
    );

    RETURN v_update_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sync_game_invite_status(
    text, text, text, text, timestamptz
) TO authenticated;

-- ── 4. fn_sync_game_spectators — extended to fan out to DMs too ───────────
CREATE OR REPLACE FUNCTION public.fn_sync_game_spectators(
    p_game_table text,
    p_game_id text,
    p_spectators_enabled boolean
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_update_count integer := 0;
BEGIN
    UPDATE "ChatMessage"
    SET "gameSpectatorsEnabled" = p_spectators_enabled
    WHERE
        "messageType" = 'gameInvite'
        AND "gameId" = p_game_id;

    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Pin-to-pin group parity: keep the DM invite payloads in sync with the
    -- host's spectator-mode setting as well.
    PERFORM public.fn_sync_dm_game_invites(
        p_game_id,
        NULL,
        NULL,
        NULL,
        NULL,
        p_spectators_enabled
    );

    RETURN v_update_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sync_game_spectators(
    text, text, boolean
) TO authenticated;

-- ── 5. fn_cleanup_orphaned_chat_invites — extended to DMs too ─────────────
-- Transitions ChatMessage AND DirectMessage game-invite rows whose gameId
-- no longer exists in ANY game table to 'expired'. This is the path that
-- makes "room closed → card shows Expired" work identically for the group
-- chat and the DM after a room is HARD-DELETED (host cancel / auto-close /
-- completed-game cleanup, none of which fire the AFTER UPDATE trigger).
-- Called by the sweep cron job every 5 min.
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
    -- ── GROUP chat: orphaned ChatMessage rows ────────────────────────────
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

    -- ── DM chat: orphaned DirectMessage invite payloads ──────────────────
    -- Same rule, same terminal status, same 5-minute cadence as the group
    -- chat above — pin-to-pin parity. A payload whose status key is
    -- missing (pre-backfill legacy row) is treated as non-terminal so it
    -- gets reconciled too.
    FOR v_game_id IN
        SELECT DISTINCT public.fn_safe_jsonb("content") ->> 'gameId' AS game_id
        FROM "DirectMessage"
        WHERE "messageType" = 'gameInvite'
          AND public.fn_safe_jsonb("content") ->> 'gameId' IS NOT NULL
          AND COALESCE(
                public.fn_safe_jsonb("content") ->> 'status',
                'pending'
              ) IN ('pending', 'in_progress', 'accepted', 'active')
    LOOP
        v_table_exists := false;

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
                EXIT;
            END IF;
        END LOOP;

        IF NOT v_table_exists THEN
            PERFORM public.fn_sync_dm_game_invites(
                v_game_id,
                'expired'
            );
        END IF;
    END LOOP;

    RETURN v_cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cleanup_orphaned_chat_invites() TO authenticated;

COMMENT ON FUNCTION public.fn_cleanup_orphaned_chat_invites() IS
'Transitions ChatMessage AND DirectMessage game-invite rows whose gameId no
longer exists in ANY game table to the expired state. Handles the orphan case
where fn_close_expired_rooms, fn_cancel_game_room or fn_cleanup_completed_games
hard-deleted the game row without updating the chat cards. DM invite payloads
(without a dedicated gameInviteStatus column) get their payload JSON status set
to expired. Called by the sweep cron job every 5 min — the same logic for the
group chat and the direct message chat.';

-- ── 6. One-time backfill: reconcile every existing DM invite payload ──────
-- For each distinct gameId referenced by a DirectMessage gameInvite row:
--   • the game row still exists → payload status := unified mapping of the
--     game table's current status (same CASE as fn_sync_game_invite_status)
--   • the game row is gone (hard-deleted) → payload status := 'expired'
--     (this is exactly what the group ChatMessage rows already show, and
--     what fixes every stale "Waiting for players" + Join DM card).
-- Spectators flag is backfilled from the game row when the column exists.
DO $$
DECLARE
    r record;
    t text;
    v_raw_status text;
    v_unified text;
    v_spectators boolean;
    v_spectators_found boolean;
BEGIN
    FOR r IN
        SELECT DISTINCT public.fn_safe_jsonb("content") ->> 'gameId' AS game_id
        FROM "DirectMessage"
        WHERE "messageType" = 'gameInvite'
          AND public.fn_safe_jsonb("content") ->> 'gameId' IS NOT NULL
    LOOP
        IF r.game_id IS NULL OR r.game_id = '' THEN
            CONTINUE;
        END IF;

        v_raw_status := NULL;
        v_unified := NULL;
        v_spectators := NULL;

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
                EXECUTE format('SELECT "status" FROM %I WHERE "id" = $1', t)
                    INTO v_raw_status USING r.game_id;
            EXCEPTION WHEN OTHERS THEN
                v_raw_status := NULL;
            END;

            IF v_raw_status IS NOT NULL THEN
                v_unified := CASE
                    WHEN v_raw_status IN ('waiting', 'lobby', 'setup', 'countdown', 'drawing', 'guessing')
                        THEN 'pending'
                    WHEN v_raw_status IN ('in_progress', 'active')
                        THEN 'in_progress'
                    WHEN v_raw_status IN ('completed', 'finished')
                        THEN 'completed'
                    WHEN v_raw_status IN ('expired', 'cancelled')
                        THEN 'expired'
                    ELSE NULL
                END;
                EXIT; -- game row found — stop scanning tables
            END IF;
        END LOOP;

        -- Game row still exists → try to pick up the spectators flag too.
        IF v_raw_status IS NOT NULL THEN
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
                v_spectators_found := false;
                BEGIN
                    EXECUTE format(
                        'SELECT "spectatorsEnabled" FROM %I WHERE "id" = $1', t)
                        INTO v_spectators USING r.game_id;
                    v_spectators_found := v_spectators IS NOT NULL;
                EXCEPTION WHEN OTHERS THEN
                    v_spectators := NULL;
                    v_spectators_found := false;
                END;
                IF v_spectators_found THEN
                    EXIT;
                END IF;
            END LOOP;
            PERFORM public.fn_sync_dm_game_invites(
                r.game_id,
                COALESCE(v_unified, 'pending'),
                NULL, NULL, NULL,
                v_spectators
            );
        ELSE
            -- Game row hard-deleted → orphaned invite → expired
            -- (identical to what fn_cleanup_orphaned_chat_invites did for
            -- the group ChatMessage rows).
            PERFORM public.fn_sync_dm_game_invites(
                r.game_id,
                'expired'
            );
        END IF;
    END LOOP;
END $$;

-- ── 7. Run the (now DM-aware) orphan cleanup immediately ──────────────────
-- Belt-and-suspenders: catches anything the backfill loop above may have
-- missed (e.g. rows inserted while the backfill was running).
SELECT public.fn_cleanup_orphaned_chat_invites() AS orphaned_cards_cleaned;
