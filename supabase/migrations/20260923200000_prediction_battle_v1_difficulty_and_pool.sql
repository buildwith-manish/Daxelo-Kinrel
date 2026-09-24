-- 20260923200000_prediction_battle_v1_difficulty_and_pool.sql
--
-- Phase 3.12 + 3.13 — two related features in one migration:
--
-- A. Adaptive question difficulty (Tier 3 item 11)
--    Adds a `difficulty` column to pb_v1_questions (1=easy, 2=medium,
--    3=hard). Updates fn_pb_v1_get_next_question to pick questions
--    that match the user's recent win rate:
--      - win_rate < 33% → bias toward easy (difficulty=1)
--      - win_rate 33-66% → medium (difficulty=2)
--      - win_rate > 66% → hard (difficulty=3)
--    The existing category-rotation + 6-month-cooldown logic is
--    preserved — difficulty is a tiebreaker, not a primary filter.
--
-- B. Family coin pool with collective goals (Tier 3 item 12)
--    New table `family_coin_pools` per (familyId) tracking the
--    family's total coins (sum of all members' lifetimeEarned).
--    When the pool hits a goal threshold (default 500), the family
--    unlocks a small bonus — currently a flag in the pool row; the
--    Flutter UI can render a celebration card.
--    An RPC `fn_get_family_coin_pool(familyId)` returns the pool
--    stats + next goal + progress fraction.

-- ═════════════════════════════════════════════════════════════════════
-- A. Adaptive question difficulty
-- ═════════════════════════════════════════════════════════════════════

ALTER TABLE "pb_v1_questions"
  ADD COLUMN IF NOT EXISTS "difficulty" INTEGER NOT NULL DEFAULT 2;
-- 1 = easy, 2 = medium, 3 = hard. Default 2 (medium) so all existing
-- seed questions start at medium and the adaptive logic can move
-- users toward harder/easier ones over time.

CREATE INDEX IF NOT EXISTS idx_pb_v1_q_difficulty
  ON "pb_v1_questions" ("difficulty", "is_active");

-- ── Update fn_pb_v1_get_next_question to factor in difficulty ─────
--
-- The new logic:
--   1. Compute the user's win rate over their last 10 revealed
--      rounds (count of i_won=true / count of my_guess != null).
--   2. Pick a target difficulty based on the win rate.
--   3. Filter eligible questions by target difficulty (with a ±1
--      fallback if no exact-match questions are available).
--   4. Preserve the existing category-rotation + 6-month cooldown.

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

  -- 2. Compute today's reveal time: 9 PM IST = 3:30 PM UTC
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';
  v_reveal_at := v_today_start + interval '21 hours';

  IF now() >= v_reveal_at THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'past_reveal_time');
  END IF;

  -- 3. Compute the user's win rate over their last 10 revealed rounds.
  --    (Adaptive difficulty — Tier 3 item 11.)
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
        v_target_difficulty := 1;  -- easy
      ELSIF v_win_rate > 0.66 THEN
        v_target_difficulty := 3;  -- hard
      ELSE
        v_target_difficulty := 2;  -- medium
      END IF;
    END IF;
  END IF;

  -- 4. Category-weighted + difficulty-aware selection.
  --    Pick from least-represented category in the last 30 days,
  --    prefer questions matching the target difficulty, with a ±1
  --    fallback if no exact-match questions are available.
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

  -- Fallback: ignore 6-month cooldown, pick least-recently-shown
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

  -- 5. Create round + record served
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
-- B. Family coin pool with collective goals
-- ═════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "family_coin_pools" (
  "familyId"           TEXT PRIMARY KEY,
  "totalEarned"         INTEGER NOT NULL DEFAULT 0,    -- sum of all members' lifetimeEarned
  "lastGoalHitAt"       TIMESTAMPTZ,                   -- when the family last hit a goal threshold
  "currentGoal"         INTEGER NOT NULL DEFAULT 500,  -- next goal threshold
  "goalsHit"            INTEGER NOT NULL DEFAULT 0,    -- how many goals the family has hit total
  "updatedAt"           TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE "family_coin_pools" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS family_coin_pools_select_family ON "family_coin_pools";
CREATE POLICY family_coin_pools_select_family ON "family_coin_pools"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

-- ── RPC: fn_get_family_coin_pool ──────────────────────────────────
-- Returns the family's pool stats + progress toward the next goal.
-- The Flutter client renders a small "Family pool: 342/500 🪙"
-- progress card on the family hub.

CREATE OR REPLACE FUNCTION public.fn_get_family_coin_pool(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pool record;
  v_total_earned integer := 0;
BEGIN
  -- Sum all members' lifetimeEarned for the family. We do this live
  -- (vs. trusting the pool row's totalEarned cache) so the progress
  -- bar is always accurate.
  SELECT COALESCE(SUM("lifetimeEarned"), 0) INTO v_total_earned
  FROM "user_coin_balances"
  WHERE "familyId" = p_family_id;

  -- Upsert the pool row with the fresh total.
  INSERT INTO "family_coin_pools" ("familyId", "totalEarned", "currentGoal", "goalsHit", "updatedAt")
  VALUES (p_family_id, v_total_earned, 500, 0, now())
  ON CONFLICT ("familyId") DO UPDATE SET
    "totalEarned" = EXCLUDED."totalEarned",
    "updatedAt" = now();

  SELECT * INTO v_pool FROM "family_coin_pools" WHERE "familyId" = p_family_id;

  -- If the family just crossed the goal threshold this call, mark
  -- it. The Flutter client can check lastGoalHitAt to decide whether
  -- to show a celebration animation.
  IF v_total_earned >= v_pool."currentGoal" AND v_pool."lastGoalHitAt" IS NULL THEN
    UPDATE "family_coin_pools" SET
      "lastGoalHitAt" = now(),
      "goalsHit" = "goalsHit" + 1,
      "currentGoal" = "currentGoal" + 500  -- next goal is +500
    WHERE "familyId" = p_family_id;
    SELECT * INTO v_pool FROM "family_coin_pools" WHERE "familyId" = p_family_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'family_id', p_family_id,
    'total_earned', v_pool."totalEarned",
    'current_goal', v_pool."currentGoal",
    'goals_hit', v_pool."goalsHit",
    'last_goal_hit_at', v_pool."lastGoalHitAt",
    'progress_fraction', CASE
      WHEN v_pool."currentGoal" = 0 THEN 0
      ELSE LEAST(1.0, v_pool."totalEarned"::float / v_pool."currentGoal"::float)
    END
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_get_family_coin_pool(text) TO authenticated;
