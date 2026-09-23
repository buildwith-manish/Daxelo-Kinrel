-- 20260923160000_prediction_battle_v1_wire_coin_economy.sql
--
-- Phase 3.7.1 — Wire fn_award_coins into fn_pb_v1_reveal_all_due.
--
-- The previous migration (20260923150000_coin_economy.sql) built the
-- coin economy. This migration replaces the three `RAISE NOTICE
-- 'COIN_AWARD_PENDING: ...'` log lines in fn_pb_v1_reveal_all_due
-- with real `PERFORM public.fn_award_coins(...)` calls.
--
-- Idempotency: each award passes the round id as the idempotency key
-- combined with the reason. This means even if the pg_cron recovery
-- tick runs twice for the same round (rare but possible), users
-- don't get double-credited.
--
-- Idempotency key format: '<round_id>:<reason>'
--   - 'abc-123:prediction_winner'
--   - 'abc-123:prediction_streak_bonus'
--   - 'abc-123:prediction_close_guess'
--
-- This is unique per (round, reason) — exactly what we want.
-- The partial unique index uq_cl_idempotency enforces this at the
-- DB level: a second fn_award_coins call with the same key returns
-- 'already_awarded' without inserting a duplicate ledger row.
--
-- The function also passes the round_id + question_id + correct_answer
-- + distance in the metadata JSONB column so we have a full audit
-- trail of why each coin was awarded.

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
  v_idempotency_key text;
  v_metadata jsonb;
  v_current_streak integer;
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

    -- Award coins + update streaks
    FOR v_guess IN
      SELECT * FROM "pb_v1_guesses" WHERE round_id = v_round.id
    LOOP
      IF v_correct > 1000 THEN
        v_distance := ABS(v_guess.guess_value - v_correct) / v_correct * 100;
      ELSE
        v_distance := ABS(v_guess.guess_value - v_correct)::float;
      END IF;

      -- Build the metadata JSONB that goes into the ledger for audit
      v_metadata := jsonb_build_object(
        'round_id', v_round.id,
        'question_id', v_question.id,
        'guess_value', v_guess.guess_value,
        'correct_answer', v_correct,
        'distance', v_distance
      );

      IF v_winners @> ARRAY[v_guess.user_id] THEN
        -- ── Winner coin bonus (10 coins) ──
        v_idempotency_key := v_round.id || ':prediction_winner';
        PERFORM public.fn_award_coins(
          v_guess.user_id,
          v_round.family_id,
          10,
          'prediction_winner',
          v_idempotency_key,
          v_metadata
        );

        -- Update win streak
        INSERT INTO "pb_v1_win_streaks" (user_id, family_id, current_streak, best_streak, updated_at)
        VALUES (v_guess.user_id, v_round.family_id, 1, 1, now())
        ON CONFLICT (user_id, family_id) DO UPDATE SET
          current_streak = "pb_v1_win_streaks".current_streak + 1,
          best_streak = GREATEST("pb_v1_win_streaks".best_streak, "pb_v1_win_streaks".current_streak + 1),
          updated_at = now();

        -- ── Streak bonus at 3+ (5 coins) ──
        SELECT current_streak INTO v_current_streak
        FROM "pb_v1_win_streaks"
        WHERE user_id = v_guess.user_id AND family_id = v_round.family_id;

        IF v_current_streak >= 3 THEN
          v_idempotency_key := v_round.id || ':prediction_streak_bonus';
          v_metadata := v_metadata || jsonb_build_object('streak', v_current_streak);
          PERFORM public.fn_award_coins(
            v_guess.user_id,
            v_round.family_id,
            5,
            'prediction_streak_bonus',
            v_idempotency_key,
            v_metadata
          );
        END IF;
      ELSIF v_distance <= v_min_distance * 2 AND v_min_distance > 0 THEN
        -- ── Close-guess consolation (2 coins) ──
        v_idempotency_key := v_round.id || ':prediction_close_guess';
        PERFORM public.fn_award_coins(
          v_guess.user_id,
          v_round.family_id,
          2,
          'prediction_close_guess',
          v_idempotency_key,
          v_metadata
        );
      END IF;

      -- Reset streak for non-winners
      IF NOT v_winners @> ARRAY[v_guess.user_id] THEN
        UPDATE "pb_v1_win_streaks" SET current_streak = 0, updated_at = now()
        WHERE user_id = v_guess.user_id AND family_id = v_round.family_id;
      END IF;
    END LOOP;

    -- Family Moments auto-post (worked since Phase 3.6)
    BEGIN
      v_margin := v_min_distance;
      v_winner_name := COALESCE(
        (SELECT name FROM "User" WHERE id = v_winners[1]),
        'Someone'
      );
      INSERT INTO "family_moments" ("familyId", "userId", "type", "title", "body", "metadata", "createdAt")
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
        jsonb_build_object(
          'round_id', v_round.id,
          'question_id', v_question.id,
          'correct_answer', v_correct,
          'margin', v_margin,
          'winner_user_ids', to_jsonb(v_winners)
        ),
        now();
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'FAMILY_MOMENTS_INSERT_FAILED: round=% err=%', v_round.id, SQLERRM;
    END;

  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_reveal_all_due() TO authenticated;
