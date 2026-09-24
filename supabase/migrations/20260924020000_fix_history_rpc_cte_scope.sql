-- 20260924020000_fix_history_rpc_cte_scope.sql
--
-- Fix: fn_pb_v1_get_history fails with "relation rounds_with_winners
-- does not exist" because the function has TWO separate SELECT
-- statements that both reference CTEs from the same WITH clause.
--
-- In PL/pgSQL, a WITH ... SELECT statement is self-contained — the
-- CTEs are only visible within that single SELECT. The first SELECT
-- (leaderboard) consumes the WITH clause, so the second SELECT
-- (rounds) can't access rounds_with_winners anymore.
--
-- Fix: rewrite the function to use TWO independent WITH ... SELECT
-- statements — one for the rounds, one for the leaderboard. Each
-- has its own set of CTEs. This is slightly more verbose but correct.

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

  -- 2. Rounds JSON — uses its own WITH clause (independent from
  --    the leaderboard query below).
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
      COALESCE(
        (SELECT jsonb_build_object(
          'guess_value', rg4.guess_value,
          'distance', rg4.distance
        )
        FROM round_guesses rg4
        WHERE rg4.round_id = rg.round_id AND rg4.guess_user_id = p_user_id),
        NULL::jsonb
      ) AS my_guess,
      EXISTS(
        SELECT 1 FROM round_guesses rg5
        WHERE rg5.round_id = rg.round_id
          AND rg5.guess_user_id = p_user_id
          AND rg5.distance = (SELECT min_distance FROM min_dist WHERE min_dist.round_id = rg.round_id)
      ) AS i_won
    FROM round_guesses rg
  )
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

  -- 3. Leaderboard JSON — uses its OWN separate WITH clause.
  --    This is a fresh query, independent from the rounds query above.
  WITH lb_round_guesses AS (
    SELECT
      r.id AS round_id,
      q.correct_answer,
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
  lb_min_dist AS (
    SELECT round_id, MIN(distance) AS min_distance
    FROM lb_round_guesses
    WHERE guess_user_id IS NOT NULL
    GROUP BY round_id
  ),
  lb_visible_rounds AS (
    SELECT round_id FROM (
      SELECT DISTINCT round_id FROM lb_round_guesses
      ORDER BY round_id
      LIMIT p_limit
    ) sub
  ),
  lb_user_window_stats AS (
    SELECT
      rg.guess_user_id AS user_id,
      COUNT(DISTINCT rg.round_id) AS total_guesses_in_window,
      COUNT(DISTINCT rg.round_id) FILTER (
        WHERE rg.distance = (SELECT min_distance FROM lb_min_dist WHERE lb_min_dist.round_id = rg.round_id)
      ) AS total_wins_in_window
    FROM lb_round_guesses rg
    WHERE rg.guess_user_id IS NOT NULL
      AND rg.round_id IN (SELECT round_id FROM lb_visible_rounds)
    GROUP BY rg.guess_user_id
  ),
  lb_leaderboard_rows AS (
    SELECT
      ws.user_id,
      ws.current_streak,
      ws.best_streak,
      COALESCE(uws.total_wins_in_window, 0) AS total_wins_in_window,
      COALESCE(uws.total_guesses_in_window, 0) AS total_guesses_in_window
    FROM "pb_v1_win_streaks" ws
    LEFT JOIN lb_user_window_stats uws ON uws.user_id = ws.user_id
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
  FROM lb_leaderboard_rows;

  -- 4. Build the final result
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
    'leaderboard', v_leaderboard
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_history(text, text, integer) TO authenticated;
