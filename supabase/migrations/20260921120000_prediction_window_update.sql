-- 20260921120000_prediction_window_update.sql
--
-- Update the Prediction Battle availability window from the previous
-- relative-interval model (lockAt = createdAt + 12h, revealAt = createdAt + 24h)
-- to a fixed daily window:
--
--   OPEN:   8:00 AM IST  (2:30 AM UTC)
--   CLOSE:  9:30 PM IST  (4:00 PM UTC)  — predictions lock
--   REVEAL: 9:30 PM IST  (4:00 PM UTC)  — results revealed immediately at close
--
-- The window is in IST (Asia/Kolkata) because the app targets Indian
-- families. The SQL uses AT TIME ZONE 'Asia/Kolkata' to compute the
-- correct UTC timestamps for storage.
--
-- This migration also fixes a pre-existing bug in fn_prediction_get_active:
-- line 110-114 had a SELECT jsonb_build_object(...) without INTO, causing
-- "query has no destination for result data" — the function would throw
-- an error every time an existing active round was found. That line is
-- removed in the replacement below.

CREATE OR REPLACE FUNCTION public.fn_prediction_get_active(p_family_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing record;
  v_question record;
  v_round_id text;
  v_now timestamptz := now();
  v_lock_at timestamptz;   -- today 9:30 PM IST (close + reveal)
  v_window_open timestamptz; -- today 8:00 AM IST
  v_today_start timestamptz; -- today 00:00 IST
BEGIN
  -- ── Compute today's window boundaries in IST, converted to UTC ──
  -- IST = UTC+5:30. 8:00 AM IST = 2:30 AM UTC. 9:30 PM IST = 4:00 PM UTC.
  v_today_start := date_trunc('day', v_now AT TIME ZONE 'Asia/Kolkata')
                   AT TIME ZONE 'Asia/Kolkata';
  v_window_open := v_today_start + interval '8 hours';      -- 8:00 AM IST
  v_lock_at     := v_today_start + interval '21 hours 30 minutes'; -- 9:30 PM IST

  -- ── 1. Check for an existing active/open/locked/pending round ──
  SELECT * INTO v_existing FROM "prediction_rounds"
  WHERE "familyId" = p_family_id AND status IN ('open','locked','pending')
  ORDER BY "createdAt" DESC LIMIT 1;

  IF FOUND THEN
    -- Return the existing round + question + participation count.
    -- (Bug fix: the old function had a stray SELECT jsonb_build_object(...)
    -- without INTO here that caused "query has no destination for result
    -- data". Removed.)
    RETURN jsonb_build_object(
      'round', row_to_json(v_existing),
      'question', (SELECT row_to_json(q) FROM "prediction_questions" q WHERE q.id = v_existing."questionId"),
      'participationCount', (SELECT COUNT(*) FROM "prediction_submissions" WHERE "roundId" = v_existing.id)
    );
  END IF;

  -- ── 2. No active round. Determine where we are relative to today's window. ──

  -- Before 8:00 AM IST → window hasn't opened yet.
  IF v_now < v_window_open THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'before_window');
  END IF;

  -- After 9:30 PM IST → window has closed. Check for a resolved round
  -- from today (the tick function should have resolved it by now).
  IF v_now >= v_lock_at THEN
    SELECT * INTO v_existing FROM "prediction_rounds"
    WHERE "familyId" = p_family_id AND status = 'resolved'
      AND "createdAt" >= v_today_start
    ORDER BY "resolvedAt" DESC LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'round', row_to_json(v_existing),
        'question', (SELECT row_to_json(q) FROM "prediction_questions" q WHERE q.id = v_existing."questionId"),
        'participationCount', (SELECT COUNT(*) FROM "prediction_submissions" WHERE "roundId" = v_existing.id)
      );
    END IF;

    -- No resolved round today (e.g., tick hasn't run, or no answer).
    -- Return after_window so the client can show "Closed for today".
    RETURN jsonb_build_object('ok', false, 'reason', 'after_window');
  END IF;

  -- ── 3. We're within the window (8 AM – 9:30 PM IST). Create a new round. ──

  -- Pick the next unseen question (priority: unseen → not same category
  -- as last → highest quality).
  SELECT * INTO v_question FROM "prediction_questions"
  WHERE "isActive" = true
    AND id NOT IN (SELECT "questionId" FROM "prediction_history" WHERE "familyId" = p_family_id)
  ORDER BY
    CASE
      WHEN "category" = (SELECT q."category" FROM "prediction_rounds" r
        JOIN "prediction_questions" q ON q.id = r."questionId"
        WHERE r."familyId" = p_family_id AND r.status = 'resolved'
        ORDER BY r."resolvedAt" DESC LIMIT 1)
      THEN 1 ELSE 0
    END,
    "qualityScore" DESC,
    random()
  LIMIT 1;

  -- If pool exhausted, reuse oldest (but not within 365 days).
  IF NOT FOUND THEN
    SELECT * INTO v_question FROM "prediction_questions"
    WHERE "isActive" = true
      AND id NOT IN (
        SELECT "questionId" FROM "prediction_history"
        WHERE "familyId" = p_family_id AND "shownAt" > now() - interval '365 days'
      )
    ORDER BY "qualityScore" DESC, random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_questions_available');
  END IF;

  -- Create the round with lockAt = revealAt = today 9:30 PM IST.
  -- Setting revealAt = lockAt means the reveal happens at close time
  -- (the tick function will transition open → locked → pending → resolved
  -- in a single tick call once now() passes lockAt).
  v_round_id := gen_random_uuid()::text;
  INSERT INTO "prediction_rounds" (id, "familyId", "questionId", status, "lockAt", "revealAt", "isLegendary")
  VALUES (v_round_id, p_family_id, v_question.id, 'open',
    v_lock_at, v_lock_at, v_question."isLegendary");

  -- Record in history
  INSERT INTO "prediction_history" ("familyId", "questionId", "roundId", "shownAt")
  VALUES (p_family_id, v_question.id, v_round_id, v_now)
  ON CONFLICT ("familyId", "questionId") DO NOTHING;

  RETURN jsonb_build_object(
    'ok', true,
    'round', jsonb_build_object(
      'id', v_round_id, 'familyId', p_family_id, 'questionId', v_question.id,
      'status', 'open', 'lockAt', v_lock_at,
      'revealAt', v_lock_at, 'isLegendary', v_question."isLegendary",
      'createdAt', v_now
    ),
    'question', row_to_json(v_question),
    'participationCount', 0
  );
END;
$$;

-- The fn_prediction_tick function does NOT need changes. It already
-- transitions states based on lockAt/revealAt:
--   open → locked   when lockAt < now()
--   locked → pending when revealAt < now()
--   pending → resolved when revealAt < now() AND answer exists
--
-- With lockAt = revealAt = 9:30 PM IST, all three transitions fire in
-- a single tick call once now() passes 9:30 PM — the round goes from
-- open → resolved in one tick (within 30s of 9:30 PM, since the provider
-- calls tick every 30s).
--
-- Verification (manual reasoning, not a SQL test):
--   At 9:30:00 PM IST (= 4:00:00 PM UTC), the provider's 30s tick fires.
--   The tick function runs:
--     1. UPDATE ... SET status='locked' WHERE status='open' AND lockAt < now()
--        → round transitions open → locked (lockAt = 9:30 PM < now = 9:30:05 PM)
--     2. UPDATE ... SET status='pending' WHERE status='locked' AND revealAt < now()
--        → round transitions locked → pending (revealAt = 9:30 PM < now = 9:30:05 PM)
--     3. SELECT ... WHERE status='pending' AND revealAt < now()
--        → round is pending, revealAt < now, and the question has a correctAnswer
--        → fn_prediction_resolve(v_round.id) is called
--        → round transitions pending → resolved
--   All three happen in one tick call. The reveal triggers at 9:30 PM IST. ✓
