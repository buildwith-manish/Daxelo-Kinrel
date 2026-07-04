-- Schedule the bingo-caller Edge Function to run every minute.
-- The function itself checks each in_progress game's lastCallAt and
-- only advances numbers that are due (based on callIntervalSeconds).

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule the bingo-caller to run every minute
-- The function is idempotent and handles per-game timing internally
SELECT cron.schedule(
  'bingo-caller-every-minute',
  '* * * * *',
  $$
    SELECT net.http_post(
      url := 'https://promxswvsnvilplmrtsj.functions.supabase.co/bingo-caller',
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    );
  $$
);
