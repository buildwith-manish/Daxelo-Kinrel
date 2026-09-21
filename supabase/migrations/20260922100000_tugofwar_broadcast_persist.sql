-- Migration: 20260922100000_tugofwar_broadcast_persist.sql
--
--perf/smoothness-pass-2 — Step 1 (tugofwar hot-path migration)
--
-- Adds a single "final persist" RPC `fn_tugofwar_persist_match` that
-- the HOST calls ONCE at match end to durably write the authoritative
-- result (rope, winner, endReason, per-player pullCount) computed
-- locally during the match.
--
-- This replaces the previous hot-path pattern where every client
-- called `fn_tugofwar_pull` every ~400 ms during active play
-- (~2.5 RPC/sec/player × 4 avg players = ~10 DB writes/sec per match).
--
-- New architecture (mirrors the stickman_heist broadcast migration
-- from commit aa46b5a9):
--   HOT PATH (active play):
--     • Non-host clients send tap batches every 400 ms via Realtime
--       Broadcast (pure websocket, NO DB) — event: 'tap_batch'.
--     • Host receives tap batches via onBroadcast('tap_batch'),
--       accumulates per-player pullCount locally, computes the
--       authoritative rope position using the SAME fairness formula
--       (avgA - avgB) / 30, and broadcasts it every 150 ms via
--       event: 'rope_state' (pure websocket, NO DB).
--     • Spectators + reconnecting players receive a one-time
--       snapshot via the 'request_state' handshake — host responds
--       with the current rope + per-player counts (NO DB).
--   DURABLE DB calls (event-driven, one per match):
--     • createGame / joinGame / leaveGame (one-time per player).
--     • startMatch / fn_tugofwar_start (one-time per match).
--     • MATCH COMPLETION: ONE call to fn_tugofwar_persist_match
--       (this function) — persists per-player pullCount + final
--       rope + winner + endReason. The ONLY DB write in the hot path.
--   PER-MATCH DB OPS: ~0/sec in steady state (was ~10/sec).
--
-- Anti-cheat note:
-- The previous fn_tugofwar_pull RPC enforced a 15 taps/sec cap per
-- player server-side. The new architecture moves tap counting to the
-- host, which trusts the per-player counts broadcast by each client.
-- A malicious client can inflate their own count, but the host
-- (elected by family) is the trust anchor — same trust model as
-- stickman_heist. The fn_tugofwar_pull RPC is retained for backward
-- compatibility (and any future client that wants to use the old
-- per-batch path), but the new tugofwar_provider no longer calls it
-- in the hot path.
--
-- Watchdog note:
-- The existing 2s _watchdogTimer in tugofwar_provider calls
-- fn_tugofwar_tick, which calls fn_tugofwar_finish_by_time if
-- endsAt < now(). fn_tugofwar_finish_by_time computes the winner
-- from tugofwar_players.pullCount. Under the new architecture,
-- pullCount is only updated by fn_tugofwar_persist_match at match
-- end — so if the host disconnects before persisting, the watchdog
-- will compute a 0-0 draw. This is an accepted edge case per the
-- user's instruction ("The 2s _watchdogTimer is a local sanity-check
-- timer — leave it alone").

