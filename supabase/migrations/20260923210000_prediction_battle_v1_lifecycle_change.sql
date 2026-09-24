-- 20260923210000_prediction_battle_v1_lifecycle_change.sql
--
-- Phase 3.17 — Lifecycle change per user request:
--
-- OLD lifecycle:
--   8 AM IST: new round opens (can submit)
--   9 PM IST: reveal tick fires, round goes to 'revealed'
--   9 PM – 8 AM next day: get_next_question returns 'past_reveal_time'
--     → card shows NOTHING. User must navigate to history to see winner.
--
-- NEW lifecycle (what the user wants):
--   8 AM IST: new round opens (can submit) — UNCHANGED
--   9:30 PM IST: reveal tick fires, round goes to 'revealed' (was 9 PM)
--   9:30 PM – 8 AM next day: get_next_question returns the REVEALED
--     round so the card keeps showing the winner until the next 8 AM
--     refresh. The user sees the winner on the family hub without
--     having to navigate anywhere.
--   8 AM IST next day: daily tick creates a NEW round, which
--     replaces the revealed one on the card.
--
-- Why this matters
--   The user explicitly said "prediction battle is not actually a
--   game, it's like streaks. It should reset new questions at 8 AM
--   and at 9:30 PM it should show the winners till the next 8 AM
--   refresh." The old behavior of showing nothing between 9 PM and
--   8 AM defeated the engagement loop — users had no reason to open
--   the app in that 11-hour window.
--
-- Changes
-- 1. fn_pb_v1_get_next_question: when no open round exists, fall
--    back to the most-recently-revealed round (created today OR
--    yesterday if we're before 8 AM). Return it with status='revealed'
--    so the Flutter card renders the winner summary.
-- 2. Reveal time: 21 hours → 21.5 hours (9:30 PM IST).
-- 3. pg_cron reveal-tick: 30 15 * * * (9 PM UTC = 9:30 PM IST? No:
--    9:30 PM IST = 16:00 UTC. Let me compute: IST = UTC + 5:30, so
--    9:30 PM IST = 16:00 UTC). Update to '0 16 * * *'.
-- 4. The streak-in-danger window in NestJS is 8:30–9:00 PM IST for
--    the 9 PM reveal. With a 9:30 PM reveal, the danger window
--    should be 8:30–9:30 PM IST. That's a NestJS code change, not
--    SQL — done in a separate commit.

CREATE OR REPLACE FUNCTION public.fn_pb_v1_get_next_question(p_family_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question record;
  v_round_id text;
  v_today_start timestamptz;
  v_reveal_at timestamptz;
  v_existing_round record;
  v_revealed_round record;
  v_user_id text := auth.uid()::text;
  v_target_difficulty integer := 2;
  v_win_count integer := 0;
  v_played_count integer := 0;
  v_win_rate float := 0.5;
BEGIN
  -- 1. Check if family already has an active (open) round
  SELECT * INTO v_existing_round FROM "pb_v1_rounds"
  WHERE family_id = p_family_id AND status = 'open'
  ORDER BY created_at DESC LIMIT 1;

  IF FOUND THEN
    SELECT row_to_json(q) INTO v_question FROM "pb_v1_questions" q WHERE q.id = v_existing_round.question_id;
    RETURN jsonb_build_object(
      'ok', true,
      'round', row_to_json(v_existing_round),
      'question', v_question
    );
  END IF;

  -- 2. Compute today's reveal time: 9:30 PM IST = 4:00 PM UTC
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';
  v_reveal_at := v_today_start + interval '21 hours 30 minutes';

  -- 3. NEW (Phase 3.17): If we're past today's reveal time, fall back
  --    to the most-recently-revealed round so the card keeps showing
  --    the winner until the next 8 AM refresh. The daily tick at 8 AM
  --    IST will create a new open round, which the next call to this
  --    function returns (via the step-1 check above).
  IF now() >= v_reveal_at THEN
    -- Look for a revealed round from today OR yesterday (in case the
    -- daily tick hasn't fired yet for the new day).
    SELECT * INTO v_revealed_round FROM "pb_v1_rounds"
    WHERE family_id = p_family_id
      AND status = 'revealed'
      AND reveal_at >= v_today_start - interval '24 hours'
    ORDER BY reveal_at DESC LIMIT 1;

    IF FOUND THEN
      SELECT row_to_json(q) INTO v_question FROM "pb_v1_questions" q WHERE q.id = v_revealed_round.question_id;
      RETURN jsonb_build_object(
        'ok', true,
        'round', row_to_json(v_revealed_round),
        'question', v_question
      );
    END IF;

    -- No revealed round either (rare — e.g., brand-new family that
    -- has never had a round). Return the old behavior so the Flutter
    -- client can show the empty state.
    RETURN jsonb_build_object('ok', false, 'reason', 'past_reveal_time');
  END IF;

  -- 4. Adaptive difficulty (preserved from Phase 3.13)
  IF v_user_id IS NOT NULL THEN
    SELECT
      COUNT(*) FILTER (WHERE g.guess_value IS NOT NULL),
      COUNT(*) FILTER (WHERE g.guess_value IS NOT NULL
        AND ABS(g.guess_value - q.correct_answer) =
          (SELECT MIN(ABS(g2.guess_value - q2.correct_answer))
           FROM "pb_v1_guesses" g2
           JOIN "pb_v1_rounds" r2 ON r2.id = g2.round_id
           JOIN "pb_v1_questions" q2 ON q2.id = r2.question_id
           WHERE r2.family_id = p_family_id AND r2.status = 'revealed'
             AND r2.reveal_at >= now() - interval '30 days')
          )
    INTO v_played_count, v_win_count
    FROM "pb_v1_guesses" g
    JOIN "pb_v1_rounds" r ON r.id = g.round_id
    JOIN "pb_v1_questions" q ON q.id = r.question_id
    WHERE r.family_id = p_family_id AND r.status = 'revealed'
      AND g.user_id = v_user_id
      AND r.reveal_at >= now() - interval '30 days';

    IF v_played_count >= 3 THEN
      v_win_rate := v_win_count::float / v_played_count::float;
      IF v_win_rate < 0.33 THEN
        v_target_difficulty := 1;
      ELSIF v_win_rate > 0.66 THEN
        v_target_difficulty := 3;
      ELSE
        v_target_difficulty := 2;
      END IF;
    END IF;
  END IF;

  -- 5. Category-weighted + difficulty-aware selection (preserved)
  WITH category_counts AS (
    SELECT q.category, COUNT(*) AS cat_count
    FROM "pb_v1_served_questions" sq
    JOIN "pb_v1_questions" q ON q.id = sq.question_id
    WHERE sq.family_id = p_family_id
      AND sq.shown_at > now() - interval '30 days'
    GROUP BY q.category
  ),
  eligible AS (
    SELECT q.*, COALESCE(cc.cat_count, 0) AS cat_count,
           ABS(q.difficulty - v_target_difficulty) AS difficulty_distance
    FROM "pb_v1_questions" q
    LEFT JOIN category_counts cc ON cc.category = q.category
    WHERE q.is_active = true
      AND q.id NOT IN (
        SELECT question_id FROM "pb_v1_served_questions"
        WHERE family_id = p_family_id AND shown_at > now() - interval '6 months'
      )
  )
  SELECT * INTO v_question FROM eligible
  ORDER BY difficulty_distance ASC, cat_count ASC, random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT q.* INTO v_question FROM "pb_v1_questions" q
    WHERE q.is_active = true
    ORDER BY difficulty_distance ASC, (
      SELECT COALESCE(MAX(sq.shown_at), '1970-01-01'::timestamptz)
      FROM "pb_v1_served_questions" sq
      WHERE sq.family_id = p_family_id AND sq.question_id = q.id
    ) ASC, random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_questions_available');
  END IF;

  -- 6. Create round + record served (preserved)
  v_round_id := gen_random_uuid()::text;
  INSERT INTO "pb_v1_rounds" (id, family_id, question_id, opens_at, reveal_at, status)
  VALUES (v_round_id, p_family_id, v_question.id, now(), v_reveal_at, 'open');

  INSERT INTO "pb_v1_served_questions" (family_id, question_id, shown_at)
  VALUES (p_family_id, v_question.id, now())
  ON CONFLICT (family_id, question_id) DO UPDATE SET shown_at = now();

  RETURN jsonb_build_object(
    'ok', true,
    'round', jsonb_build_object(
      'id', v_round_id, 'family_id', p_family_id, 'question_id', v_question.id,
      'opens_at', now(), 'reveal_at', v_reveal_at, 'status', 'open', 'created_at', now()
    ),
    'question', row_to_json(v_question)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_next_question(text) TO authenticated;

-- ── Update the daily_tick's reveal_at to 9:30 PM IST ────────────────
-- The daily tick creates rounds. We need its reveal_at to match the
-- new 9:30 PM IST time so the Flutter card's countdown is correct.

CREATE OR REPLACE FUNCTION public.fn_pb_v1_daily_tick()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family record;
  v_today_start timestamptz;
  v_reveal_at timestamptz;
BEGIN
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';
  v_reveal_at := v_today_start + interval '21 hours 30 minutes'; -- 9:30 PM IST

  -- Only create rounds if we're before today's reveal time
  IF now() >= v_reveal_at THEN RETURN; END IF;

  FOR v_family IN
    SELECT DISTINCT family_id FROM "pb_v1_served_questions"
    UNION
    SELECT DISTINCT family_id FROM "pb_v1_rounds"
  LOOP
    IF EXISTS (SELECT 1 FROM "pb_v1_rounds" WHERE family_id = v_family.family_id AND status = 'open') THEN
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM "pb_v1_rounds" WHERE family_id = v_family.family_id AND status = 'revealed' AND created_at >= v_today_start) THEN
      CONTINUE;
    END IF;
    PERFORM public.fn_pb_v1_get_next_question(v_family.family_id);
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_daily_tick() TO authenticated;

-- ── Reschedule the cron jobs for the new times ──────────────────────
-- Daily tick (new round creation): 8 AM IST = 2:30 AM UTC. UNCHANGED.
-- Reveal tick: 9:30 PM IST = 4:00 PM UTC (was 3:30 PM UTC for 9 PM IST).
DO $$
BEGIN
  PERFORM cron.unschedule('pb-v1-daily-tick');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
  PERFORM cron.unschedule('pb-v1-reveal-tick');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
  PERFORM cron.unschedule('pb-v1-recovery-tick');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Daily round creation at 8 AM IST (2:30 AM UTC) — unchanged
SELECT cron.schedule('pb-v1-daily-tick', '30 2 * * *', $$ SELECT public.fn_pb_v1_daily_tick(); $$);

-- Reveal transition at 9:30 PM IST (4:00 PM UTC) — CHANGED from 3:30 PM UTC
SELECT cron.schedule('pb-v1-reveal-tick', '0 16 * * *', $$ SELECT public.fn_pb_v1_reveal_all_due(); $$);

-- Recovery check every 15 minutes — unchanged
SELECT cron.schedule('pb-v1-recovery-tick', '*/15 * * * *', $$ SELECT public.fn_pb_v1_daily_tick(); $$);
