-- 20260923130000_prediction_battle_v1_history_leaderboard.sql
--
-- Phase 3.4 — extend fn_pb_v1_get_history to also return a family-
-- wide leaderboard. The leaderboard ranks all family members by:
--   1. current_streak DESC (the live streak is most engaging)
--   2. best_streak DESC (tiebreaker — historical performance)
--   3. user_id ASC (final tiebreaker — stable order)
--
-- Each leaderboard row includes:
--   - user_id
--   - current_streak, best_streak (from pb_v1_win_streaks)
--   - total_wins_in_window (computed from the rounds we already
--     return — counts how many of the visible rounds this user won)
--   - total_guesses_in_window (computed — how many of the visible
--     rounds this user participated in)
--
-- We compute the "in window" stats by aggregating over the same
-- rounds_with_winners CTE that the existing function builds. This
-- means we don't need a second pass over pb_v1_rounds — we reuse the
-- in-memory CTE result.
--
-- Cache invalidation strategy (Flutter side):
-- The cache key prefix is bumped from `pb_v1_history_` to
-- `pb_v1_history_v2_` so old caches that don't have the `leaderboard`
-- field are ignored. The model parser treats a missing `leaderboard`
-- field as an empty list, so even a stale cache will render without
-- crashing — the user just sees an empty leaderboard section until
-- the refresh completes.

