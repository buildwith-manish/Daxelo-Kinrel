-- Schedule the bingo-caller Edge Function to run every minute.
-- The function itself checks each in_progress game's lastCallAt and
-- only advances numbers that are due (based on callIntervalSeconds).
-- Running the cron every minute is sufficient because the function
-- handles per-game timing internally — if a game's interval is 5s,
-- it will advance ~12 times per minute when the cron fires.

-- Using Supabase's pg_cron extension (already enabled by default).
-- The function URL pattern: https://<project-ref>.functions.supabase.co/bingo-caller
-- We use the supabase_functions.invoke helper to call the edge function.

SELECT cron.schedule(
  'bingo-caller-every-minute',
  '* * * * *',
  $$
    SELECT net.http_post(
      url := 'https://promxswvsnvilplmrtsj.functions.supabase.co/bingo-caller',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)
      ),
      body := '{}'::jsonb
    );
  $$
);

-- Also schedule a faster poll — every 15 seconds via a 4-cron approach
-- (pg_cron minimum is 1 minute, so we run 4 jobs offset by 15s using
-- pg_sleep in a DO block). For simplicity, we'll just run every minute
-- and rely on the function to advance multiple numbers if multiple
-- intervals have passed since the last call.

-- Note: If finer-grained timing is needed, a separate worker process
-- (e.g., a small Node.js script on Render that pings the function
-- every 5s) would be the alternative. For v1, every-minute cron is
-- acceptable — the function will catch up on missed calls.
