-- 20260922160000_prediction_battle_v1_scheduled.sql
--
-- Prediction Battle v1 — Scheduled Mode Only
--
-- Replaces the previous on-demand prediction_battle system with a
-- backend-scheduled, numeric-estimation guessing game with:
-- - Per-family question rotation with anti-repeat (6-month cooldown)
-- - Category-weighted question selection
-- - Backend-enforced reveal timing (no client-dependent transitions)
-- - Percentage-based scoring for large numbers, absolute for small
-- - Coin economy integration (participation, winner, close-guess, streak)
-- - Family Moments auto-post on reveal
--
-- This migration creates NEW tables (pb_v1_*) alongside the existing
-- prediction_battle tables. The existing tables will be deprecated
-- after v1 is verified in production.

-- ═════════════════════════════════════════════════════════════════════
-- 1. Schema
-- ═════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "pb_v1_questions" (
  id              TEXT PRIMARY KEY,
  question_text   TEXT NOT NULL,
  correct_answer  NUMERIC NOT NULL,
  unit_label      TEXT NOT NULL DEFAULT '',
  category        TEXT NOT NULL DEFAULT 'general',
  fun_fact_text    TEXT NOT NULL DEFAULT '',
  min_bound       NUMERIC,
  max_bound       NUMERIC,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pb_v1_q_category ON "pb_v1_questions" ("category", "is_active");

CREATE TABLE IF NOT EXISTS "pb_v1_rounds" (
  id            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  family_id     TEXT NOT NULL,
  question_id   TEXT NOT NULL REFERENCES "pb_v1_questions"(id),
  opens_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  reveal_at     TIMESTAMPTZ NOT NULL,
  status        TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'revealed')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pb_v1_r_family ON "pb_v1_rounds" ("family_id", "created_at" DESC);
CREATE INDEX IF NOT EXISTS idx_pb_v1_r_status ON "pb_v1_rounds" ("status", "reveal_at");

CREATE TABLE IF NOT EXISTS "pb_v1_guesses" (
  round_id      TEXT NOT NULL REFERENCES "pb_v1_rounds"(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL,
  guess_value   NUMERIC NOT NULL,
  submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("round_id", "user_id")
);
CREATE INDEX IF NOT EXISTS idx_pb_v1_g_round ON "pb_v1_guesses" ("round_id");

CREATE TABLE IF NOT EXISTS "pb_v1_served_questions" (
  family_id     TEXT NOT NULL,
  question_id   TEXT NOT NULL REFERENCES "pb_v1_questions"(id),
  shown_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("family_id", "question_id")
);
CREATE INDEX IF NOT EXISTS idx_pb_v1_sq_family ON "pb_v1_served_questions" ("family_id", "shown_at" DESC);

CREATE TABLE IF NOT EXISTS "pb_v1_win_streaks" (
  user_id       TEXT NOT NULL,
  family_id     TEXT NOT NULL,
  current_streak INTEGER NOT NULL DEFAULT 0,
  best_streak   INTEGER NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("user_id", "family_id")
);

-- RLS
ALTER TABLE "pb_v1_questions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pb_v1_rounds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pb_v1_guesses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pb_v1_served_questions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pb_v1_win_streaks" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pb_v1_q_select_all" ON "pb_v1_questions" FOR SELECT TO authenticated USING (true);
CREATE POLICY "pb_v1_r_select_family" ON "pb_v1_rounds" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("family_id"));
CREATE POLICY "pb_v1_g_select_family" ON "pb_v1_guesses" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "pb_v1_rounds" r WHERE r.id = "pb_v1_guesses"."round_id" AND public.fn_user_is_family_member(r."family_id")));
CREATE POLICY "pb_v1_g_insert_self" ON "pb_v1_guesses" FOR INSERT TO authenticated WITH CHECK ("user_id" = auth.uid()::text);
CREATE POLICY "pb_v1_sq_select_family" ON "pb_v1_served_questions" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("family_id"));
CREATE POLICY "pb_v1_ws_select_self" ON "pb_v1_win_streaks" FOR SELECT TO authenticated USING ("user_id" = auth.uid()::text OR public.fn_user_is_family_member("family_id"));

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE "pb_v1_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "pb_v1_guesses";
ALTER TABLE "pb_v1_rounds" REPLICA IDENTITY FULL;
ALTER TABLE "pb_v1_guesses" REPLICA IDENTITY FULL;

