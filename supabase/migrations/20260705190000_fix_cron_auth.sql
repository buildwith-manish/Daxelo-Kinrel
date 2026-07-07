-- =============================================================================
-- Fix: update the game_invites FCM trigger + scheduled_game_nights cron
-- to use a properly-set secret instead of current_setting('app.service_role_token')
-- which isn't configured on this Supabase project.
--
-- The Edge Functions use Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') internally,
-- so they don't need the caller to pass an Authorization header. We just need
-- to POST to the function URL with an empty body — the function will use its
-- own service role key to read the invite + device_tokens tables.
-- =============================================================================

-- 1. Replace the FCM trigger function to NOT pass an Authorization header
CREATE OR REPLACE FUNCTION fn_trigger_game_invite_fcm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only push for fresh invites (not for status updates)
  IF NEW."status" = 'pending' AND (TG_OP = 'INSERT') THEN
    PERFORM net.http_post(
      url := 'https://promxswvsnvilplmrtsj.supabase.co/functions/v1/send-game-invite-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'inviteId', NEW."id",
        'gameType', NEW."gameType",
        'gameId', NEW."gameId",
        'roomCode', NEW."roomCode",
        'familyId', NEW."familyId",
        'invitedUserId', NEW."invitedUserId",
        'invitedByName', NEW."invitedByName",
        'message', NEW."message",
        'maxPlayers', NEW."maxPlayers",
        'currentPlayers', NEW."currentPlayers"
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- 2. Replace the scheduled_game_nights cron job to NOT pass an Authorization header
DO $_outer_$
BEGIN
  -- Unschedule the old job that used current_setting('app.service_role_token')
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scheduled-game-nights-process') THEN
    PERFORM cron.unschedule('scheduled-game-nights-process');
  END IF;

  PERFORM cron.schedule(
    'scheduled-game-nights-process',
    '*/5 * * * *',
    $_inner_$
      SELECT net.http_post(
        url := 'https://promxswvsnvilplmrtsj.supabase.co/functions/v1/process-scheduled-game-nights',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
    $_inner_$
  );
END $_outer_$;
