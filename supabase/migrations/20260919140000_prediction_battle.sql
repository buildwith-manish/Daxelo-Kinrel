-- 20260919140000_prediction_battle.sql
-- Prediction Battle — replaces Truth Streak in Family Space.
-- Two engines: Closest Wins (numeric) + Outcome Prediction (binary).
-- Lifecycle: OPEN → LOCKED → PENDING → RESOLVED → ARCHIVED.

CREATE TABLE IF NOT EXISTS "prediction_questions" (
  id TEXT PRIMARY KEY,
  question TEXT NOT NULL,
  "type" TEXT NOT NULL DEFAULT 'closest', -- closest | outcome
  category TEXT NOT NULL DEFAULT 'general',
  "correctAnswer" TEXT, -- numeric string for closest, 'yes'/'no' or option text for outcome
  "optionA" TEXT, -- for outcome type
  "optionB" TEXT, -- for outcome type
  "qualityScore" INTEGER NOT NULL DEFAULT 50,
  "isLegendary" BOOLEAN NOT NULL DEFAULT false,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pq_category ON "prediction_questions" ("category", "isActive");
ALTER TABLE "prediction_questions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prediction_questions_select_all" ON "prediction_questions" FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS "prediction_rounds" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "questionId" TEXT NOT NULL REFERENCES "prediction_questions"(id),
  status TEXT NOT NULL DEFAULT 'open', -- open|locked|pending|resolved|archived
  "lockAt" TIMESTAMPTZ NOT NULL,
  "revealAt" TIMESTAMPTZ NOT NULL,
  "resolvedAt" TIMESTAMPTZ,
  "actualAnswer" TEXT,
  "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "results" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "isLegendary" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pr_family ON "prediction_rounds" ("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_pr_status ON "prediction_rounds" ("status", "lockAt");
ALTER TABLE "prediction_rounds" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prediction_rounds_select_family" ON "prediction_rounds" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "prediction_rounds_insert_family" ON "prediction_rounds" FOR INSERT TO authenticated WITH CHECK (public.fn_user_is_family_member("familyId"));
CREATE POLICY "prediction_rounds_update_family" ON "prediction_rounds" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

CREATE TABLE IF NOT EXISTS "prediction_submissions" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "roundId" TEXT NOT NULL REFERENCES "prediction_rounds"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  prediction TEXT NOT NULL, -- numeric string or option text
  confidence TEXT NOT NULL DEFAULT 'low', -- low|medium|high
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("roundId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_ps_round ON "prediction_submissions" ("roundId");
ALTER TABLE "prediction_submissions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prediction_submissions_select_family" ON "prediction_submissions" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "prediction_submissions_insert_self" ON "prediction_submissions" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "prediction_submissions_update_self" ON "prediction_submissions" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

CREATE TABLE IF NOT EXISTS "prediction_history" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "questionId" TEXT NOT NULL,
  "roundId" TEXT NOT NULL,
  "shownAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "resolvedAt" TIMESTAMPTZ,
  UNIQUE ("familyId", "questionId")
);
ALTER TABLE "prediction_history" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prediction_history_select_family" ON "prediction_history" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));

CREATE TABLE IF NOT EXISTS "prediction_leaderboard" (
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  points INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  "correctPredictions" INTEGER NOT NULL DEFAULT 0,
  "totalPredictions" INTEGER NOT NULL DEFAULT 0,
  "currentStreak" INTEGER NOT NULL DEFAULT 0,
  "bestStreak" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("userId", "familyId")
);
ALTER TABLE "prediction_leaderboard" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prediction_leaderboard_select_family" ON "prediction_leaderboard" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER PUBLICATION supabase_realtime ADD TABLE "prediction_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "prediction_submissions";
ALTER TABLE "prediction_rounds" REPLICA IDENTITY FULL;
ALTER TABLE "prediction_submissions" REPLICA IDENTITY FULL;

-- RPC: get_or_create_active_prediction — picks an unseen question for the family
CREATE OR REPLACE FUNCTION public.fn_prediction_get_active(p_family_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing record;
  v_question record;
  v_round_id text;
  v_lock_interval interval := interval '12 hours';
  v_reveal_interval interval := interval '24 hours';
  v_now timestamptz := now();
BEGIN
  -- Check for an existing active/open/locked/pending round
  SELECT * INTO v_existing FROM "prediction_rounds"
  WHERE "familyId" = p_family_id AND status IN ('open','locked','pending')
  ORDER BY "createdAt" DESC LIMIT 1;

  IF FOUND THEN
    -- Return the existing round + question
    SELECT jsonb_build_object(
      'round', row_to_json(v_existing),
      'question', (SELECT row_to_json(q) FROM "prediction_questions" q WHERE q.id = v_existing."questionId"),
      'participationCount', (SELECT COUNT(*) FROM "prediction_submissions" WHERE "roundId" = v_existing.id)
    );
    RETURN jsonb_build_object(
      'round', row_to_json(v_existing),
      'question', (SELECT row_to_json(q) FROM "prediction_questions" q WHERE q.id = v_existing."questionId"),
      'participationCount', (SELECT COUNT(*) FROM "prediction_submissions" WHERE "roundId" = v_existing.id)
    );
  END IF;

  -- Pick the next unseen question (priority: unseen → not same category as last → highest quality)
  SELECT * INTO v_question FROM "prediction_questions"
  WHERE "isActive" = true
    AND id NOT IN (SELECT "questionId" FROM "prediction_history" WHERE "familyId" = p_family_id)
  ORDER BY
    CASE
      -- Avoid same category as the most recent resolved round
      WHEN "category" = (SELECT q."category" FROM "prediction_rounds" r
        JOIN "prediction_questions" q ON q.id = r."questionId"
        WHERE r."familyId" = p_family_id AND r.status = 'resolved'
        ORDER BY r."resolvedAt" DESC LIMIT 1)
      THEN 1 ELSE 0
    END,
    "qualityScore" DESC,
    random()
  LIMIT 1;

  -- If pool exhausted, reuse oldest (but not within 365 days)
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

  -- Create the round
  v_round_id := gen_random_uuid()::text;
  INSERT INTO "prediction_rounds" (id, "familyId", "questionId", status, "lockAt", "revealAt", "isLegendary")
  VALUES (v_round_id, p_family_id, v_question.id, 'open',
    v_now + v_lock_interval, v_now + v_reveal_interval, v_question."isLegendary");

  -- Record in history
  INSERT INTO "prediction_history" ("familyId", "questionId", "roundId", "shownAt")
  VALUES (p_family_id, v_question.id, v_round_id, v_now)
  ON CONFLICT ("familyId", "questionId") DO NOTHING;

  RETURN jsonb_build_object(
    'ok', true,
    'round', jsonb_build_object(
      'id', v_round_id, 'familyId', p_family_id, 'questionId', v_question.id,
      'status', 'open', 'lockAt', v_now + v_lock_interval,
      'revealAt', v_now + v_reveal_interval, 'isLegendary', v_question."isLegendary",
      'createdAt', v_now
    ),
    'question', row_to_json(v_question),
    'participationCount', 0
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_prediction_get_active(text) TO authenticated;

-- RPC: submit_prediction
CREATE OR REPLACE FUNCTION public.fn_prediction_submit(
  p_round_id text, p_user_id text, p_family_id text, p_prediction text, p_confidence text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_round record;
BEGIN
  SELECT * INTO v_round FROM "prediction_rounds" WHERE id = p_round_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_round.status <> 'open' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_open'); END IF;
  IF now() > v_round."lockAt" THEN RETURN jsonb_build_object('ok', false, 'reason', 'locked'); END IF;

  INSERT INTO "prediction_submissions" ("roundId", "userId", "familyId", prediction, confidence)
  VALUES (p_round_id, p_user_id, p_family_id, p_prediction, p_confidence)
  ON CONFLICT ("roundId", "userId") DO UPDATE SET prediction = EXCLUDED.prediction, confidence = EXCLUDED.confidence, "submittedAt" = now();

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_prediction_submit(text, text, text, text, text) TO authenticated;

-- RPC: resolve_prediction — called by tick or manually
CREATE OR REPLACE FUNCTION public.fn_prediction_resolve(p_round_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_round record; v_question record; v_actual text; v_type text;
  v_subs jsonb; v_results jsonb := '[]'::jsonb; v_winners text[] := ARRAY[]::text[];
  v_confidence_mult float; v_points int; v_winner_ids jsonb := '[]'::jsonb;
  v_sub record; v_distance float; v_min_distance float := 999999999.0;
  v_rank int; v_lb record;
BEGIN
  SELECT * INTO v_round FROM "prediction_rounds" WHERE id = p_round_id;
  IF NOT FOUND OR v_round.status = 'resolved' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found_or_resolved'); END IF;

  SELECT * INTO v_question FROM "prediction_questions" WHERE id = v_round."questionId";
  v_actual := COALESCE(v_round."actualAnswer", v_question."correctAnswer");
  IF v_actual IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_answer'); END IF;

  v_type := v_question."type";

  -- Build results per submission
  FOR v_sub IN SELECT * FROM "prediction_submissions" WHERE "roundId" = p_round_id ORDER BY "submittedAt" LOOP
    v_confidence_mult := CASE v_sub.confidence WHEN 'high' THEN 1.5 WHEN 'medium' THEN 1.2 ELSE 1.0 END;

    IF v_type = 'closest' THEN
      v_distance := ABS(v_sub.prediction::float - v_actual::float);
      v_results := v_results || jsonb_build_object(
        'userId', v_sub."userId", 'prediction', v_sub.prediction,
        'confidence', v_sub.confidence, 'distance', v_distance,
        'correct', v_distance = 0
      );
    ELSE
      v_results := v_results || jsonb_build_object(
        'userId', v_sub."userId", 'prediction', v_sub.prediction,
        'confidence', v_sub.confidence, 'correct', v_sub.prediction = v_actual
      );
    END IF;
  END LOOP;

  -- Determine winners
  IF v_type = 'closest' THEN
    -- Sort by distance, assign ranks + points
    v_results := (SELECT jsonb_agg(elem ORDER BY (elem->>'distance')::float) FROM jsonb_array_elements(v_results) elem);
    v_rank := 0; v_min_distance := -1;
    FOR v_i IN 0..jsonb_array_length(v_results) - 1 LOOP
      DECLARE v_elem jsonb; v_dist float; v_pts int;
      BEGIN
        v_elem := v_results->v_i;
        v_dist := (v_elem->>'distance')::float;
        IF v_dist <> v_min_distance THEN v_rank := v_i + 1; v_min_distance := v_dist; END IF;
        v_pts := CASE v_rank WHEN 1 THEN 10 WHEN 2 THEN 6 WHEN 3 THEN 3 ELSE 0 END;
        v_confidence_mult := CASE v_elem->>'confidence' WHEN 'high' THEN 1.5 WHEN 'medium' THEN 1.2 ELSE 1.0 END;
        -- Wrong high-confidence gets reduced: if distance > 0 and confidence = high, mult = 0.7
        IF v_dist > 0 AND v_elem->>'confidence' = 'high' THEN v_confidence_mult := 0.7; END IF;
        v_pts := ROUND(v_pts * v_confidence_mult)::int;
        v_results := jsonb_set(v_results, ARRAY[v_i::text, 'points'], v_pts::text::jsonb);
        v_results := jsonb_set(v_results, ARRAY[v_i::text, 'rank'], v_rank::text::jsonb);
        IF v_rank = 1 THEN v_winners := array_append(v_winners, v_elem->>'userId'); END IF;
      END;
    END LOOP;
  ELSE
    -- Outcome: correct = 10 pts, incorrect = 0 pts
    FOR v_i IN 0..jsonb_array_length(v_results) - 1 LOOP
      DECLARE v_elem jsonb; v_pts int; v_correct boolean;
      BEGIN
        v_elem := v_results->v_i;
        v_correct := (v_elem->>'correct')::boolean;
        v_pts := CASE WHEN v_correct THEN 10 ELSE 0 END;
        v_confidence_mult := CASE v_elem->>'confidence' WHEN 'high' THEN 1.5 WHEN 'medium' THEN 1.2 ELSE 1.0 END;
        IF NOT v_correct AND v_elem->>'confidence' = 'high' THEN v_confidence_mult := 0.3; END IF;
        v_pts := ROUND(v_pts * v_confidence_mult)::int;
        v_results := jsonb_set(v_results, ARRAY[v_i::text, 'points'], v_pts::text::jsonb);
        IF v_correct THEN v_winners := array_append(v_winners, v_elem->>'userId'); END IF;
      END;
    END LOOP;
  END IF;

  v_winner_ids := to_jsonb(v_winners);

  -- Update round
  UPDATE "prediction_rounds" SET
    status = 'resolved', "resolvedAt" = now(), "actualAnswer" = v_actual,
    "winnerUserIds" = v_winner_ids, "results" = v_results
  WHERE id = p_round_id;

  -- Update history
  UPDATE "prediction_history" SET "resolvedAt" = now()
  WHERE "roundId" = p_round_id;

  -- Update leaderboard
  FOR v_i IN 0..jsonb_array_length(v_results) - 1 LOOP
    DECLARE v_elem jsonb; v_uid text; v_pts int; v_correct boolean; v_won boolean;
    BEGIN
      v_elem := v_results->v_i;
      v_uid := v_elem->>'userId';
      v_pts := (v_elem->>'points')::int;
      v_correct := (v_elem->>'correct')::boolean;
      v_won := v_winner_ids ? v_uid;

      INSERT INTO "prediction_leaderboard" ("userId", "familyId", points, wins, "correctPredictions", "totalPredictions", "currentStreak", "bestStreak", "updatedAt")
      VALUES (v_uid, v_round."familyId", v_pts,
        CASE WHEN v_won THEN 1 ELSE 0 END,
        CASE WHEN v_correct THEN 1 ELSE 0 END,
        1,
        CASE WHEN v_correct THEN 1 ELSE 0 END,
        CASE WHEN v_correct THEN 1 ELSE 0 END,
        now())
      ON CONFLICT ("userId", "familyId") DO UPDATE SET
        points = "prediction_leaderboard".points + v_pts,
        wins = "prediction_leaderboard".wins + CASE WHEN v_won THEN 1 ELSE 0 END,
        "correctPredictions" = "prediction_leaderboard"."correctPredictions" + CASE WHEN v_correct THEN 1 ELSE 0 END,
        "totalPredictions" = "prediction_leaderboard"."totalPredictions" + 1,
        "currentStreak" = CASE WHEN v_correct THEN "prediction_leaderboard"."currentStreak" + 1 ELSE 0 END,
        "bestStreak" = GREATEST("prediction_leaderboard"."bestStreak", CASE WHEN v_correct THEN "prediction_leaderboard"."currentStreak" + 1 ELSE "prediction_leaderboard"."currentStreak" END),
        "updatedAt" = now();
    END;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'results', v_results, 'winners', v_winner_ids);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_prediction_resolve(text) TO authenticated;

-- RPC: tick — advance round statuses + auto-resolve
CREATE OR REPLACE FUNCTION public.fn_prediction_tick(p_family_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_round record;
BEGIN
  -- Lock open rounds past lockAt
  UPDATE "prediction_rounds" SET status = 'locked'
  WHERE "familyId" = p_family_id AND status = 'open' AND "lockAt" < now();

  -- Move locked to pending past revealAt
  UPDATE "prediction_rounds" SET status = 'pending'
  WHERE "familyId" = p_family_id AND status = 'locked' AND "revealAt" < now();

  -- Resolve pending rounds past revealAt (if answer exists)
  FOR v_round IN SELECT * FROM "prediction_rounds"
    WHERE "familyId" = p_family_id AND status = 'pending' AND "revealAt" < now()
  LOOP
    -- Only resolve if the question has a correctAnswer OR the round has actualAnswer set
    IF EXISTS (SELECT 1 FROM "prediction_questions" q WHERE q.id = v_round."questionId" AND q."correctAnswer" IS NOT NULL)
       OR v_round."actualAnswer" IS NOT NULL THEN
      PERFORM public.fn_prediction_resolve(v_round.id);
    END IF;
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_prediction_tick(text) TO authenticated;

-- Seed initial questions (50 sample questions across categories)
INSERT INTO "prediction_questions" (id, question, "type", category, "correctAnswer", "qualityScore", "isActive", "optionA", "optionB") VALUES
  ('pq-001', 'How many floors are in Burj Khalifa?', 'closest', 'geography', '163', 90, true, NULL, NULL),
  ('pq-002', 'How many countries drive on the left side of the road?', 'closest', 'geography', '46', 85, true, NULL, NULL),
  ('pq-003', 'How many bones are in the adult human body?', 'closest', 'science', '206', 90, true, NULL, NULL),
  ('pq-004', 'How many planets are in our solar system?', 'closest', 'space', '8', 95, true, NULL, NULL),
  ('pq-005', 'How many minutes long is a full cricket ODI innings (one side)?', 'closest', 'sports', '300', 80, true, NULL, NULL),
  ('pq-006', 'How many official languages does India have?', 'closest', 'culture', '22', 85, true, NULL, NULL),
  ('pq-007', 'How many elements are in the periodic table?', 'closest', 'science', '118', 90, true, NULL, NULL),
  ('pq-008', 'How many time zones does Russia span?', 'closest', 'geography', '11', 80, true, NULL, NULL),
  ('pq-009', 'How many keys are on a standard piano?', 'closest', 'entertainment', '88', 85, true, NULL, NULL),
  ('pq-010', 'How many stripes are on the US flag?', 'closest', 'history', '13', 90, true, NULL, NULL),
  ('pq-011', 'How many rings does Saturn have (main groups)?', 'closest', 'space', '7', 75, true, NULL, NULL),
  ('pq-012', 'How many days does it take for the Moon to orbit Earth?', 'closest', 'space', '27', 85, true, NULL, NULL),
  ('pq-013', 'How many species of big cats exist?', 'closest', 'nature', '7', 75, true, NULL, NULL),
  ('pq-014', 'How many hearts does an octopus have?', 'closest', 'nature', '3', 90, true, NULL, NULL),
  ('pq-015', 'How many strings does a standard guitar have?', 'closest', 'entertainment', '6', 95, true, NULL, NULL),
  ('pq-016', 'How many players are on a cricket field during a match (including umpires)?', 'closest', 'sports', '15', 75, true, NULL, NULL),
  ('pq-017', 'How many continents are there?', 'closest', 'geography', '7', 95, true, NULL, NULL),
  ('pq-018', 'How many oceans are there on Earth?', 'closest', 'geography', '5', 90, true, NULL, NULL),
  ('pq-019', 'How many colors are in a rainbow?', 'closest', 'science', '7', 95, true, NULL, NULL),
  ('pq-020', 'How many teeth does an adult human have?', 'closest', 'science', '32', 90, true, NULL, NULL),
  ('pq-021', 'Will India win the next Cricket World Cup?', 'outcome', 'sports', NULL, 70, true, 'Yes', 'No'),
  ('pq-022', 'Will it rain in Mumbai tomorrow?', 'outcome', 'nature', NULL, 60, true, 'Yes', 'No'),
  ('pq-023', 'Will the next iPhone have a foldable screen?', 'outcome', 'technology', NULL, 65, true, 'Yes', 'No'),
  ('pq-024', 'Will humans land on Mars by 2030?', 'outcome', 'space', NULL, 75, true, 'Yes', 'No'),
  ('pq-025', 'Will electric cars outsell petrol cars by 2035?', 'outcome', 'technology', NULL, 70, true, 'Yes', 'No')
ON CONFLICT ("id") DO NOTHING;

-- Seed prediction badges
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'forecast-apprentice','Forecast Apprentice','भविष्यवाणी शिष्य','3 correct predictions','🔮','games','bronze',3,false,now()),
  (gen_random_uuid()::text,'oracle','Oracle','भविष्यद्रष्टा','10 correct predictions','🔮','games','silver',10,false,now()),
  (gen_random_uuid()::text,'future-seer','Future Seer','भविष्य द्रष्टा','25 correct predictions','🔮','games','gold',25,false,now()),
  (gen_random_uuid()::text,'prediction-master','Prediction Master','भविष्यवाणी मास्टर','50 correct predictions','🔮','games','platinum',50,false,now())
ON CONFLICT ("slug") DO NOTHING;