-- ═════════════════════════════════════════════════════════════════════
-- 2. Question Selection RPC
-- ═════════════════════════════════════════════════════════════════════

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
BEGIN
  -- Check if family already has an active (open) round
  SELECT * INTO v_existing_round FROM "pb_v1_rounds"
  WHERE family_id = p_family_id AND status = 'open'
  ORDER BY created_at DESC LIMIT 1;

  IF FOUND THEN
    -- Return the existing round's question
    SELECT row_to_json(q) INTO v_question FROM "pb_v1_questions" q WHERE q.id = v_existing_round.question_id;
    RETURN jsonb_build_object(
      'ok', true,
      'round', row_to_json(v_existing_round),
      'question', v_question
    );
  END IF;

  -- Compute today's reveal time: 9 PM IST = 3:30 PM UTC
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';
  v_reveal_at := v_today_start + interval '21 hours';

  -- If we're already past today's reveal time, no new round today
  IF now() >= v_reveal_at THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'past_reveal_time');
  END IF;

  -- Category-weighted selection: pick from least-represented category
  -- in the last 30 days
  WITH category_counts AS (
    SELECT q.category, COUNT(*) AS cat_count
    FROM "pb_v1_served_questions" sq
    JOIN "pb_v1_questions" q ON q.id = sq.question_id
    WHERE sq.family_id = p_family_id
      AND sq.shown_at > now() - interval '30 days'
    GROUP BY q.category
  ),
  eligible AS (
    SELECT q.*, COALESCE(cc.cat_count, 0) AS cat_count
    FROM "pb_v1_questions" q
    LEFT JOIN category_counts cc ON cc.category = q.category
    WHERE q.is_active = true
      AND q.id NOT IN (
        SELECT question_id FROM "pb_v1_served_questions"
        WHERE family_id = p_family_id AND shown_at > now() - interval '6 months'
      )
  )
  SELECT * INTO v_question FROM eligible
  ORDER BY cat_count ASC, random() LIMIT 1;

  -- Fallback: if no eligible questions, ignore 6-month cooldown, pick least-recently-shown
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

  -- Create round + record served in same transaction
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