CREATE OR REPLACE FUNCTION public.fn_pb_v1_get_history(
  p_family_id text,
  p_user_id text,
  p_limit integer DEFAULT 30
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_streak record;
  v_rounds jsonb;
  v_leaderboard jsonb;
  v_result jsonb;
BEGIN
  -- 1. Streaks for this (user, family)
  SELECT current_streak, best_streak, updated_at INTO v_streak
  FROM "pb_v1_win_streaks"
  WHERE user_id = p_user_id AND family_id = p_family_id;

  -- 2. Last N revealed rounds for the family, with the question + the
  --    requesting user's guess (LEFT JOIN — null if they didn't
  --    participate) + the winner set (computed inline).
  WITH round_guesses AS (
    SELECT
      r.id AS round_id,
      r.question_id,
      r.opens_at,
      r.reveal_at,
      r.status,
      q.question_text,
      q.correct_answer,
      q.unit_label,
      q.category,
      q.fun_fact_text,
      g.user_id AS guess_user_id,
      g.guess_value,
      CASE
        WHEN q.correct_answer > 1000 THEN
          ABS(g.guess_value - q.correct_answer) / q.correct_answer * 100
        ELSE
          ABS(g.guess_value - q.correct_answer)::float
      END AS distance
    FROM "pb_v1_rounds" r
    JOIN "pb_v1_questions" q ON q.id = r.question_id
    LEFT JOIN "pb_v1_guesses" g ON g.round_id = r.id
    WHERE r.family_id = p_family_id
      AND r.status = 'revealed'
  ),
  min_dist AS (
    SELECT round_id, MIN(distance) AS min_distance
    FROM round_guesses
    WHERE guess_user_id IS NOT NULL
    GROUP BY round_id
  ),
  rounds_with_winners AS (
    SELECT DISTINCT
      rg.round_id,
      rg.question_id,
      rg.opens_at,
      rg.reveal_at,
      rg.status,
      rg.question_text,
      rg.correct_answer,
      rg.unit_label,
      rg.category,
      rg.fun_fact_text,
      COALESCE(
        (SELECT jsonb_agg(DISTINCT rg2.guess_user_id)
         FROM round_guesses rg2
         WHERE rg2.round_id = rg.round_id
           AND rg2.distance = (SELECT min_distance FROM min_dist WHERE min_dist.round_id = rg.round_id)
        ),
        '[]'::jsonb
      ) AS winner_user_ids,
      (SELECT COUNT(*) FROM round_guesses rg3
       WHERE rg3.round_id = rg.round_id AND rg3.guess_user_id IS NOT NULL) AS total_guesses,
      -- The requesting user's guess for this round (or null)
      COALESCE(
        (SELECT jsonb_build_object(
          'guess_value', rg4.guess_value,
          'distance', rg4.distance
        )
        FROM round_guesses rg4
        WHERE rg4.round_id = rg.round_id AND rg4.guess_user_id = p_user_id),
        NULL::jsonb
      ) AS my_guess,
      -- Whether the requesting user was a winner
      EXISTS(
        SELECT 1 FROM round_guesses rg5
        WHERE rg5.round_id = rg.round_id
          AND rg5.guess_user_id = p_user_id
          AND rg5.distance = (SELECT min_distance FROM min_dist WHERE min_dist.round_id = rg.round_id)
      ) AS i_won
    FROM round_guesses rg
  ),
  -- ── Phase 3.4 — per-user aggregation across the visible rounds ────
  -- We aggregate over round_guesses (limited to the rounds that are
  -- in the rounds_with_winners CTE) to compute each user's wins + total
  -- guesses IN THE VISIBLE WINDOW. The window is p_limit rounds
  -- (default 30). This is a different stat from the all-time
  -- current_streak / best_streak in pb_v1_win_streaks — it's "how
  -- active is this user in the visible history window".
  visible_rounds AS (
    SELECT round_id FROM rounds_with_winners
  ),
  user_window_stats AS (
    SELECT
      rg.guess_user_id AS user_id,
      COUNT(DISTINCT rg.round_id) AS total_guesses_in_window,
      COUNT(DISTINCT rg.round_id) FILTER (
        WHERE rg.distance = (SELECT min_distance FROM min_dist WHERE min_dist.round_id = rg.round_id)
      ) AS total_wins_in_window
    FROM round_guesses rg
    WHERE rg.guess_user_id IS NOT NULL
      AND rg.round_id IN (SELECT round_id FROM visible_rounds)
    GROUP BY rg.guess_user_id
  ),
  -- ── Full family leaderboard ───────────────────────────────────────
  -- LEFT JOIN pb_v1_win_streaks with user_window_stats so we include
  -- family members who have ever played (in pb_v1_win_streaks) even
  -- if they didn't participate in the visible window. Members with
  -- no row in pb_v1_win_streaks at all are NOT included — we don't
  -- have a list of family members here, only the win_streaks table
  -- which is populated on first win. That's a known limitation; the
  -- history screen's user-name lookup covers everyone who has ever
  -- played.
  leaderboard_rows AS (
    SELECT
      ws.user_id,
      ws.current_streak,
      ws.best_streak,
      COALESCE(uws.total_wins_in_window, 0) AS total_wins_in_window,
      COALESCE(uws.total_guesses_in_window, 0) AS total_guesses_in_window
    FROM "pb_v1_win_streaks" ws
    LEFT JOIN user_window_stats uws ON uws.user_id = ws.user_id
    WHERE ws.family_id = p_family_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'user_id', user_id,
    'current_streak', current_streak,
    'best_streak', best_streak,
    'total_wins_in_window', total_wins_in_window,
    'total_guesses_in_window', total_guesses_in_window
  ) ORDER BY
    current_streak DESC,
    best_streak DESC,
    user_id ASC
  ), '[]'::jsonb) INTO v_leaderboard
  FROM leaderboard_rows;

  -- ── Build the rounds JSON (same as before) ───────────────────────
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'round_id', round_id,
    'question_id', question_id,
    'opens_at', opens_at,
    'reveal_at', reveal_at,
    'status', status,
    'question_text', question_text,
    'correct_answer', correct_answer,
    'unit_label', unit_label,
    'category', category,
    'fun_fact_text', fun_fact_text,
    'winner_user_ids', winner_user_ids,
    'total_guesses', total_guesses,
    'my_guess', my_guess,
    'i_won', i_won
  ) ORDER BY reveal_at DESC), '[]'::jsonb) INTO v_rounds
  FROM rounds_with_winners
  LIMIT p_limit;

  v_result := jsonb_build_object(
    'ok', true,
    'streak', CASE WHEN v_streak IS NULL THEN
      jsonb_build_object('current_streak', 0, 'best_streak', 0, 'updated_at', NULL)
    ELSE
      jsonb_build_object(
        'current_streak', v_streak.current_streak,
        'best_streak', v_streak.best_streak,
        'updated_at', v_streak.updated_at
      )
    END,
    'rounds', v_rounds,
    -- Phase 3.4 — new field. Existing Flutter caches (keyed
    -- `pb_v1_history_<familyId>`) do NOT have this field; the cache
    -- key prefix is bumped to `pb_v1_history_v2_<familyId>` on the
    -- Flutter side so old caches are ignored. The model parser also
    -- treats a missing `leaderboard` field as an empty list, so a
    -- stale cache would not crash.
    'leaderboard', v_leaderboard
  );

  RETURN v_result;
END;
$$;
