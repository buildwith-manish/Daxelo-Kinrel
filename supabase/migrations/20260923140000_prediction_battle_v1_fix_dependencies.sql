-- 20260923140000_prediction_battle_v1_fix_dependencies.sql
--
-- Phase 3.6 — Fix the silent failures in fn_pb_v1_reveal_all_due.
--
-- When the original prediction_battle_v1_scheduled migration was
-- written, it assumed two dependencies that don't exist anywhere
-- in the codebase:
--
--   1. public.fn_award_coins(userId, familyId, amount, reason)
--      → never created. Every winner / streak-bonus / close-guess
--        coin award in fn_pb_v1_reveal_all_due was silently
--        swallowed by `EXCEPTION WHEN OTHERS THEN NULL`.
--   2. public.family_moments table
--      → never created. The Family Moments auto-post on reveal
--        was silently swallowed too.
--        Bonus: the existing family_moment_reactions table (created
--        in 20260917150000_family_arena_3zone_restructure.sql) was
--        orphaned — its `momentId` foreign key references a parent
--        table that doesn't exist.
--
-- This migration does TWO things:
--
-- A) Creates the family_moments table (minimal — only the columns
--    the predictions module + the orphaned reactions table need).
--    This unblocks:
--      - The predictions Family Moments auto-post on reveal
--      - The orphaned family_moment_reactions table (which now has
--        a real parent to point at)
--    The table is intentionally minimal — a richer schema (photos,
--    multiple winners, etc.) can be added later when there's a UI
--    that needs it.
--
-- B) Replaces the broken `PERFORM public.fn_award_coins(...)` calls
--    in fn_pb_v1_reveal_all_due with `RAISE NOTICE` log lines that
--    document what WOULD have been awarded. This makes the silent
--    failure visible in the Postgres logs — instead of swallowing
--    the error, we now log "would have awarded 10 coins to user X
--    for reason 'prediction_winner' (coin economy not yet built)".
--    When a real coin economy is added later, swap the RAISE NOTICE
--    for a PERFORM fn_award_coins(...) call.
--
-- Why not just build a coin economy here?
--   - The coin economy is a multi-day feature: wallet table,
--     transaction ledger, Flutter UI for balance, server-side
--     validators for negative-balance protection, etc.
--   - The user's request was to "do better in the app" — shipping
--     a half-built coin economy would be worse than honest no-ops.
--   - The prediction battle's engagement loop (streaks + leaderboard)
--     works without coins; coins were a nice-to-have bonus layer.
--   - Making the silent failure visible (via RAISE NOTICE) means
--     the Postgres logs will show exactly what's being skipped, so
--     when a real coin economy is built, we can verify the awards
--     are flowing by tailing the logs.

