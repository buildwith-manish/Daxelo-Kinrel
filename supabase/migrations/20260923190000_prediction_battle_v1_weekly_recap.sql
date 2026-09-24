-- 20260923190000_prediction_battle_v1_weekly_recap.sql
--
-- Phase 3.11 — Weekly recap push notification.
--
-- Every Sunday at 10 AM IST, the NestJS predictions scheduler sends
-- a "This week in [Family Name]: N predictions, M winners, K coins
-- earned. See the recap →" push to every family member.
--
-- This migration adds the SQL RPC that computes the per-family
-- weekly stats. The NestJS scheduler calls it + dispatches the FCM
-- pushes via the existing sendOnce helper.

CREATE OR REPLACE FUNCTION public.fn_pb_v1_get_weekly_recap(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since timestamptz := now() - interval '7 days';
  v_total_rounds integer;
  v_total_guesses integer;
  v_total_winners integer;  -- distinct winner count
  v_total_coins integer;   -- sum of all coin amounts in the family this week
  v_top_winner record;
  v_top_winner_name text;
BEGIN
  -- Total rounds revealed in the last 7 days for this family.
  SELECT COUNT(*) INTO v_total_rounds
  FROM "pb_v1_rounds"
  WHERE family_id = p_family_id
    AND status = 'revealed'
    AND reveal_at >= v_since;

  -- Total guesses submitted in the last 7 days for this family.
  SELECT COUNT(*) INTO v_total_guesses
  FROM "pb_v1_guesses" g
  JOIN "pb_v1_rounds" r ON r.id = g.round_id
  WHERE r.family_id = p_family_id
    AND g.submitted_at >= v_since;

  -- Distinct winners in the last 7 days.
  SELECT COUNT(DISTINCT user_id) INTO v_total_winners
  FROM "pb_v1_win_streaks"
  WHERE family_id = p_family_id
    AND updated_at >= v_since
    AND current_streak > 0;

  -- Total coins earned in the last 7 days (sum of positive amounts
  -- in the ledger for this family).
  SELECT COALESCE(SUM(amount), 0) INTO v_total_coins
  FROM "coin_ledger"
  WHERE "familyId" = p_family_id
    AND amount > 0
    AND "createdAt" >= v_since;

  -- Top winner: the family member with the highest current streak.
  -- (We use current streak rather than wins-this-week because the
  -- streak is the more engaging stat for the recap copy.)
  SELECT user_id, current_streak INTO v_top_winner
  FROM "pb_v1_win_streaks"
  WHERE family_id = p_family_id
    AND current_streak > 0
  ORDER BY current_streak DESC, best_streak DESC
  LIMIT 1;

  IF v_top_winner IS NOT NULL THEN
    SELECT name INTO v_top_winner_name FROM "User" WHERE id = v_top_winner.user_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'since', v_since,
    'total_rounds', v_total_rounds,
    'total_guesses', v_total_guesses,
    'total_winners', v_total_winners,
    'total_coins_earned', v_total_coins,
    'top_winner_user_id', COALESCE(v_top_winner.user_id, NULL),
    'top_winner_name', COALESCE(v_top_winner_name, NULL),
    'top_winner_streak', COALESCE(v_top_winner.current_streak, 0)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_weekly_recap(text) TO authenticated;