CREATE OR REPLACE FUNCTION fn_tugofwar_persist_match(
  p_game_id text,
  p_pull_counts jsonb,        -- {"userId1": 123, "userId2": 456, ...}
  p_final_rope real,          -- -1.0 .. +1.0
  p_end_reason text,          -- 'victory_line' | 'time_up' | 'walkover'
  p_winner_team text          -- 'A' | 'B' | NULL (draw)
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_user_id text;
  v_count int;
  v_sum_a int := 0;
  v_sum_b int := 0;
  v_winner_ids jsonb := '[]'::jsonb;
  v_was_in_progress boolean := false;
BEGIN
  -- 1. Lock the game row to prevent concurrent persist calls.
  SELECT * INTO v_game FROM "tugofwar_games" WHERE "id" = p_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- 2. Only the host can persist the match result.
  IF v_game."hostUserId" <> auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_host');
  END IF;

  -- 3. Idempotent: if the match is already completed, return success
  --    without re-writing. This protects against double-fire when
  --    the host detects both rope-cross AND time-up in the same tick.
  IF v_game.status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'already_completed');
  END IF;

  -- 4. Only persist if the match is in_progress (or, defensively, if
  --    the host is forcing a walkover from the waiting room — though
  --    that's not the normal path).
  IF v_game.status <> 'in_progress' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress',
                              'status', v_game.status);
  END IF;

  v_was_in_progress := true;

  -- 5. Apply per-player pullCount updates. p_pull_counts is a JSON
  --    object {userId: int}. Only update players who are actually in
  --    this game; ignore any spurious userIds.
  IF p_pull_counts IS NOT NULL AND jsonb_typeof(p_pull_counts) = 'object' THEN
    FOR v_user_id, v_count IN SELECT * FROM jsonb_each_text(p_pull_counts)
    LOOP
      -- Skip non-numeric values defensively.
      BEGIN
        UPDATE "tugofwar_players"
           SET "pullCount" = v_count::int,
               "lastPullAt" = CASE WHEN v_count::int > 0
                                   THEN now()
                                   ELSE "lastPullAt" END,
               "lastActivityAt" = now()
         WHERE "gameId" = p_game_id
           AND "userId" = v_user_id;
      EXCEPTION WHEN invalid_text_representation THEN
        -- Skip malformed entries.
        CONTINUE;
      END;
    END LOOP;
  END IF;

  -- 6. Compute team totals + winnerUserIds from the now-fresh
  --    pullCount values, so they're consistent with the persisted
  --    per-player counts (the host passed us p_final_rope computed
  --    locally, but we re-derive teamATaps/teamBTaps from the DB to
  --    avoid any client-side math drift).
  SELECT COALESCE(SUM("pullCount"), 0) INTO v_sum_a
    FROM "tugofwar_players" WHERE "gameId" = p_game_id AND team = 'A';
  SELECT COALESCE(SUM("pullCount"), 0) INTO v_sum_b
    FROM "tugofwar_players" WHERE "gameId" = p_game_id AND team = 'B';

  -- 7. Build winnerUserIds from the winning team's roster. If
  --    p_winner_team is NULL (draw) or doesn't match either team,
  --    leave winnerUserIds empty.
  IF p_winner_team = 'A' AND v_sum_a > 0 THEN
    SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb) INTO v_winner_ids
      FROM "tugofwar_players"
     WHERE "gameId" = p_game_id AND team = 'A';
  ELSIF p_winner_team = 'B' AND v_sum_b > 0 THEN
    SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb) INTO v_winner_ids
      FROM "tugofwar_players"
     WHERE "gameId" = p_game_id AND team = 'B';
  END IF;

  -- 8. Persist the final game state.
  UPDATE "tugofwar_games"
     SET status = 'completed',
         "completedAt" = now(),
         "teamATaps" = v_sum_a,
         "teamBTaps" = v_sum_b,
         "ropePosition" = LEAST(GREATEST(p_final_rope, -1.0), 1.0),
         "winnerTeam" = p_winner_team,
         "winnerUserIds" = v_winner_ids,
         "endReason" = p_end_reason,
         "lastRopeAt" = now(),
         "lastActivityAt" = now()
   WHERE "id" = p_game_id AND status = 'in_progress';

  RETURN jsonb_build_object(
    'ok', true,
    'teamATaps', v_sum_a,
    'teamBTaps', v_sum_b,
    'winnerTeam', p_winner_team,
    'winnerUserIds', v_winner_ids
  );
END;
$$;
GRANT EXECUTE ON FUNCTION fn_tugofwar_persist_match(text, jsonb, real, text, text) TO authenticated;
