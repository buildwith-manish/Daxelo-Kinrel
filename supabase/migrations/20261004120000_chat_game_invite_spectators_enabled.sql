-- =============================================================================
-- Daxelo-Kinrel — gameSpectatorsEnabled on ChatMessage + sync RPC
-- =============================================================================
-- Adds a denormalized `gameSpectatorsEnabled` boolean to ChatMessage so the
-- chat-invite card can render a Spectate button ONLY when the host enabled
-- spectator mode at room creation time. Without this column, the card would
-- have to do a per-render round-trip to the per-game table to check the
-- `spectatorsEnabled` column — wasteful and racy.
--
-- Pattern matches the existing denormalized fields:
--   • gameMaxPlayers, gameCurrentPlayers (capacity display)
--   • gameInviteStatus, gameWinnerName, gameCompletedAt (lifecycle display)
--
-- Backward compatibility:
--   • Column is nullable (existing rows have NULL).
--   • The Flutter classifier treats NULL as `true` (legacy default —
--     spectator mode was historically on by default). New inserts from the
--     chat-provider always set the field explicitly.
--
-- Companion Flutter changes:
--   • lib/features/chat/providers/chat_provider.dart — ChatMessage field +
--     sendGameInvite(spectatorsEnabled: ...) parameter.
--   • lib/features/games/shared/widgets/invite_family_sheet.dart — reads
--     spectatorsEnabled from the game row and passes it to sendGameInvite.
--   • lib/features/chat/presentation/widgets/message_bubble.dart — gates
--     the "Watch" / "Spectate" button on gameSpectatorsEnabled for the
--     in_progress state.
-- =============================================================================

-- 1. Add the column.
ALTER TABLE "ChatMessage"
    ADD COLUMN IF NOT EXISTS "gameSpectatorsEnabled" boolean;

-- 2. Backfill existing rows to `true` so legacy chat cards continue to
--    render the Spectate button (matching the historical default where
--    spectator mode was on by default).
UPDATE "ChatMessage"
SET "gameSpectatorsEnabled" = true
WHERE "messageType" = 'gameInvite'
  AND "gameSpectatorsEnabled" IS NULL;

-- 3. Index for the partial-UPDATE path used by fn_sync_game_spectators.
CREATE INDEX IF NOT EXISTS "ChatMessage_gameInvite_spectators_idx"
ON "ChatMessage" ("gameId")
WHERE "messageType" = 'gameInvite";

-- 4. fn_sync_game_spectators(p_game_table, p_game_id, p_spectators_enabled)
--    Called by an AFTER UPDATE trigger on each game table when the
--    `spectatorsEnabled` column changes. Mirrors the pattern of
--    fn_sync_game_invite_status for the lifecycle status.
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
    RETURN v_update_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sync_game_spectators(
    text, text, boolean
) TO authenticated;

-- 5. AFTER UPDATE OF "spectatorsEnabled" trigger on every game table.
--    The trigger function is per-table (PL/pgSQL requires a function per
--    trigger for OLD/NEW row references).
DO $$
DECLARE
    t text;
    game_tables text[] := ARRAY[
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
        -- Note: ghost_painter_rounds does NOT have a spectatorsEnabled column
        -- (it uses a different model). Excluded from the trigger list.
    ];
BEGIN
    FOREACH t IN ARRAY game_tables LOOP
        -- Drop + recreate for idempotency.
        EXECUTE format('DROP TRIGGER IF EXISTS "trg_%I_sync_spectators" ON %I;', t, t);

        -- Per-table trigger function.
        EXECUTE format(
            'CREATE OR REPLACE FUNCTION public.fn_trg_%I_sync_spectators()
             RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
             BEGIN
                 IF NEW."spectatorsEnabled" IS DISTINCT FROM OLD."spectatorsEnabled" THEN
                     PERFORM public.fn_sync_game_spectators(
                         ''%s'', NEW.id, NEW."spectatorsEnabled"
                     );
                 END IF;
                 RETURN NEW;
             END;
             $f$;',
            t, t
        );

        -- AFTER UPDATE OF spectatorsEnabled trigger.
        EXECUTE format(
            'CREATE TRIGGER "trg_%I_sync_spectators"
             AFTER UPDATE OF "spectatorsEnabled" ON %I
             FOR EACH ROW
             EXECUTE FUNCTION public.fn_trg_%I_sync_spectators();',
            t, t, t
        );
    END LOOP;
END $$;

COMMENT ON FUNCTION public.fn_sync_game_spectators(text, text, boolean) IS
'Syncs the spectatorsEnabled flag from a game-room row to every chat-invite
card for that room. Called by AFTER UPDATE OF spectatorsEnabled triggers
on every game table so the chat card always reflects the host''s current
spectator-mode setting without an extra round-trip from the client.';