-- ═════════════════════════════════════════════════════════════════════
-- 3. Submit Guess RPC
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_submit_guess(
  p_round_id text, p_user_id text, p_guess_value numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_round record;
  v_question record;
  v_warning boolean := false;
BEGIN
  SELECT * INTO v_round FROM "pb_v1_rounds" WHERE id = p_round_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_round.status != 'open' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_open'); END IF;
  IF now() >= v_round.reveal_at THEN RETURN jsonb_build_object('ok', false, 'reason', 'past_reveal'); END IF;

  -- Check if already guessed (one per person, no changing)
  IF EXISTS (SELECT 1 FROM "pb_v1_guesses" WHERE round_id = p_round_id AND user_id = p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_guessed');
  END IF;

  -- Soft-validate against min/max bounds
  SELECT * INTO v_question FROM "pb_v1_questions" WHERE id = v_round.question_id;
  IF v_question.min_bound IS NOT NULL AND p_guess_value < v_question.min_bound THEN
    v_warning := true;
  END IF;
  IF v_question.max_bound IS NOT NULL AND p_guess_value > v_question.max_bound THEN
    v_warning := true;
  END IF;

  INSERT INTO "pb_v1_guesses" (round_id, user_id, guess_value, submitted_at)
  VALUES (p_round_id, p_user_id, p_guess_value, now());

  -- Award participation coins (best-effort — don't fail if coin RPC missing)
  BEGIN
    PERFORM public.fn_award_coins(p_user_id, v_round.family_id, 1, 'prediction_participation');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'warning', v_warning);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_submit_guess(text, text, numeric) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 4. Get Round Guesses RPC (reveal-gated)
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_get_round_guesses(
  p_round_id text, p_requesting_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_round record;
  v_question record;
  v_guesses jsonb;
  v_my_guess record;
  v_ranked jsonb;
  v_winner_ids text[];
BEGIN
  SELECT * INTO v_round FROM "pb_v1_rounds" WHERE id = p_round_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  SELECT * INTO v_question FROM "pb_v1_questions" WHERE id = v_round.question_id;

  -- BEFORE REVEAL: return ONLY the requesting user's own guess
  IF now() < v_round.reveal_at THEN
    SELECT * INTO v_my_guess FROM "pb_v1_guesses"
    WHERE round_id = p_round_id AND user_id = p_requesting_user_id;

    RETURN jsonb_build_object(
      'ok', true,
      'round', row_to_json(v_round),
      'my_guess', CASE WHEN FOUND THEN row_to_json(v_my_guess) ELSE NULL END,
      'revealed', false
    );
  END IF;

  -- AFTER REVEAL: return all guesses + correct_answer + fun_fact + ranking
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', g.user_id,
    'guess_value', g.guess_value,
    'submitted_at', g.submitted_at,
    'distance', CASE
      WHEN v_question.correct_answer > 1000 THEN
        ABS(g.guess_value - v_question.correct_answer) / v_question.correct_answer * 100
      ELSE
        ABS(g.guess_value - v_question.correct_answer)
    END
  ) ORDER BY (
    CASE
      WHEN v_question.correct_answer > 1000 THEN
        ABS(g.guess_value - v_question.correct_answer) / v_question.correct_answer
      ELSE
        ABS(g.guess_value - v_question.correct_answer)
    END
  )) INTO v_guesses
  FROM "pb_v1_guesses" g
  WHERE g.round_id = p_round_id;

  -- Identify winner(s) — smallest distance
  IF v_guesses IS NOT NULL AND jsonb_array_length(v_guesses) > 0 THEN
    SELECT array_agg(elem->>'user_id') INTO v_winner_ids
    FROM jsonb_array_elements(v_guesses) AS elem
    WHERE (elem->>'distance')::float = (
      SELECT min((e->>'distance')::float)
      FROM jsonb_array_elements(v_guesses) AS e
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'round', row_to_json(v_round),
    'question', row_to_json(v_question),
    'guesses', COALESCE(v_guesses, '[]'::jsonb),
    'winner_user_ids', COALESCE(to_jsonb(v_winner_ids), '[]'::jsonb),
    'revealed', true
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_round_guesses(text, text) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 5. Reveal Transition + Scoring (called by pg_cron)
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_reveal_all_due()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_round record;
  v_question record;
  v_guess record;
  v_correct numeric;
  v_distance float;
  v_min_distance float := 999999999.0;
  v_winners text[];
  v_margin float;
  v_winner_name text;
  v_streak record;
BEGIN
  FOR v_round IN
    SELECT * FROM "pb_v1_rounds"
    WHERE status = 'open' AND reveal_at <= now()
  LOOP
    SELECT * INTO v_question FROM "pb_v1_questions" WHERE id = v_round.question_id;
    v_correct := v_question.correct_answer;

    -- Find minimum distance (winner)
    v_min_distance := 999999999.0;
    v_winners := ARRAY[]::text[];
    FOR v_guess IN
      SELECT * FROM "pb_v1_guesses" WHERE round_id = v_round.id
    LOOP
      IF v_correct > 1000 THEN
        v_distance := ABS(v_guess.guess_value - v_correct) / v_correct * 100;
      ELSE
        v_distance := ABS(v_guess.guess_value - v_correct)::float;
      END IF;

      IF v_distance < v_min_distance THEN
        v_min_distance := v_distance;
        v_winners := ARRAY[v_guess.user_id];
      ELSIF v_distance = v_min_distance THEN
        v_winners := array_append(v_winners, v_guess.user_id);
      END IF;
    END LOOP;

    -- Transition round to revealed
    UPDATE "pb_v1_rounds" SET status = 'revealed' WHERE id = v_round.id;

    -- Award coins: winner bonus + close-guess consolation
    FOR v_guess IN
      SELECT * FROM "pb_v1_guesses" WHERE round_id = v_round.id
    LOOP
      IF v_correct > 1000 THEN
        v_distance := ABS(v_guess.guess_value - v_correct) / v_correct * 100;
      ELSE
        v_distance := ABS(v_guess.guess_value - v_correct)::float;
      END IF;

      IF v_winners @> ARRAY[v_guess.user_id] THEN
        -- Winner coin bonus
        BEGIN
          PERFORM public.fn_award_coins(v_guess.user_id, v_round.family_id, 10, 'prediction_winner');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- Update win streak
        INSERT INTO "pb_v1_win_streaks" (user_id, family_id, current_streak, best_streak, updated_at)
        VALUES (v_guess.user_id, v_round.family_id, 1, 1, now())
        ON CONFLICT (user_id, family_id) DO UPDATE SET
          current_streak = "pb_v1_win_streaks".current_streak + 1,
          best_streak = GREATEST("pb_v1_win_streaks".best_streak, "pb_v1_win_streaks".current_streak + 1),
          updated_at = now();

        -- Streak bonus at 3+
        IF (SELECT current_streak FROM "pb_v1_win_streaks" WHERE user_id = v_guess.user_id AND family_id = v_round.family_id) >= 3 THEN
          BEGIN
            PERFORM public.fn_award_coins(v_guess.user_id, v_round.family_id, 5, 'prediction_streak_bonus');
          EXCEPTION WHEN OTHERS THEN NULL;
          END;
        END IF;
      ELSIF v_distance <= v_min_distance * 2 AND v_min_distance > 0 THEN
        -- Close-guess consolation coin
        BEGIN
          PERFORM public.fn_award_coins(v_guess.user_id, v_round.family_id, 2, 'prediction_close_guess');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;

      -- Reset streak for non-winners
      IF NOT v_winners @> ARRAY[v_guess.user_id] THEN
        UPDATE "pb_v1_win_streaks" SET current_streak = 0, updated_at = now()
        WHERE user_id = v_guess.user_id AND family_id = v_round.family_id;
      END IF;
    END LOOP;

    -- Family Moments auto-post (best-effort)
    BEGIN
      v_margin := v_min_distance;
      v_winner_name := COALESCE(
        (SELECT name FROM "User" WHERE id = v_winners[1]),
        (SELECT u.name FROM "User" u WHERE u.id = v_winners[1]),
        'Someone'
      );
      -- Insert into family_moments if table exists
      INSERT INTO "family_moments" ("familyId", "userId", "type", "title", "body", "createdAt")
      SELECT v_round.family_id, v_winners[1], 'prediction_battle',
        CASE WHEN array_length(v_winners, 1) > 1 THEN
          v_winner_name || ' and others tied for closest'
        ELSE
          v_winner_name || ' was closest'
        END,
        CASE WHEN v_correct > 1000 THEN
          'Off by only ' || v_margin::text || '% on "' || v_question.question_text || '" 🎯'
        ELSE
          'Off by only ' || v_margin::text || ' on "' || v_question.question_text || '" 🎯'
        END || COALESCE(' ' || v_question.fun_fact_text, ''),
        now()
      WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'family_moments');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_reveal_all_due() TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 6. Daily Round Creation (pg_cron)
-- ═════════════════════════════════════════════════════════════════════

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
  v_reveal_at := v_today_start + interval '21 hours'; -- 9 PM IST

  -- Only create rounds if we're before today's reveal time
  IF now() >= v_reveal_at THEN RETURN; END IF;

  -- For every family that has played before (has pb_v1_served_questions or pb_v1_rounds)
  FOR v_family IN
    SELECT DISTINCT family_id FROM "pb_v1_served_questions"
    UNION
    SELECT DISTINCT family_id FROM "pb_v1_rounds"
  LOOP
    -- Skip if already has an open round
    IF EXISTS (SELECT 1 FROM "pb_v1_rounds" WHERE family_id = v_family.family_id AND status = 'open') THEN
      CONTINUE;
    END IF;
    -- Skip if already has a revealed round created today
    IF EXISTS (SELECT 1 FROM "pb_v1_rounds" WHERE family_id = v_family.family_id AND status = 'revealed' AND created_at >= v_today_start) THEN
      CONTINUE;
    END IF;
    -- Create a new round
    PERFORM public.fn_pb_v1_get_next_question(v_family.family_id);
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_daily_tick() TO authenticated;

-- pg_cron schedules
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA cron;

-- Unschedule any previous prediction v1 cron jobs (idempotent — wrapped
-- in exception blocks so first-run doesn't fail with "could not find
-- valid entry for job"). pg_cron's unschedule raises an exception if
-- the job doesn't exist; there is no IF EXISTS variant.
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

-- Daily round creation at 8 AM IST (2:30 AM UTC)
SELECT cron.schedule('pb-v1-daily-tick', '30 2 * * *', $$ SELECT public.fn_pb_v1_daily_tick(); $$);

-- Reveal transition at 9 PM IST (3:30 PM UTC)
SELECT cron.schedule('pb-v1-reveal-tick', '30 15 * * *', $$ SELECT public.fn_pb_v1_reveal_all_due(); $$);

-- Recovery check every 15 minutes
SELECT cron.schedule('pb-v1-recovery-tick', '*/15 * * * *', $$ SELECT public.fn_pb_v1_daily_tick(); $$);

-- ═════════════════════════════════════════════════════════════════════
-- 7. Seed Questions (50 across 8 categories)
-- ═════════════════════════════════════════════════════════════════════

INSERT INTO "pb_v1_questions" (id, question_text, correct_answer, unit_label, category, fun_fact_text, min_bound, max_bound, is_active) VALUES
-- Nature
('pbq-001', 'How many species of trees are estimated to exist on Earth?', 73500, 'species', 'Nature', ' Brazil alone has over 7,500 tree species!', 1000, 500000, true),
('pbq-002', 'How many hearts does an octopus have?', 3, 'hearts', 'Nature', ' Two pump blood to the gills, one to the body.', 1, 10, true),
('pbq-003', 'How many bones does a newborn baby have?', 300, 'bones', 'Nature', ' Adults have 206 — many fuse together as we grow.', 100, 500, true),
('pbq-004', 'How many times does a hummingbird flap its wings per second?', 80, 'flaps/sec', 'Nature', ' The bee hummingbird can flap up to 200 times per second!', 10, 300, true),
('pbq-005', 'How many teeth can a great white shark have in its lifetime?', 30000, 'teeth', 'Nature', ' They go through about 30,000 teeth in a lifetime!', 1000, 100000, true),
('pbq-006', 'How many legs does a millipede typically have?', 750, 'legs', 'Nature', ' Despite the name, no millipede has exactly 1000 legs.', 100, 2000, true),
('pbq-007', 'How many days can a camel go without water?', 15, 'days', 'Nature', ' Their humps store fat, not water!', 3, 30, true),
-- Money
('pbq-008', 'How many rupees is a 1-gram gold coin (approx, 2024)?', 7500, 'rupees', 'Money', ' Gold prices fluctuate daily.', 1000, 20000, true),
('pbq-009', 'How much did the most expensive painting ever sold cost (in millions USD)?', 450, 'million USD', 'Money', ' Salvator Mundi by Leonardo da Vinci.', 100, 1000, true),
('pbq-010', 'How many zeros are in 1 trillion (Indian system)?', 12, 'zeros', 'Money', ' 1 trillion = 10 lakh crore in the Indian system.', 5, 15, true),
('pbq-011', 'What is the approximate GDP of India in trillions USD (2024)?', 3.9, 'trillion USD', 'Money', ' India is the 5th largest economy by GDP.', 1, 10, true),
('pbq-012', 'How much does a Boeing 747 cost (in million USD)?', 400, 'million USD', 'Money', ' A new 747-8 costs around $400M.', 100, 1000, true),
-- Human Body
('pbq-013', 'How many hairs does the average human head have?', 100000, 'hairs', 'Human Body', ' Blondes average 146,000, brunettes 110,000.', 50000, 200000, true),
('pbq-014', 'How many times does the average human heart beat per day?', 100000, 'beats', 'Human Body', ' That is about 2.5 billion beats in a lifetime.', 50000, 150000, true),
('pbq-015', 'How many miles of blood vessels are in the human body?', 60000, 'miles', 'Human Body', ' Enough to circle Earth 2.4 times!', 10000, 150000, true),
('pbq-016', 'How many taste buds does the average human tongue have?', 10000, 'taste buds', 'Human Body', ' They replace themselves every 2 weeks.', 2000, 30000, true),
('pbq-017', 'How many steps per day is considered healthy?', 10000, 'steps', 'Human Body', ' The 10,000 steps concept originated from a 1960s Japanese marketing campaign.', 5000, 20000, true),
-- Space
('pbq-018', 'How many moons does Jupiter have?', 95, 'moons', 'Space', ' The most of any planet in our solar system!', 50, 200, true),
('pbq-019', 'How many light-years away is the nearest star (Proxima Centauri)?', 4.2, 'light-years', 'Space', ' Light takes 4.2 years to reach us from it.', 1, 10, true),
('pbq-020', 'How many days does it take for Mars to orbit the Sun?', 687, 'days', 'Space', ' A Martian year is about 1.88 Earth years.', 300, 1000, true),
('pbq-021', 'How many planets are in our solar system?', 8, 'planets', 'Space', ' Pluto was reclassified as a dwarf planet in 2006.', 5, 12, true),
('pbq-022', 'How many stars are estimated to be in the Milky Way?', 100000000000, 'stars', 'Space', ' About 100 billion stars!', 1000000000, 1000000000000, true),
('pbq-023', 'How many days does it take for the Moon to orbit Earth?', 27, 'days', 'Space', ' This is the sidereal month.', 20, 35, true),
-- Food
('pbq-024', 'How many varieties of rice are grown worldwide?', 40000, 'varieties', 'Food', ' India grows over 6,000 of them!', 1000, 100000, true),
('pbq-025', 'How many calories are in a standard banana?', 105, 'calories', 'Food', ' A good source of potassium too!', 50, 200, true),
('pbq-026', 'How many spices are used in a typical Indian garam masala?', 7, 'spices', 'Food', ' The exact count varies by family recipe!', 3, 15, true),
('pbq-027', 'How many cups of coffee are consumed worldwide each day (in billions)?', 2.25, 'billion cups', 'Food', ' That is about 400 billion cups a year!', 0.5, 5, true),
('pbq-028', 'How many years does it take to grow a pineapple?', 3, 'years', 'Food', ' Each plant produces only one pineapple at a time.', 1, 7, true),
('pbq-029', 'How many almonds does it take to make 1 litre of almond milk?', 150, 'almonds', 'Food', ' That is about 500g of almonds per litre.', 50, 500, true),
-- History
('pbq-030', 'In what year did the Berlin Wall fall?', 1989, 'year', 'History', ' It stood for 28 years (1961-1989).', 1900, 2000, true),
('pbq-031', 'How many years did the Roman Empire last (approximate)?', 1000, 'years', 'History', ' From 27 BC to 476 AD (Western Empire).', 500, 2000, true),
('pbq-032', 'How many years ago did dinosaurs go extinct (in millions)?', 66, 'million years', 'History', ' The Cretaceous-Paleogene extinction event.', 50, 100, true),
('pbq-033', 'How many years ago was the first written language created (approximate)?', 5000, 'years ago', 'History', ' Sumerian cuneiform is the oldest known.', 3000, 7000, true),
('pbq-034', 'How many people lived in the ancient city of Rome at its peak?', 1000000, 'people', 'History', ' The largest city in the world at that time!', 100000, 5000000, true),
('pbq-035', 'How many years did the Hundred Years War actually last?', 116, 'years', 'History', ' It lasted from 1337 to 1453.', 50, 200, true),
-- India-specific
('pbq-036', 'How many official languages does India have?', 22, 'languages', 'India', ' Scheduled languages in the Constitution.', 10, 30, true),
('pbq-037', 'How many UNESCO World Heritage Sites are in India?', 42, 'sites', 'India', ' As of 2024, India has 42 World Heritage Sites.', 20, 60, true),
('pbq-038', 'How many people visit the Taj Mahal each year (in millions)?', 7, 'million visitors', 'India', ' It receives 7-8 million visitors annually.', 1, 20, true),
('pbq-039', 'How many kilometres of railway tracks does India have?', 68000, 'km', 'India', ' Indian Railways is the 4th largest network in the world.', 50000, 100000, true),
('pbq-040', 'How many years ago was the Indus Valley Civilization (approximate)?', 4500, 'years ago', 'India', ' It flourished around 2500 BCE.', 3000, 6000, true),
('pbq-041', 'How many districts does India have (as of 2024)?', 776, 'districts', 'India', ' The count changes as new districts are created.', 600, 900, true),
('pbq-042', 'How many films does Bollywood produce per year (approximate)?', 1000, 'films', 'India', ' India produces the most films in the world!', 500, 2000, true),
-- Technology
('pbq-043', 'How many lines of code was the first iPhone OS (approximate)?', 100000, 'lines', 'Technology', ' Modern iOS has tens of millions of lines.', 10000, 500000, true),
('pbq-044', 'How many transistors are in the Apple M3 chip (in billions)?', 25, 'billion', 'Technology', ' The M3 has 25 billion transistors!', 5, 100, true),
('pbq-045', 'How many bytes are in 1 gigabyte?', 1073741824, 'bytes', 'Technology', ' 1 GB = 1024^3 bytes (binary definition).', 100000000, 10000000000, true),
('pbq-046', 'How many internet users are there worldwide (in billions, 2024)?', 5.4, 'billion users', 'Technology', ' About 67% of the global population.', 3, 8, true),
('pbq-047', 'How many YouTube videos are watched per day (in billions)?', 5, 'billion videos', 'Technology', ' About 720,000 hours uploaded every day too!', 1, 15, true),
('pbq-048', 'How many apps are on the Google Play Store (in millions, 2024)?', 3.5, 'million apps', 'Technology', ' Google removed many low-quality apps recently.', 1, 10, true),
('pbq-049', 'How many searches does Google handle per day (in billions)?', 8.5, 'billion searches', 'Technology', ' That is about 99,000 searches per second!', 1, 20, true),
('pbq-050', 'How many years ago was the first email sent?', 53, 'years ago', 'Technology', ' Ray Tomlinson sent it in 1971.', 30, 70, true)
ON CONFLICT ("id") DO NOTHING;