-- ═════════════════════════════════════════════════════════════════════
-- A. Create the family_moments table (minimal)
-- ═════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "family_moments" (
  "id"        TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"  TEXT NOT NULL,
  "userId"    TEXT NOT NULL,
  "type"      TEXT NOT NULL,                  -- 'prediction_battle' | future types
  "title"     TEXT NOT NULL,
  "body"      TEXT NOT NULL DEFAULT '',
  "metadata"  JSONB NOT NULL DEFAULT '{}'::jsonb, -- round_id, question_id, etc.
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes: list-by-family-recent-first (the main query pattern)
CREATE INDEX IF NOT EXISTS idx_fm_family_created
  ON "family_moments" ("familyId", "createdAt" DESC);
-- Index: filter by type within a family (e.g. show only prediction moments)
CREATE INDEX IF NOT EXISTS idx_fm_family_type_created
  ON "family_moments" ("familyId", "type", "createdAt" DESC);

-- RLS
ALTER TABLE "family_moments" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS family_moments_select_family ON "family_moments";
CREATE POLICY family_moments_select_family ON "family_moments"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

-- INSERT: only service-role (NestJS / pg_cron / SECURITY DEFINER
-- functions) writes moments — users don't create them directly. We
-- do allow INSERT for authenticated so the existing security pattern
-- is preserved, but the body should always come from a SECURITY
-- DEFINER function (fn_pb_v1_reveal_all_due).
DROP POLICY IF EXISTS family_moments_insert_family ON "family_moments";
CREATE POLICY family_moments_insert_family ON "family_moments"
  FOR INSERT TO authenticated
  WITH CHECK (public.fn_user_is_family_member("familyId"));

-- Realtime: publish inserts so the family hub can live-update when
-- a new moment is auto-posted on reveal.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.family_moments;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
ALTER TABLE "family_moments" REPLICA IDENTITY FULL;

-- Add a foreign key from the orphaned family_moment_reactions
-- table to family_moments. The reactions table was created in
-- 20260917150000_family_arena_3zone_restructure.sql but never had
-- a parent table to point at. Now it does.
-- Use DO block + EXCEPTION because the FK may already exist (idempotent).
DO $$
BEGIN
  ALTER TABLE "family_moment_reactions"
    ADD CONSTRAINT "family_moment_reactions_momentId_fkey"
    FOREIGN KEY ("momentId") REFERENCES "family_moments"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
END $$;

-- ═════════════════════════════════════════════════════════════════════
-- B. Rewrite fn_pb_v1_reveal_all_due to log instead of silently fail
-- ═════════════════════════════════════════════════════════════════════
--
-- The only change vs. the original: the three
-- `PERFORM public.fn_award_coins(...)` blocks are replaced with
-- `RAISE NOTICE` log lines that document what would have been
-- awarded. The Family Moments INSERT is left as-is — it now works
-- because the table exists.

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

    -- Award coins (winner bonus + close-guess consolation)
    -- ─────────────────────────────────────────────────────────
    -- Phase 3.6 — the coin economy (fn_award_coins) does NOT exist
    -- in the codebase. The original migration silently swallowed
    -- the failure via `EXCEPTION WHEN OTHERS THEN NULL`. We now
    -- RAISE NOTICE so the Postgres logs show what would have been
    -- awarded, making the gap visible. When a real coin economy is
    -- built, swap the RAISE NOTICE for a PERFORM fn_award_coins(...)
    -- and remove this comment.
    FOR v_guess IN
      SELECT * FROM "pb_v1_guesses" WHERE round_id = v_round.id
    LOOP
      IF v_correct > 1000 THEN
        v_distance := ABS(v_guess.guess_value - v_correct) / v_correct * 100;
      ELSE
        v_distance := ABS(v_guess.guess_value - v_correct)::float;
      END IF;

      IF v_winners @> ARRAY[v_guess.user_id] THEN
        -- Winner coin bonus (coin economy not yet built — logged only)
        RAISE NOTICE 'COIN_AWARD_PENDING: user=% family=% amount=10 reason=prediction_winner round=%',
          v_guess.user_id, v_round.family_id, v_round.id;

        -- Update win streak (this part DOES work — pb_v1_win_streaks exists)
        INSERT INTO "pb_v1_win_streaks" (user_id, family_id, current_streak, best_streak, updated_at)
        VALUES (v_guess.user_id, v_round.family_id, 1, 1, now())
        ON CONFLICT (user_id, family_id) DO UPDATE SET
          current_streak = "pb_v1_win_streaks".current_streak + 1,
          best_streak = GREATEST("pb_v1_win_streaks".best_streak, "pb_v1_win_streaks".current_streak + 1),
          updated_at = now();

        -- Streak bonus at 3+ (coin economy not yet built — logged only)
        IF (SELECT current_streak FROM "pb_v1_win_streaks" WHERE user_id = v_guess.user_id AND family_id = v_round.family_id) >= 3 THEN
          RAISE NOTICE 'COIN_AWARD_PENDING: user=% family=% amount=5 reason=prediction_streak_bonus round=% streak=%',
            v_guess.user_id, v_round.family_id, v_round.id,
            (SELECT current_streak FROM "pb_v1_win_streaks" WHERE user_id = v_guess.user_id AND family_id = v_round.family_id);
        END IF;
      ELSIF v_distance <= v_min_distance * 2 AND v_min_distance > 0 THEN
        -- Close-guess consolation coin (coin economy not yet built — logged only)
        RAISE NOTICE 'COIN_AWARD_PENDING: user=% family=% amount=2 reason=prediction_close_guess round=% distance=%',
          v_guess.user_id, v_round.family_id, v_round.id, v_distance;
      END IF;

      -- Reset streak for non-winners
      IF NOT v_winners @> ARRAY[v_guess.user_id] THEN
        UPDATE "pb_v1_win_streaks" SET current_streak = 0, updated_at = now()
        WHERE user_id = v_guess.user_id AND family_id = v_round.family_id;
      END IF;
    END LOOP;

    -- Family Moments auto-post (now works — table created in this migration)
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
      -- Still wrapped in exception because the User table lookup
      -- for v_winner_name could fail in edge cases. Log + continue.
      RAISE NOTICE 'FAMILY_MOMENTS_INSERT_FAILED: round=% err=%', v_round.id, SQLERRM;
    END;

  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_reveal_all_due() TO authenticated;
