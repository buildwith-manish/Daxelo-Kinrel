-- =============================================================================
-- Daxelo-Kinrel — scheduled_game_nights table + reminder cron
-- =============================================================================
-- Implements section 4 of the feature spec: family game night scheduling.
-- Hosts can schedule a game for a future date/time. A pg_cron job runs
-- every 5 minutes, checks for scheduled_game_nights rows due within the
-- next 15 minutes (send reminder) or due now (create the real game row +
-- send invites + mark status 'started').
--
-- The actual game-row creation is done by an Edge Function because it needs
-- to know each game table's column shape (hostUserId vs playerOneId, etc.).
-- The cron job just fires the Edge Function with the scheduled_game_night id.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "scheduled_game_nights" (
  "id"              text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        text NOT NULL,
  "hostUserId"      text NOT NULL,
  "hostUserName"    text,
  "gameType"        text NOT NULL,   -- 'bingo', 'ludo', etc. (matches GameType.routeSegment)
  "scheduledFor"    timestamptz NOT NULL,
  "invitedUserIds"  text[] NOT NULL DEFAULT '{}',
  "status"          text NOT NULL DEFAULT 'scheduled',  -- scheduled | reminded | started | cancelled
  "createdGameId"   text,             -- set when the real game row is created
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "reminderSentAt"  timestamptz,
  "startedAt"       timestamptz
);

CREATE INDEX IF NOT EXISTS idx_scheduled_game_nights_family
  ON "scheduled_game_nights" ("familyId", "scheduledFor" DESC);

CREATE INDEX IF NOT EXISTS idx_scheduled_game_nights_status_due
  ON "scheduled_game_nights" ("status", "scheduledFor")
  WHERE "status" IN ('scheduled', 'reminded');

CREATE INDEX IF NOT EXISTS idx_scheduled_game_nights_host
  ON "scheduled_game_nights" ("hostUserId", "createdAt" DESC);

ALTER TABLE "scheduled_game_nights" ENABLE ROW LEVEL SECURITY;

-- SELECT: family members can see their family's scheduled game nights
CREATE POLICY "scheduled_game_nights_select_family"
  ON "scheduled_game_nights" FOR SELECT
  TO authenticated
  USING (fn_user_is_family_member("familyId"));

-- INSERT/UPDATE/DELETE: only the host can modify their own scheduled nights
CREATE POLICY "scheduled_game_nights_insert_host"
  ON "scheduled_game_nights" FOR INSERT
  TO authenticated
  WITH CHECK ("hostUserId" = auth.uid()::text);

CREATE POLICY "scheduled_game_nights_update_host"
  ON "scheduled_game_nights" FOR UPDATE
  TO authenticated
  USING ("hostUserId" = auth.uid()::text)
  WITH CHECK ("hostUserId" = auth.uid()::text);

CREATE POLICY "scheduled_game_nights_delete_host"
  ON "scheduled_game_nights" FOR DELETE
  TO authenticated
  USING ("hostUserId" = auth.uid()::text);

-- ── pg_cron: every 5 minutes, fire the scheduler Edge Function ──────────
-- The Edge Function does the actual work:
--   1. Find scheduled_game_nights WHERE status='scheduled' AND scheduledFor <= now() + 15min
--      → send reminder FCM + UPDATE status='reminded'
--   2. Find scheduled_game_nights WHERE status IN ('scheduled','reminded') AND scheduledFor <= now()
--      → create the real {game}_games row
--      → send game_invites to each invitedUserIds entry (triggers FCM push via section 1 trigger)
--      → UPDATE status='started', createdGameId=<new game id>

DO $_outer_$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'scheduled-game-nights-process'
  ) THEN
    PERFORM cron.schedule(
      'scheduled-game-nights-process',
      '*/5 * * * *',
      $_inner_$
        SELECT net.http_post(
          url := 'https://promxswvsnvilplmrtsj.supabase.co/functions/v1/process-scheduled-game-nights',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.service_role_token', true)
          ),
          body := '{}'::jsonb
        );
      $_inner_$
    );
  END IF;
END $_outer_$;
