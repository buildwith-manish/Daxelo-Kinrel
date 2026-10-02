-- 20261001180000_fix_scheduled_game_nights_race_condition.sql
--
-- PHASE 2 Item 19: Add FOR UPDATE SKIP LOCKED to fn_process_scheduled_game_nights
--
-- The function processes scheduled game nights in two FOR loops (reminders +
-- start). Without row locking, concurrent cron executions (or overlapping
-- invocations) can process the same scheduled game night row twice,
-- creating duplicate game rows + duplicate notifications.
--
-- FAILURE MODE (observed/theoretical):
-- If two cron runs overlap (15-min schedule + slow execution), both SELECT
-- the same 'scheduled'/'reminded' rows. Both loops create a game row for
-- the same scheduled night → duplicate games + duplicate invite pushes.
--
-- FIX: Add FOR UPDATE SKIP LOCKED to both FOR loops. This makes concurrent
-- runs skip rows the other run has already locked, rather than erroring
-- or duplicating. The function is already idempotent (status flip prevents
-- re-processing within the same run), so SKIP LOCKED is the correct
-- concurrency strategy here.
--
-- VERIFICATION:
-- Simulate concurrent execution: two simultaneous calls to the function.
-- Before the fix: both create duplicate game rows. After the fix: only one
-- creates the game row; the other skips the locked row.

CREATE OR REPLACE FUNCTION public.fn_process_scheduled_game_nights()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_now timestamptz := now();
  v_reminder_window timestamptz := now() + interval '15 minutes';
  v_sn RECORD;
  v_game_table text;
  v_game_id text;
  v_reminders_count int := 0;
  v_started_count int := 0;
BEGIN
  -- ── 1. REMINDERS ──────────────────────────────────────────────────
  -- Mark scheduled game nights within the 15-minute reminder window
  -- as 'reminded'. FOR UPDATE SKIP LOCKED prevents concurrent runs
  -- from processing the same row.
  FOR v_sn IN
    SELECT * FROM "scheduled_game_nights"
    WHERE status = 'scheduled'
      AND "scheduledFor" <= v_reminder_window
      AND "scheduledFor" > v_now
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE "scheduled_game_nights"
    SET status = 'reminded', "reminderSentAt" = v_now
    WHERE id = v_sn.id;
    v_reminders_count := v_reminders_count + 1;
  END LOOP;

  -- ── 2. START ─────────────────────────────────────────────────────
  -- For scheduled game nights whose time has arrived, create the real
  -- game row and insert game_invites. FOR UPDATE SKIP LOCKED prevents
  -- concurrent runs from creating duplicate game rows.
  FOR v_sn IN
    SELECT * FROM "scheduled_game_nights"
    WHERE status IN ('scheduled', 'reminded')
      AND "scheduledFor" <= v_now
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Determine the game table name.
    v_game_table := CASE v_sn."gameType"
      WHEN 'bingo' THEN 'bingo_games'
      WHEN 'ludo' THEN 'ludo_games'
      WHEN 'checkers' THEN 'checkers_games'
      WHEN 'carrom' THEN 'carrom_games'
      WHEN 'chess' THEN 'chess_games'
      WHEN 'sos' THEN 'sos_games'
      WHEN 'antakshari' THEN 'antakshari_games'
      WHEN 'freeze-dash' THEN 'redlight_rounds'
      WHEN 'nameplace' THEN 'nameplace_games'
      WHEN 'tictactoe' THEN 'tictactoe_games'
      WHEN 'truthordare' THEN 'truthordare_games'
      WHEN 'twotruths' THEN 'twotruths_games'
      WHEN 'dotsboxes' THEN 'dotsboxes_games'
      WHEN 'chitmatch' THEN 'chitmatch_games'
      ELSE 'bingo_games'
    END;

    -- Generate a game ID.
    v_game_id := gen_random_uuid()::text;

    -- Insert the game row via dynamic SQL.
    BEGIN
      EXECUTE format(
        'INSERT INTO %I (id, "familyId", "createdBy", status, "scheduledFor", "createdAt") VALUES ($1, $2, $3, $4, $5, now())',
        v_game_table
      ) USING v_game_id, v_sn."familyId", v_sn."createdBy", 'waiting', v_sn."scheduledFor";

      -- Insert game invites for each family member.
      INSERT INTO "game_invites" ("gameId", "gameTable", "familyId", "userId", status, "createdAt")
      SELECT v_game_id, v_game_table, v_sn."familyId", fm."userId", 'pending', now()
      FROM "FamilyMember" fm
      WHERE fm."familyId" = v_sn."familyId";

      -- Mark the scheduled night as started.
      UPDATE "scheduled_game_nights"
      SET status = 'started', "gameId" = v_game_id, "startedAt" = v_now
      WHERE id = v_sn.id;

      v_started_count := v_started_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Non-fatal: log + continue to the next scheduled night.
      RAISE NOTICE 'Failed to start game night %: %', v_sn.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'remindersSent', v_reminders_count,
    'gamesStarted', v_started_count,
    'processedAt', v_now
  );
END;
$$;
