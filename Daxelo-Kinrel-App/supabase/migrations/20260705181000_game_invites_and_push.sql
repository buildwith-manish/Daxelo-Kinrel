-- =============================================================================
-- Daxelo-Kinrel — game_invites + device_tokens + FCM push for invites
-- =============================================================================
-- Implements section 1 of the feature spec: push notifications for game
-- invites. When a host sends an invite (specific member or entire family
-- space), an in-app realtime event fires immediately via Socket.IO AND a
-- row is inserted here, which an AFTER INSERT trigger relays to an Edge
-- Function that calls FCM.
--
-- Foreground suppression: the Flutter client sets a flag on the invite
-- receipt (in-memory) so the push isn't shown if the user already saw the
-- in-app dialog. This is handled client-side; the server always sends the
-- push (it can't know foreground state).
--
-- Expiry: a 10-minute pg_cron job marks stale pending invites as expired.
-- =============================================================================

-- ── device_tokens table ───────────────────────────────────────────────────
-- (Mirrors the existing FcmToken Prisma model so the Flutter app can read
-- tokens directly via Supabase without going through NestJS. The NestJS
-- FcmToken table is the source of truth — this is a denormalized mirror
-- populated by the Flutter app on token refresh.)

CREATE TABLE IF NOT EXISTS "device_tokens" (
  "id"          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"      text NOT NULL,
  "fcmToken"    text NOT NULL,
  "platform"    text NOT NULL DEFAULT 'unknown',  -- ios | android | web | unknown
  "updatedAt"   timestamptz NOT NULL DEFAULT now(),
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_device_tokens_token
  ON "device_tokens" ("fcmToken");

CREATE INDEX IF NOT EXISTS idx_device_tokens_user
  ON "device_tokens" ("userId");

ALTER TABLE "device_tokens" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "device_tokens_select_self"
  ON "device_tokens" FOR SELECT
  TO authenticated
  USING ("userId" = auth.uid()::text);

CREATE POLICY "device_tokens_insert_self"
  ON "device_tokens" FOR INSERT
  TO authenticated
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "device_tokens_update_self"
  ON "device_tokens" FOR UPDATE
  TO authenticated
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "device_tokens_delete_self"
  ON "device_tokens" FOR DELETE
  TO authenticated
  USING ("userId" = auth.uid()::text);

-- ── game_invites table ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "game_invites" (
  "id"              text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameTable"       text NOT NULL,    -- 'bingo_games', 'ludo_games', etc.
  "gameId"          text NOT NULL,    -- FK to the specific game row
  "gameType"        text NOT NULL,    -- 'bingo', 'ludo', etc. (for display + routing)
  "familyId"        text NOT NULL,
  "roomCode"        text,             -- 6-char display code
  "invitedUserId"   text NOT NULL,
  "invitedByUserId" text NOT NULL,
  "invitedByName"   text,
  "maxPlayers"      int DEFAULT 2,
  "currentPlayers"  int DEFAULT 1,
  "message"         text,
  "status"          text NOT NULL DEFAULT 'pending',  -- pending | accepted | declined | expired
  "sourceGameId"    text,             -- nullable; set when this invite came from a Rematch
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "respondedAt"     timestamptz,
  "expiresAt"       timestamptz NOT NULL DEFAULT now() + interval '10 minutes'
);

CREATE INDEX IF NOT EXISTS idx_game_invites_invited_user
  ON "game_invites" ("invitedUserId", "status", "createdAt" DESC);

CREATE INDEX IF NOT EXISTS idx_game_invites_game
  ON "game_invites" ("gameTable", "gameId");

CREATE INDEX IF NOT EXISTS idx_game_invites_status_expires
  ON "game_invites" ("status", "expiresAt")
  WHERE "status" = 'pending';

CREATE INDEX IF NOT EXISTS idx_game_invites_sender
  ON "game_invites" ("invitedByUserId", "createdAt" DESC);

ALTER TABLE "game_invites" ENABLE ROW LEVEL SECURITY;

-- Helper: is the caller a member of the family on this invite?
CREATE OR REPLACE FUNCTION fn_user_is_family_member_check(p_family_id text, p_user_id text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "FamilyMember" fm
    WHERE fm."familyId" = p_family_id
      AND fm."userId" = p_user_id
  );
$$;

-- SELECT: caller can see invites they sent OR received (both must be family members)
CREATE POLICY "game_invites_select_self"
  ON "game_invites" FOR SELECT
  TO authenticated
  USING (
    "invitedUserId" = auth.uid()::text
    OR ("invitedByUserId" = auth.uid()::text
        AND fn_user_is_family_member_check("familyId", auth.uid()::text))
  );

-- INSERT: any authenticated family member can invite others
CREATE POLICY "game_invites_insert_family"
  ON "game_invites" FOR INSERT
  TO authenticated
  WITH CHECK (
    "invitedByUserId" = auth.uid()::text
    AND fn_user_is_family_member_check("familyId", auth.uid()::text)
  );

-- UPDATE: invited user can update status (accept/decline); sender can mark expired
CREATE POLICY "game_invites_update_invited"
  ON "game_invites" FOR UPDATE
  TO authenticated
  USING (
    "invitedUserId" = auth.uid()::text
    OR "invitedByUserId" = auth.uid()::text
  )
  WITH CHECK (
    "invitedUserId" = auth.uid()::text
    OR "invitedByUserId" = auth.uid()::text
  );

-- ── AFTER INSERT trigger → call FCM Edge Function ───────────────────────
-- Mirrors the bingo-caller pattern: uses pg_net.http_post to invoke an
-- Edge Function that reads the invite row + the recipient's device_tokens
-- and sends the FCM push.

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
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_token', true)
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

DROP TRIGGER IF EXISTS trg_game_invite_fcm ON "game_invites";
CREATE TRIGGER trg_game_invite_fcm
  AFTER INSERT ON "game_invites"
  FOR EACH ROW
  EXECUTE FUNCTION fn_trigger_game_invite_fcm();

-- ── pg_cron: expire stale pending invites every 5 minutes ──────────────
-- Marks invites past their expiresAt as 'expired' so the recipient stops
-- seeing them and the sender sees them flip to 'expired' in their
-- PendingInvitesSection.

CREATE OR REPLACE FUNCTION fn_expire_stale_game_invites()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE "game_invites"
  SET "status" = 'expired',
      "respondedAt" = now()
  WHERE "status" = 'pending'
    AND "expiresAt" < now();
$$;

-- Schedule the expiry job (every 5 minutes). Idempotent — check if exists first.
-- Use $_$ ... $_$ for the inner string to avoid $$ conflict with the DO block.
DO $_outer_$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'expire-stale-game-invites'
  ) THEN
    PERFORM cron.schedule(
      'expire-stale-game-invites',
      '*/5 * * * *',
      $_inner_$ SELECT fn_expire_stale_game_invites(); $_inner_$
    );
  END IF;
END $_outer_$;
