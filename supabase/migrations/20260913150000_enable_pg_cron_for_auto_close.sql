-- =============================================================================
-- Daxelo-Kinrel — Enable pg_cron + schedule the auto-close + reaper jobs
-- =============================================================================
-- Root cause of "non-functional auto-close timer":
-- The original migration (20260913120000) included an idempotent
-- INSERT INTO cron.jobs, BUT only IF the cron schema already existed.
-- On Supabase instances where pg_cron is not enabled by default, that
-- IF EXISTS check silently skipped the INSERT — so the cron jobs were
-- never registered, and fn_close_expired_rooms never ran server-side.
--
-- This migration:
--   1. Creates the pg_cron extension (idempotent — CREATE EXTENSION IF
--      NOT EXISTS).
--   2. Registers the auto-close job (every 30 seconds).
--   3. Registers the disconnected-player reaper (every 15 seconds).
--
-- After this migration, the local AutoCloseTimer widget's countdown
-- hitting zero is matched by the server actually closing the room
-- (within 30s) — no more fake countdowns.
-- =============================================================================

-- ── 1. Enable pg_cron ──────────────────────────────────────────────
-- Requires superuser ( Supabase service_role has this via the SQL
-- editor). The extension is created in the `cron` schema.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA cron;

-- Allow the cron schema to be accessed by authenticated users (the
-- RPCs are SECURITY DEFINER so they can call fn_close_expired_rooms
-- directly; this GRANT is just for schema visibility).
GRANT USAGE ON SCHEMA cron TO authenticated;

-- ── 2. Register / refresh the auto-close job ───────────────────────
-- `cron.schedule()` is the modern pg_cron API. It returns a bigint
-- jobid. `cron.alter_job` lets us update schedule + active flag without
-- dropping + recreating.
--
-- Schedule: every 30 seconds (`*/30 * * * * *` — 6-field with seconds)
-- Command: SELECT public.fn_close_expired_rooms();
DO $$
DECLARE
  v_jobid bigint;
BEGIN
  -- Try to schedule. If the jobname already exists, schedule() throws
  -- an exception -- so catch it and use alter_job instead.
  BEGIN
    v_jobid := cron.schedule(
      'close-expired-game-rooms',
      '*/30 * * * * *',
      'SELECT public.fn_close_expired_rooms();'
    );
    RAISE NOTICE 'Scheduled close-expired-game-rooms (jobid=%)', v_jobid;
  EXCEPTION WHEN OTHERS THEN
    -- Already scheduled -- alter the schedule in case it changed.
    BEGIN
      v_jobid := cron.alter_job(
        jobname := 'close-expired-game-rooms',
        schedule := '*/30 * * * * *',
        command := 'SELECT public.fn_close_expired_rooms();',
        active := true
      );
      RAISE NOTICE 'Altered existing close-expired-game-rooms job';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not schedule/alter close-expired-game-rooms: %', SQLERRM;
    END;
  END;

  -- Reaper job: every 15 seconds, mark players with lastSeenAt > 60s
  -- ago as 'offline' (and if host, close the room).
  BEGIN
    v_jobid := cron.schedule(
      'reap-disconnected-game-players',
      '*/15 * * * * *',
      'SELECT public.fn_reap_disconnected_players(60);'
    );
    RAISE NOTICE 'Scheduled reap-disconnected-game-players (jobid=%)', v_jobid;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_jobid := cron.alter_job(
        jobname := 'reap-disconnected-game-players',
        schedule := '*/15 * * * * *',
        command := 'SELECT public.fn_reap_disconnected_players(60);',
        active := true
      );
      RAISE NOTICE 'Altered existing reap-disconnected-game-players job';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not schedule/alter reap-disconnected-game-players: %', SQLERRM;
    END;
  END;
END $$;

-- ── 3. Verify the jobs landed ─────────────────────────────────────
-- (This is just a NOTICE — not a hard failure if 0 rows for some reason.)
-- NOTE: the table is `cron.job` (singular) in pg_cron 1.6+. The
-- original migration (20260913120000) used `cron.jobs` (plural) which
-- silently failed — that's why the cron jobs were never registered.
DO $$
DECLARE
  v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM cron.job
  WHERE jobname IN ('close-expired-game-rooms', 'reap-disconnected-game-players')
    AND active = true;
  RAISE NOTICE 'Active multiplayer cron jobs registered: %', v_cnt;
END $$;
