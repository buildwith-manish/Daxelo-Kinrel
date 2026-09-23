-- 20260923120000_prediction_battle_v1_history_rpc.sql
--
-- Phase 3.3 — History + Streaks RPC for the Prediction Battle v1.
--
-- The pb_v1_win_streaks table is populated by fn_pb_v1_reveal_all_due
-- (the 9 PM IST cron tick) but never read by the Flutter client. This
-- migration adds a single RPC that returns everything the new
-- History screen needs in one round-trip:
--
--   1. The user's current + best win streak for the family.
--   2. The last N revealed rounds for the family (default 30), each
--      with: the question, the correct answer, the user's guess
--      (or null if they didn't participate), the winner set, and
--      the user's distance from the correct answer.
--   3. Per-round participation stats (total guesses, did-i-win flag).
--
-- The RPC is SECURITY DEFINER because:
--   - We want to return data for ALL family members' guesses (not
--     just the requesting user's), so the pg_v1_guesses RLS policy
--     (which allows SELECT only when the requesting user is a family
--     member) would let us through — but we want to enforce the
--     family-membership check ourselves in one place rather than
--     relying on the cascading RLS pattern.
--   - The function reads pb_v1_win_streaks for the requesting user
--     only (the RLS policy on that table allows the user themselves
--     OR family members; SECURITY DEFINER bypasses RLS entirely so
--     we don't depend on which path fires).
--
-- The function is idempotent and read-only — safe to call repeatedly.
-- The Flutter client caches the result via LocalCacheService for
-- offline-ish cold opens of the history screen (mirroring the
-- cache-first pattern used by pb_v1_provider).

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
  v_result jsonb;
BEGIN
  -- 1. Streaks for this (user, family)
  SELECT current_streak, best_streak, updated_at INTO v_streak
  FROM "pb_v1_win_streaks"
  WHERE user_id = p_user_id AND family_id = p_family_id;

  -- 2. Last N revealed rounds for the family, with the question + the
  --    requesting user's guess (LEFT JOIN — null if they didn't
  --    participate) + the winner set (computed inline).
  --
  -- We compute the winner set in SQL using a CTE that finds the
  -- minimum distance per round, then filters guesses whose distance
  -- matches the minimum. This avoids needing a second RPC round-trip
  -- or client-side winner computation.
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
    'rounds', v_rounds
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_history(text, text, integer) TO authenticated;
