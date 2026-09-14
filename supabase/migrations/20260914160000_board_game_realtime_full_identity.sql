-- =============================================================================
-- Daxelo-Kinrel — Task 4 (round 3): board-game realtime sync fixes
-- =============================================================================
-- Two production bugs found in live two-account chess E2E:
--
-- 1. MOVES NEVER SYNCED TO THE OPPONENT'S BOARD:
--    a) The chess provider inserted the move row with 'notation':
--       logic.history.last — but chess.dart 0.8.1's history is a
--       List<State> of position objects, NOT SAN strings. jsonEncode
--       threw "Converting object to an encodable object failed" → the
--       chess_moves INSERT was rolled back → the opponent's
--       chess_moves INSERT realtime subscription never fired. (Client
--       fix: use logic.move_to_san() before applying the move.)
--    b) Even the chess_games UPDATE event (boardState + turn) could
--       not be applied by the opponent: all 4 board-game tables use
--       REPLICA IDENTITY DEFAULT, so UPDATE events only carry the
--       CHANGED COLUMNS + PK. The handlers run Game.fromJson(newRecord)
--       on that partial map → playerWhiteId/playerBlackId default to
--       '' → the receiver's own color/turn resolution breaks and the
--       board freezes on the old position.
--
--    FIX: REPLICA IDENTITY FULL on every board-game table already in
--    the supabase_realtime publication (chess/checkers/tictactoe/
--    carrom + their moves/rounds/turns children) so UPDATE payloads
--    carry the complete row — the same treatment the Task 4 migration
--    already applied to game_participants / game_spectators /
--    game_room_events and the temporary-game player tables.
-- =====================================================================

ALTER TABLE "chess_games"      REPLICA IDENTITY FULL;
ALTER TABLE "chess_moves"      REPLICA IDENTITY FULL;
ALTER TABLE "checkers_games"   REPLICA IDENTITY FULL;
ALTER TABLE "checkers_moves"   REPLICA IDENTITY FULL;
ALTER TABLE "tictactoe_games"  REPLICA IDENTITY FULL;
ALTER TABLE "tictactoe_moves"  REPLICA IDENTITY FULL;
ALTER TABLE "tictactoe_rounds" REPLICA IDENTITY FULL;
ALTER TABLE "carrom_games"     REPLICA IDENTITY FULL;
ALTER TABLE "carrom_turns"     REPLICA IDENTITY FULL;
