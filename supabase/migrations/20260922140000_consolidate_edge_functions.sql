-- 20260922140000_consolidate_edge_functions.sql
--
-- Tier 3 #7 — Consolidate Edge Functions (Group A: cron-triggered only).
--
-- CRITICAL CAVEAT (from user prompt): only merge functions that share
-- the same trigger type. Do NOT merge a cron-scheduled function with a
-- user-action-triggered function. We respect this by ONLY converting
-- the one remaining cron-triggered Edge Function (process-scheduled-
-- game-nights) to a direct SQL pg_cron call — eliminating the HTTP hop
-- and Deno cold-start latency entirely. The user-action-triggered
-- functions (ludo-roll-dice, send-game-invite-push, check-game-badges,
-- bingo-verify-claim, get-active-family-games) are kept as independent
-- Edge Functions.
--
-- bingo-caller was already consolidated in migration 20260919100000:
-- the pg_cron job now calls fn_bingo_call_all_due() directly (SQL),
-- not the Edge Function HTTP endpoint. The Edge Function is still
-- deployed but no longer actively scheduled.
--
-- WHAT THIS MIGRATION DOES:
-- 1. Creates fn_process_scheduled_game_nights() — a SQL function that
--    replaces the process-scheduled-game-nights Edge Function. It
--    handles the same two cases:
--    a. REMINDER (status='scheduled', scheduledFor within next 15 min):
--       — We skip the FCM push (the Edge Function's sendReminderPush
--         was a console.log stub anyway — "would send to N tokens").
--         The reminder status update is what matters: once status flips
--         to 'reminded', the client UI can show the reminder state.
--    b. START (status IN ('scheduled','reminded'), scheduledFor <= now):
--       — Creates the game row via INSERT into the appropriate
--         {gameType}_games table.
--       — Inserts game_invites rows (which triggers the AFTER INSERT
--         trigger that fires FCM push via send-game-invite-push Edge
--         Function — same as the Edge Function did).
--       — Updates status='started', createdGameId, startedAt.
--
-- 2. Unschedules the old 'scheduled-game-nights-process' pg_cron job
--    (which fired the Edge Function via HTTP POST).
--
-- 3. Schedules a new pg_cron job that calls the SQL function directly
--    every 5 minutes — no HTTP hop, no Deno cold start.
--
-- The user-action-triggered Edge Functions are NOT touched:
--   • ludo-roll-dice — user-action (dice roll button)
--   • send-game-invite-push — trigger (AFTER INSERT on game_invites)
--   • check-game-badges — user-action (post-game)
--   • bingo-verify-claim — user-action (BINGO button)
--   • get-active-family-games — user-action (screen load)

-- ─────────────────────────────────────────────────────────────────────
-- 1. SQL function to replace the Edge Function
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_process_scheduled_game_nights()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_reminder_window timestamptz := now() + interval '15 minutes';
  v_sn record;
  v_game_table text;
  v_game_id text;
  v_room_code text;
  v_invites jsonb;
  v_game_display text;
  v_reminders_count int := 0;
  v_started_count int := 0;
