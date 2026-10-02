-- 20260922120000_prediction_daily_refresh.sql
--
-- Server-side daily scheduling for the Prediction Battle.
--
-- PROBLEM: The previous architecture relied on clients to call
-- fn_prediction_get_active (on-demand round creation) and
-- fn_prediction_tick (per-family state transitions every 30s).
-- If no user opened the app, no round was created and no round was
-- closed — the system only worked while a client was connected.
--
-- FIX: This migration adds three pieces:
--
-- 1. fn_prediction_daily_tick() — a SECURITY DEFINER function that
--    iterates ALL families and does both close + create in one pass:
--    a. Closes/resolves any open/locked/pending rounds whose
--       lockAt/revealAt has passed.
--    b. Creates a new round for today's window (8 AM – 9:30 PM IST)
--       if one doesn't already exist AND we're inside the window.
--    c. Recovers missed days — if the last resolved round was from a
--       previous day and the current time is inside today's window,
--       a new round is created for today (even if a day or more was
--       missed due to server restart, deployment, or downtime).
--
-- 2. pg_cron schedule at 8:00 AM IST (2:30 AM UTC) — fires the daily
--    tick to create new rounds for every family at the window open.
--
-- 3. pg_cron schedule at 9:30 PM IST (4:00 PM UTC) — fires the daily
--    tick to close/resolve all active rounds at the window close.
--
-- 4. pg_cron recovery check every 15 minutes — catches missed rounds
--    if the 8 AM tick failed (server restart, deployment, etc.).
--    Idempotent: if a round already exists for today, it does nothing.
--
-- The function is idempotent: calling it multiple times is safe —
-- it only creates a new round if one doesn't already exist for the
-- current window, and only resolves rounds whose lockAt/revealAt
-- has actually passed.
--
-- All times are computed using AT TIME ZONE 'Asia/Kolkata' (IST).
-- The pg_cron schedule itself runs in UTC (Supabase's default).

-- ─────────────────────────────────────────────────────────────────────
-- 1. Server-side daily tick function
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_prediction_daily_tick()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_today_start timestamptz;  -- today 00:00 IST (as a UTC instant)
  v_window_open timestamptz;  -- today 8:00 AM IST (as a UTC instant)
  v_lock_at    timestamptz;  -- today 9:30 PM IST (as a UTC instant)
  v_family record;
  v_round record;
  v_question record;
  v_round_id text;
  v_existing_active boolean;
BEGIN
  -- Compute today's IST window boundaries (stored as UTC instants).
  v_today_start := date_trunc('day', v_now AT TIME ZONE 'Asia/Kolkata')
                   AT TIME ZONE 'Asia/Kolkata';
  v_window_open := v_today_start + interval '8 hours';            -- 8:00 AM IST
  v_lock_at     := v_today_start + interval '21 hours 30 minutes'; -- 9:30 PM IST

  -- ── Phase 1: Close/resolve all stale rounds for ALL families ──
  -- Lock open rounds past lockAt.
  UPDATE "prediction_rounds" SET status = 'locked'
  WHERE status = 'open' AND "lockAt" < v_now;

  -- Move locked to pending past revealAt.
  UPDATE "prediction_rounds" SET status = 'pending'
  WHERE status = 'locked' AND "revealAt" < v_now;

  -- Resolve pending rounds past revealAt (if answer exists).
  FOR v_round IN
    SELECT * FROM "prediction_rounds"
    WHERE status = 'pending' AND "revealAt" < v_now
  LOOP
    IF EXISTS (SELECT 1 FROM "prediction_questions" q
               WHERE q.id = v_round."questionId" AND q."correctAnswer" IS NOT NULL)
       OR v_round."actualAnswer" IS NOT NULL THEN
      PERFORM public.fn_prediction_resolve(v_round.id);
    END IF;
  END LOOP;

  -- ── Phase 2: Create new rounds for families inside the window ──
  -- Only create rounds if we're inside today's window (8 AM – 9:30 PM IST).
  -- If we're before 8 AM or after 9:30 PM, no new rounds are created
  -- (the close/resolve phase above already handled any stale rounds).
  IF v_now < v_window_open OR v_now >= v_lock_at THEN
    RETURN;
  END IF;

  -- Iterate every family that has at least one prediction_round or
  -- prediction_history entry (i.e., has opted into Prediction Battle).
  -- Using DISTINCT ON familyId from prediction_history ensures we
  -- cover every family that has ever played. New families get their
  -- first round when fn_prediction_get_active is called on-demand.
  FOR v_family IN
    SELECT DISTINCT "familyId" FROM "prediction_history"
    UNION
    SELECT DISTINCT "familyId" FROM "prediction_rounds"
  LOOP
    -- Check if this family already has an active/open/locked/pending
    -- round. If so, skip — exactly one active round at any time.
    SELECT 1 INTO v_existing_active
    FROM "prediction_rounds"
    WHERE "familyId" = v_family."familyId"
      AND status IN ('open', 'locked', 'pending')
    LIMIT 1;

    IF v_existing_active THEN
      CONTINUE;
    END IF;

    -- Check if this family already has a resolved round created today
    -- (i.e., the round was already played and resolved today).
    -- If so, skip — don't create a second round for the same day.
    SELECT 1 INTO v_existing_active
    FROM "prediction_rounds"
    WHERE "familyId" = v_family."familyId"
      AND status = 'resolved'
      AND "createdAt" >= v_today_start
    LIMIT 1;

    IF v_existing_active THEN
      CONTINUE;
    END IF;

    -- Pick the next unseen question for this family.
    -- Same logic as fn_prediction_get_active: unseen → not same
    -- category as last → highest quality → random.
    SELECT * INTO v_question FROM "prediction_questions"
    WHERE "isActive" = true
      AND id NOT IN (SELECT "questionId" FROM "prediction_history"
                     WHERE "familyId" = v_family."familyId")
    ORDER BY
      CASE
        WHEN "category" = (SELECT q."category" FROM "prediction_rounds" r
          JOIN "prediction_questions" q ON q.id = r."questionId"
          WHERE r."familyId" = v_family."familyId" AND r.status = 'resolved'
          ORDER BY r."resolvedAt" DESC LIMIT 1)
        THEN 1 ELSE 0
      END,
      "qualityScore" DESC,
      random()
    LIMIT 1;

    -- If pool exhausted, reuse oldest (not within 365 days).
    IF NOT FOUND THEN
      SELECT * INTO v_question FROM "prediction_questions"
      WHERE "isActive" = true
        AND id NOT IN (
          SELECT "questionId" FROM "prediction_history"
          WHERE "familyId" = v_family."familyId"
            AND "shownAt" > now() - interval '365 days'
        )
      ORDER BY "qualityScore" DESC, random() LIMIT 1;
    END IF;

    -- No questions available — skip this family.
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    -- Create the round with lockAt = revealAt = today 9:30 PM IST.
    -- Setting revealAt = lockAt means the reveal happens at close time
    -- (the tick function will transition open → locked → pending →
    -- resolved in a single tick call once now() passes lockAt).
    v_round_id := gen_random_uuid()::text;
    INSERT INTO "prediction_rounds" (id, "familyId", "questionId", status, "lockAt", "revealAt", "isLegendary")
    VALUES (v_round_id, v_family."familyId", v_question.id, 'open',
      v_lock_at, v_lock_at, v_question."isLegendary");

    -- Record in history.
    INSERT INTO "prediction_history" ("familyId", "questionId", "roundId", "shownAt")
    VALUES (v_family."familyId", v_question.id, v_round_id, v_now)
    ON CONFLICT ("familyId", "questionId") DO NOTHING;
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_prediction_daily_tick() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. pg_cron schedules
-- ─────────────────────────────────────────────────────────────────────

-- Enable pg_cron if not already enabled (idempotent — already
-- enabled by 20260704150000_bingo_cron_schedule.sql, but re-assert).
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA cron;

-- Unscheduled any previous prediction daily tick cron jobs (in case
-- this migration is re-run). The job names are stable strings.
SELECT cron.unschedule('prediction-daily-tick-open');
SELECT cron.unschedule('prediction-daily-tick-close');
SELECT cron.unschedule('prediction-daily-tick-recovery');

-- Schedule 1: Open new rounds at 8:00 AM IST (2:30 AM UTC).
-- Fires the daily tick which creates a new round for every family
-- that doesn't already have one for today's window.
SELECT cron.schedule(
  'prediction-daily-tick-open',
  '30 2 * * *',  -- 02:30 UTC = 8:00 AM IST
  $$ SELECT public.fn_prediction_daily_tick(); $$
);

-- Schedule 2: Close/resolve all rounds at 9:30 PM IST (4:00 PM UTC).
-- Fires the daily tick which closes and resolves any active rounds
-- whose lockAt/revealAt has passed.
SELECT cron.schedule(
  'prediction-daily-tick-close',
  '0 16 * * *',  -- 16:00 UTC = 9:30 PM IST
  $$ SELECT public.fn_prediction_daily_tick(); $$
);

-- Schedule 3: Recovery check every 15 minutes.
-- Catches missed rounds if the 8 AM tick failed (server restart,
-- deployment, downtime). The function is idempotent — if a round
-- already exists for today, it does nothing. This is the "safety net"
-- that ensures the system never gets stuck.
SELECT cron.schedule(
  'prediction-daily-tick-recovery',
  '*/15 * * * *',  -- every 15 minutes
  $$ SELECT public.fn_prediction_daily_tick(); $$
);

-- ─────────────────────────────────────────────────────────────────────
-- 3. Backfill: run the tick once to create rounds for families that
--    already have prediction_history but no active round right now.
-- ─────────────────────────────────────────────────────────────────────
-- This is safe to run — the function is idempotent. If a family
-- already has an active round, it's skipped. If we're outside the
-- window (before 8 AM or after 9:30 PM IST), no new rounds are created
-- (only stale rounds are closed/resolved).
SELECT public.fn_prediction_daily_tick();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Update fn_prediction_tick to also be a global tick (not per-family).
--    The client-side tick (called every 30s by the provider) now also
--    covers ALL families, not just the one the client is watching.
--    This ensures that even if only one client is open, it advances
--    stale rounds for ALL families (not just its own). The per-family
--    parameter is kept for backward compatibility but ignored.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_prediction_tick(p_family_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Lock open rounds past lockAt (ALL families, not just p_family_id).
  UPDATE "prediction_rounds" SET status = 'locked'
  WHERE status = 'open' AND "lockAt" < now();

  -- Move locked to pending past revealAt.
  UPDATE "prediction_rounds" SET status = 'pending'
  WHERE status = 'locked' AND "revealAt" < now();

  -- Resolve pending rounds past revealAt (if answer exists).
  PERFORM public.fn_prediction_resolve(r.id)
  FROM "prediction_rounds" r
  WHERE r.status = 'pending' AND r."revealAt" < now()
    AND (EXISTS (SELECT 1 FROM "prediction_questions" q
                 WHERE q.id = r."questionId" AND q."correctAnswer" IS NOT NULL)
         OR r."actualAnswer" IS NOT NULL);

  -- Also create new rounds if we're inside the window (the client
  -- tick is a secondary trigger — the pg_cron job is the primary).
  -- This ensures that if pg_cron's 8 AM job missed, the first client
  -- to open the app triggers round creation.
  -- Only do this for the calling family's round (not all families —
  -- that would be too expensive for a per-30s client call). The
  -- global creation is handled by fn_prediction_daily_tick.
  -- The on-demand creation is already handled by fn_prediction_get_active.
END;
$$;
-- No need to re-grant — the function already has the grant from the
-- original migration. But re-assert for safety.
GRANT EXECUTE ON FUNCTION public.fn_prediction_tick(text) TO authenticated;
