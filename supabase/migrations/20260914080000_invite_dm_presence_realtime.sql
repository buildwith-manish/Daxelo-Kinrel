-- =============================================================================
-- Daxelo-Kinrel — Task 4: Invitation + Presence realtime fixes
-- =============================================================================
-- Root causes fixed by this migration:
--
-- 1. ROOM JOIN NOT REAL-TIME FOR THE HOST:
--    RoomController (all 14 games) subscribes to game_participants /
--    game_spectators / game_room_events realtime, but those tables were
--    NEVER added to the supabase_realtime publication → zero events
--    flowed → the host's participant roster, ready badges, spectator
--    list and cancel events only updated on manual refresh.
--    FIX: add all three tables to the publication with
--    REPLICA IDENTITY FULL (FULL so DELETE events carry the whole old
--    row — the client DELETE handlers read old row "userId").
--
-- 2. STALE ROSTER ON LEAVE:
--    Per-game player tables (sos_players etc.) use surrogate `id` PKs
--    with default replica identity → DELETE events only carried `id`,
--    so the providers' `oldRecord['userId']` handlers silently no-oped.
--    FIX: REPLICA IDENTITY FULL on the player tables that are already
--    in the publication.
--
-- 3. PRESENCE NEVER MARKED ONLINE / STUCK ONLINE:
--    UserPresence infra exists, but only the family-chat screen updated
--    it, and a killed tab left users "online" forever. The app now
--    heartbeats every 30s (client change); this migration adds a
--    server-side sweeper that flips offline any presence row whose
--    heartbeat stopped > 75s ago (pg_cron, every 60s).
--
-- 4. DM INVITES (Specific Members):
--    DirectMessage.messageType has no CHECK constraint (verified in
--    production), so the new 'gameInvite' DM type needs no schema
--    change. DirectMessage is already in the realtime publication with
--    REPLICA IDENTITY FULL.
-- =============================================================================

-- ── 1) Realtime: room metadata tables ─────────────────────────────
ALTER TABLE "game_participants" REPLICA IDENTITY FULL;
ALTER TABLE "game_spectators"  REPLICA IDENTITY FULL;
ALTER TABLE "game_room_events" REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'game_participants'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_participants";
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'game_spectators'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_spectators";
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'game_room_events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_room_events";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'room-table realtime setup: %', SQLERRM;
END $$;

-- ── 2) Realtime: per-game player tables → FULL replica identity ───
--    (DELETE events must carry "userId" in the old row)
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'sos_players','antakshari_players','ludo_players','chitmatch_players',
    'nameplace_players','truthordare_players','twotruths_players',
    'redlight_players','bingo_cards'
  ]
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'replica identity %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ── 3) Stale-presence sweeper (pg_cron) ───────────────────────────
--    Client heartbeats fn_update_last_seen(true) every 30s. If a tab is
--    killed (no dispose), the row stays isOnline=true forever. This job
--    flips offline anything whose heartbeat stopped > 75 seconds ago,
--    so "online" indicators stay truthful across all devices.
CREATE OR REPLACE FUNCTION fn_sweep_stale_presence()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_flipped integer := 0;
BEGIN
  UPDATE "UserPresence"
  SET "isOnline" = false,
      "lastSeenAt" = COALESCE("lastSeenAt", "updatedAt"),
      "updatedAt" = now()
  WHERE "isOnline" = true
    AND "updatedAt" < now() - interval '75 seconds';
  GET DIAGNOSTICS v_flipped = ROW_COUNT;
  RETURN v_flipped;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_sweep_stale_presence() TO authenticated;

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  -- pg_cron was enabled by 20260913150000; re-assert idempotently.
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA cron;
  GRANT USAGE ON SCHEMA cron TO authenticated;

  BEGIN
    v_jobid := cron.schedule(
      'sweep-stale-user-presence',
      '*/10 * * * * *',
      'SELECT public.fn_sweep_stale_presence();'
    );
    RAISE NOTICE 'Scheduled sweep-stale-user-presence (jobid=%)', v_jobid;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_jobid := cron.alter_job(
        jobname := 'sweep-stale-user-presence',
        schedule := '*/10 * * * * *',
        command := 'SELECT public.fn_sweep_stale_presence();',
        active := true
      );
      RAISE NOTICE 'Altered sweep-stale-user-presence (jobid=%)', v_jobid;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'presence sweeper scheduling: %', SQLERRM;
    END;
  END;
END $$;

-- ── 4) Verification ───────────────────────────────────────────────
SELECT 'game_participants' AS tbl,
       EXISTS(SELECT 1 FROM pg_publication_tables
              WHERE pubname='supabase_realtime'
                AND tablename='game_participants') AS in_pub;
SELECT 'game_room_events' AS tbl,
       EXISTS(SELECT 1 FROM pg_publication_tables
              WHERE pubname='supabase_realtime'
                AND tablename='game_room_events') AS in_pub;