BEGIN
  -- ── 1. REMINDERS ──────────────────────────────────────────────────
  -- Mark scheduled game nights within the 15-minute reminder window
  -- as 'reminded'. The Edge Function also sent an FCM push, but that
  -- was a console.log stub ("would send to N tokens"). The status
  -- flip is what the client UI reads to show the reminder state.
  FOR v_sn IN
    SELECT * FROM "scheduled_game_nights"
    WHERE status = 'scheduled'
      AND "scheduledFor" <= v_reminder_window
      AND "scheduledFor" > v_now
  LOOP
    UPDATE "scheduled_game_nights"
    SET status = 'reminded', "reminderSentAt" = v_now
    WHERE id = v_sn.id;
    v_reminders_count := v_reminders_count + 1;
  END LOOP;

  -- ── 2. START ─────────────────────────────────────────────────────
  -- For scheduled game nights whose time has arrived, create the real
  -- game row and insert game_invites (which triggers the FCM push via
  -- the existing AFTER INSERT trigger on game_invites →
  -- send-game-invite-push Edge Function).
  FOR v_sn IN
    SELECT * FROM "scheduled_game_nights"
    WHERE status IN ('scheduled', 'reminded')
      AND "scheduledFor" <= v_now
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

    -- Display name for the invite message.
    v_game_display := CASE v_sn."gameType"
      WHEN 'bingo' THEN 'Bingo'
      WHEN 'ludo' THEN 'Ludo'
      WHEN 'checkers' THEN 'Checkers'
      WHEN 'carrom' THEN 'Carrom'
      WHEN 'chess' THEN 'Chess'
      WHEN 'sos' THEN 'SOS'
      WHEN 'antakshari' THEN 'Antakshari'
      WHEN 'freeze-dash' THEN 'Freeze & Dash'
      WHEN 'nameplace' THEN 'Name, Place, Animal, Thing'
      WHEN 'tictactoe' THEN 'Tic-Tac-Toe'
      WHEN 'truthordare' THEN 'Truth or Dare'
      WHEN 'twotruths' THEN 'Two Truths and a Lie'
      WHEN 'dotsboxes' THEN 'Dots and Boxes'
      WHEN 'chitmatch' THEN 'TripleMatch'
      ELSE 'Game'
    END;

    -- Create the game row via dynamic SQL (each game table has a
    -- different schema, but all share the common columns: familyId,
    -- hostUserId, hostUserName, status, spectatorsEnabled).
    BEGIN
      EXECUTE format(
        'INSERT INTO %I ("familyId", "hostUserId", "hostUserName", status, "spectatorsEnabled", "createdAt")
         VALUES ($1, $2, $3, ''waiting'', true, $4)
         RETURNING id::text',
        v_game_table
      ) INTO v_game_id
      USING v_sn."familyId", v_sn."hostUserId", v_sn."hostUserName", v_now;

      IF v_game_id IS NOT NULL THEN
        v_room_code := upper(replace(v_game_id, '-', ''));
        v_room_code := substring(v_room_code from 1 for 6);

        -- Insert game_invites for each invited user. The AFTER INSERT
        -- trigger on game_invites fires the send-game-invite-push Edge
        -- Function for each row — same flow as the Edge Function used.
        v_invites := '[]'::jsonb;
        IF v_sn."invitedUserIds" IS NOT NULL AND jsonb_array_length(v_sn."invitedUserIds") > 0 THEN
          SELECT jsonb_agg(jsonb_build_object(
            'gameTable', v_game_table,
            'gameId', v_game_id,
            'gameType', v_sn."gameType",
            'familyId', v_sn."familyId",
            'roomCode', v_room_code,
            'invitedUserId', elem,
            'invitedByUserId', v_sn."hostUserId",
            'invitedByName', v_sn."hostUserName",
            'maxPlayers', 2,
            'currentPlayers', 1,
            'message', COALESCE(v_sn."hostUserName", 'A family member') || '''s ' || v_game_display || ' night is starting now!',
            'status', 'pending',
            'sourceGameId', 'null'
          )) INTO v_invites
          FROM jsonb_array_elements_text(v_sn."invitedUserIds") AS elem;
        END IF;

        IF v_invites IS NOT NULL AND jsonb_array_length(v_invites) > 0 THEN
          INSERT INTO "game_invites" ("gameTable", "gameId", "gameType", "familyId", "roomCode",
            "invitedUserId", "invitedByUserId", "invitedByName", "maxPlayers", "currentPlayers",
            "message", "status", "sourceGameId")
          SELECT
            elem->>'gameTable', elem->>'gameId', elem->>'gameType', elem->>'familyId',
            elem->>'roomCode', elem->>'invitedUserId', elem->>'invitedByUserId',
            elem->>'invitedByName', (elem->>'maxPlayers')::int, (elem->>'currentPlayers')::int,
            elem->>'message', elem->>'status',
            NULLIF(elem->>'sourceGameId', 'null')
          FROM jsonb_array_elements(v_invites) AS elem;
        END IF;

        -- Update the scheduled game night status.
        UPDATE "scheduled_game_nights"
        SET status = 'started', "createdGameId" = v_game_id, "startedAt" = v_now
        WHERE id = v_sn.id;

        v_started_count := v_started_count + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Log and continue — don't let one failed game night block others.
      RAISE NOTICE 'Failed to start game night %: %', v_sn.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'remindersSent', v_reminders_count,
    'gamesStarted', v_started_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_process_scheduled_game_nights() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Replace the pg_cron schedule
-- ─────────────────────────────────────────────────────────────────────

-- Unschedule the old HTTP-hop job.
SELECT cron.unschedule('scheduled-game-nights-process')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scheduled-game-nights-process');

-- Schedule the new SQL-direct job (every 5 minutes, same cadence).
SELECT cron.schedule(
  'scheduled-game-nights-process',
  '*/5 * * * *',
  $$ SELECT public.fn_process_scheduled_game_nights(); $$
);
