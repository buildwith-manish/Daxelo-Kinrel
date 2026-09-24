-- 20260924000000_fix_question_row_to_json.sql
--
-- Fix: fn_pb_v1_get_next_question returns the question wrapped in
-- an extra "row_to_json" key when an existing round is returned.
--
-- The problem:
--   SELECT row_to_json(q) INTO v_question FROM pb_v1_questions q ...
--   stores {"row_to_json": {...}} in v_question (because row_to_json
--   in a SELECT context returns a single column named "row_to_json").
--   Then 'question', v_question puts that wrapper into the JSON
--   response, so the Flutter client sees:
--     "question": {"row_to_json": {"question_text": "..."}}
--   instead of:
--     "question": {"question_text": "..."}
--
-- The fix: use `to_jsonb(q.*)` instead of `row_to_json(q)`. This
-- produces the flat JSON object directly, without the wrapper.
--
-- Two places to fix: the existing-round path (line 68) and the
-- revealed-round fallback path (line 95).

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
    -- FIX: use to_jsonb(q.*) instead of row_to_json(q) to avoid the
    -- {"row_to_json": {...}} wrapper that was hiding the question_text
    -- from the Flutter client.
    SELECT to_jsonb(q.*) INTO v_question FROM "pb_v1_questions" q WHERE q.id = v_existing_round.question_id;
    RETURN jsonb_build_object(
      'ok', true,
      'round', to_jsonb(v_existing_round),
      'question', v_question
    );
  END IF;

  -- 2. Compute today's reveal time: 9:30 PM IST = 4:00 PM UTC
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';
  v_reveal_at := v_today_start + interval '21 hours 30 minutes';

  -- 3. If we're past today's reveal time, fall back to the
  --    most-recently-revealed round so the card keeps showing the
  --    winner until the next 8 AM refresh.
  IF now() >= v_reveal_at THEN
    SELECT * INTO v_revealed_round FROM "pb_v1_rounds"
    WHERE family_id = p_family_id
      AND status = 'revealed'
      AND reveal_at >= v_today_start - interval '24 hours'
    ORDER BY reveal_at DESC LIMIT 1;

    IF FOUND THEN
      -- FIX: same to_jsonb(q.*) fix as above.
      SELECT to_jsonb(q.*) INTO v_question FROM "pb_v1_questions" q WHERE q.id = v_revealed_round.question_id;
      RETURN jsonb_build_object(
        'ok', true,
        'round', to_jsonb(v_revealed_round),
        'question', v_question
      );
    END IF;

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
    ORDER BY (
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
    'question', to_jsonb(v_question)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_next_question(text) TO authenticated;
