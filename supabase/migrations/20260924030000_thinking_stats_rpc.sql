-- 20260924030000_thinking_stats_rpc.sql
--
-- Phase 3.24 — Thinking of You stats RPC.
--
-- Returns the user's "Thinking of You" stats for a family:
--   - total_sent: how many taps the user has ever sent in this family
--   - total_received: how many taps the user has ever received in this family
--   - daily_streak: how many consecutive days the user has sent at least 1 tap
--
-- The stats are used on the Family Ring Widget header to show:
--   "🔥 5 days · 12 sent · 8 received"
--
-- This drives daily return (streak/commitment) + social proof (sent/received counts).

CREATE OR REPLACE FUNCTION public.fn_get_thinking_stats(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_sent integer := 0;
  v_total_received integer := 0;
  v_daily_streak integer := 0;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_check_date date;
  v_found_today boolean;
BEGIN
  -- Total sent
  SELECT COUNT(*) INTO v_total_sent
  FROM "ThinkingOfYouTap"
  WHERE "senderId" = p_user_id
    AND "familyId" = p_family_id;

  -- Total received
  SELECT COUNT(*) INTO v_total_received
  FROM "ThinkingOfYouTap"
  WHERE "receiverId" = p_user_id
    AND "familyId" = p_family_id;

  -- Daily streak: count consecutive days (ending today or yesterday)
  -- where the user sent at least 1 tap.
  -- Start from today and walk backwards. If the user sent a tap today,
  -- the streak includes today. If not, check yesterday. If neither, streak = 0.
  v_check_date := v_today;
  v_daily_streak := 0;

  -- Check today first
  SELECT EXISTS(
    SELECT 1 FROM "ThinkingOfYouTap"
    WHERE "senderId" = p_user_id
      AND "familyId" = p_family_id
      AND ("createdAt" AT TIME ZONE 'Asia/Kolkata')::date = v_check_date
  ) INTO v_found_today;

  -- If nothing today, check yesterday (grace period for late-night IST)
  IF NOT v_found_today THEN
    v_check_date := v_check_date - 1;
    SELECT EXISTS(
      SELECT 1 FROM "ThinkingOfYouTap"
      WHERE "senderId" = p_user_id
        AND "familyId" = p_family_id
        AND ("createdAt" AT TIME ZONE 'Asia/Kolkata')::date = v_check_date
    ) INTO v_found_today;
    IF NOT v_found_today THEN
      -- No tap today or yesterday — streak is 0
      v_daily_streak := 0;
      -- But still return the sent/received counts
      RETURN jsonb_build_object(
        'total_sent', v_total_sent,
        'total_received', v_total_received,
        'daily_streak', v_daily_streak
      );
    END IF;
  END IF;

  -- Walk backwards from the check_date, counting consecutive days
  LOOP
    v_check_date := v_check_date - 1;
    SELECT EXISTS(
      SELECT 1 FROM "ThinkingOfYouTap"
      WHERE "senderId" = p_user_id
        AND "familyId" = p_family_id
        AND ("createdAt" AT TIME ZONE 'Asia/Kolkata')::date = v_check_date
    ) INTO v_found_today;

    EXIT WHEN NOT v_found_today;
    v_daily_streak := v_daily_streak + 1;
  END LOOP;

  -- The streak counts the number of consecutive days (including the
  -- starting day). If we started from today and walked back N days,
  -- the streak is N+1 (today + N previous days). But we already
  -- incremented v_daily_streak for each day found, so we need to add
  -- 1 for the starting day.
  v_daily_streak := v_daily_streak + 1;

  RETURN jsonb_build_object(
    'total_sent', v_total_sent,
    'total_received', v_total_received,
    'daily_streak', v_daily_streak
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_thinking_stats(text, text) TO authenticated;
