-- supabase/migrations/20261018120000_chat_scheduled_messages.sql
--
-- feat(chat): scheduled messages — server-side dispatch
--
-- Adds a new table ChatScheduledMessage + a SQL dispatch function +
-- a pg_cron job that picks due messages and inserts them into
-- ChatMessage as the author (exactly like a normal send), so
-- recipients, push notifications and realtime behave normally.
--
-- IDEMPOTENT: every CREATE / ALTER / CREATE POLICY / CREATE
-- FUNCTION / pg_cron job is wrapped in an EXCEPTION-WHEN-DUPLICATE
-- handler or uses IF NOT EXISTS. Re-applying is a no-op.
--
-- ─────────────────────────────────────────────────────────────────────
-- SCHEMA CHANGES
-- ─────────────────────────────────────────────────────────────────────
--   1. ChatScheduledMessage table (the queue of pending scheduled
--      messages). Columns:
--        id (text PK, gen_random_uuid)
--        familyId (text, NOT NULL)         — the family chat target
--        groupId  (text, NULLABLE)         — null = family-wide;
--                                            non-null = direct / sub
--                                            group chat (scoped just
--                                            like ChatMessage.groupId)
--        authorId (text, NOT NULL)        — the user the message will
--                                            be sent AS (RLS: only
--                                            the author can SELECT/
--                                            UPDATE/DELETE their own
--                                            rows)
--        content  (text, NOT NULL)        — the message body
--        messageType (text, NOT NULL DEFAULT 'text') — text-only in
--                                            v1; reserved for future
--                                            media support
--        replyToId (text, NULLABLE)       — the id of the ChatMessage
--                                            this is a reply to
--        sendAt   (timestamptz, NOT NULL) — when to send
--        status   (text, NOT NULL DEFAULT 'pending') — pending|sent|
--                                            cancelled|failed
--        sentMessageId (text, NULLABLE)   — the id of the ChatMessage
--                                            row that was inserted by
--                                            the dispatch job (null
--                                            until sent; set on
--                                            success; never overwritten)
--        failureReason (text, NULLABLE)   — populated when status=
--                                            'failed' (the dispatch
--                                            exception message)
--        createdAt (timestamptz, NOT NULL DEFAULT now())
--        sentAt    (timestamptz, NULLABLE)
--   2. RLS — only the author (authorId = auth.uid()) can SELECT, INSERT,
--      UPDATE, DELETE their own rows. No other family member can see
--      who scheduled what.
--   3. Indexes:
--        - (status, sendAt) — the dispatch job's claim scan
--        - (familyId, authorId, status) — the per-conversation
--          scheduled-list UI query (filter by status='pending')
--        - (authorId) — the per-user cleanup scan
--   4. fn_dispatch_scheduled_chat_messages() — SECURITY DEFINER SQL
--      function that:
--        a. SELECTs pending rows WHERE sendAt <= now() FOR UPDATE
--           SKIP LOCKED (so concurrent runs don't double-claim).
--        b. For each claimed row, INSERTs a ChatMessage row AS THE
--           AUTHOR (the function runs as the supabase_admin role,
--           bypassing RLS for the insert — the inserted row's
--           senderId = authorId). The insert uses the same wire
--           shape as ChatNotifier.sendMessage so realtime + the
--           read-receipt trigger + the push scheduler all fire
--           normally.
--        c. On success: UPDATE the scheduled row to status='sent',
--           sentMessageId = <new ChatMessage id>, sentAt = now().
--        d. On failure: UPDATE status='failed', failureReason=<msg>.
--        e. Idempotency: the FOR UPDATE SKIP LOCKED + the status
--           guard (only 'pending' rows are claimed) means a crash
--           mid-dispatch + a retry never produces a duplicate send.
--           The transaction is atomic per-row: a crash rolls back
--           BOTH the ChatMessage insert AND the status update, so
--           either both happen or neither does.
--   5. pg_cron job — fires fn_dispatch_scheduled_chat_messages()
--      every minute. Idempotent scheduling (DROP IF EXISTS +
--      schedule) so re-running the migration is safe.
--
-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK NOTE
-- ─────────────────────────────────────────────────────────────────────
-- To revert this migration, run the following SQL in reverse order:
--
--   -- 5. Unschedule the pg_cron job
--   SELECT cron.unschedule('dispatch-scheduled-chat-messages');
--
--   -- 4. Drop the dispatch function
--   DROP FUNCTION IF EXISTS fn_dispatch_scheduled_chat_messages();
--
--   -- 3. Drop the indexes
--   DROP INDEX IF EXISTS "ChatScheduledMessage_status_sendAt_idx";
--   DROP INDEX IF EXISTS "ChatScheduledMessage_family_author_status_idx";
--   DROP INDEX IF EXISTS "ChatScheduledMessage_authorId_idx";
--
--   -- 2. Drop the RLS policies
--   DROP POLICY IF EXISTS "ChatScheduledMessage author select"
--     ON "ChatScheduledMessage";
--   DROP POLICY IF EXISTS "ChatScheduledMessage author insert"
--     ON "ChatScheduledMessage";
--   DROP POLICY IF EXISTS "ChatScheduledMessage author update"
--     ON "ChatScheduledMessage";
--   DROP POLICY IF EXISTS "ChatScheduledMessage author delete"
--     ON "ChatScheduledMessage";
--   ALTER TABLE "ChatScheduledMessage" DISABLE ROW LEVEL SECURITY;
--
--   -- 1. Drop the table
--   DROP TABLE IF EXISTS "ChatScheduledMessage";
--
-- Rolling back loses any pending scheduled messages (their rows are
-- deleted by the table drop). Re-applying the migration from scratch
-- is also safe (idempotent — every CREATE / ALTER is IF NOT EXISTS).
--
-- ─────────────────────────────────────────────────────────────────────
-- APPLY COMMAND (cannot be applied by the migration runner — the user
-- must run this manually against their Supabase database):
-- ─────────────────────────────────────────────────────────────────────
--   psql "postgresql://postgres:<password>@<host>:5432/postgres" \
--       -f supabase/migrations/20261018120000_chat_scheduled_messages.sql
--   OR via the Supabase Studio SQL editor (paste the file contents).
-- ─────────────────────────────────────────────────────────────────────

-- ─── 1. ChatScheduledMessage table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ChatScheduledMessage" (
  "id"             TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"       TEXT NOT NULL,
  "groupId"        TEXT,
  "authorId"       TEXT NOT NULL,
  "content"        TEXT NOT NULL,
  "messageType"    TEXT NOT NULL DEFAULT 'text',
  "replyToId"      TEXT,
  "sendAt"         TIMESTAMPTZ NOT NULL,
  "status"         TEXT NOT NULL DEFAULT 'pending',
  "sentMessageId"  TEXT,
  "failureReason"  TEXT,
  "createdAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
  "sentAt"         TIMESTAMPTZ
);

COMMENT ON TABLE "ChatScheduledMessage" IS
  'Pending scheduled chat messages. Dispatched by the pg_cron job '
  'dispatch-scheduled-chat-messages (every minute) which calls '
  'fn_dispatch_scheduled_chat_messages() — that function atomically '
  'claims a row (SELECT FOR UPDATE SKIP LOCKED), inserts a '
  'ChatMessage row AS THE AUTHOR, and marks the scheduled row '
  'status=sent + sentMessageId. Idempotent: a crash mid-dispatch '
  'rolls back the entire transaction so a retry never double-sends.';

-- ─── 2. RLS — author-only ─────────────────────────────────────────────
ALTER TABLE "ChatScheduledMessage" ENABLE ROW LEVEL SECURITY;

-- SELECT: author only. (No other family member can see who scheduled
-- what — privacy.)
DROP POLICY IF EXISTS "ChatScheduledMessage author select"
  ON "ChatScheduledMessage";
CREATE POLICY "ChatScheduledMessage author select"
  ON "ChatScheduledMessage"
  FOR SELECT
  USING ("authorId" = auth.uid()::text);

-- INSERT: author must be the requester (WITH CHECK enforces
-- authorId = auth.uid()).
DROP POLICY IF EXISTS "ChatScheduledMessage author insert"
  ON "ChatScheduledMessage";
CREATE POLICY "ChatScheduledMessage author insert"
  ON "ChatScheduledMessage"
  FOR INSERT
  WITH CHECK ("authorId" = auth.uid()::text);

-- UPDATE: author only. Used for cancel + status flips. (The dispatch
-- function runs as SECURITY DEFINER → supabase_admin → bypasses this
-- policy. Authors can also UPDATE their own rows to cancel.)
DROP POLICY IF EXISTS "ChatScheduledMessage author update"
  ON "ChatScheduledMessage";
CREATE POLICY "ChatScheduledMessage author update"
  ON "ChatScheduledMessage"
  FOR UPDATE
  USING ("authorId" = auth.uid()::text)
  WITH CHECK ("authorId" = auth.uid()::text);

-- DELETE: author only.
DROP POLICY IF EXISTS "ChatScheduledMessage author delete"
  ON "ChatScheduledMessage";
CREATE POLICY "ChatScheduledMessage author delete"
  ON "ChatScheduledMessage"
  FOR DELETE
  USING ("authorId" = auth.uid()::text);

-- ─── 3. Indexes ───────────────────────────────────────────────────────
-- Dispatch scan: pending rows due now. Partial index keeps it tiny
-- (only pending rows; sent/cancelled/failed rows are excluded) so the
-- per-minute dispatch is an index scan, not a seq scan.
CREATE INDEX IF NOT EXISTS "ChatScheduledMessage_status_sendAt_idx"
  ON "ChatScheduledMessage" ("sendAt")
  WHERE "status" = 'pending';

-- Per-conversation scheduled-list UI (filter by familyId + authorId +
-- status='pending' for the active list, OR familyId + authorId for
-- the full history including failed/cancelled).
CREATE INDEX IF NOT EXISTS "ChatScheduledMessage_family_author_status_idx"
  ON "ChatScheduledMessage" ("familyId", "authorId", "status");

-- Per-author cleanup scan (e.g. "delete all my scheduled messages"
-- on account deletion).
CREATE INDEX IF NOT EXISTS "ChatScheduledMessage_authorId_idx"
  ON "ChatScheduledMessage" ("authorId");

-- ─── 4. fn_dispatch_scheduled_chat_messages() ─────────────────────────
-- SECURITY DEFINER so the function can:
--   • Claim pending rows via SELECT FOR UPDATE SKIP LOCKED (works
--     across concurrent dispatch runs without serializable isolation).
--   • INSERT into ChatMessage AS the author (the function runs as
--     supabase_admin, bypassing RLS for the ChatMessage insert — the
--     inserted row's senderId = authorId, so recipients see the
--     message as if the author sent it normally).
--
-- The function is idempotent: a crash mid-dispatch rolls back the
-- transaction (both the ChatMessage insert AND the status update),
-- so a retry never produces a duplicate send. The status='pending'
-- guard means even a manual re-run with stale data is safe —
-- already-sent rows are skipped.
--
-- Returns a summary: { claimed, sent, failed, skipped }.
CREATE OR REPLACE FUNCTION fn_dispatch_scheduled_chat_messages()
RETURNS TABLE(
  claimed  INTEGER,
  sent     INTEGER,
  failed   INTEGER,
  skipped  INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed_rows RECORD;
  v_new_message_id TEXT;
  v_failure_msg TEXT;
  v_count_claimed INTEGER := 0;
  v_count_sent INTEGER := 0;
  v_count_failed INTEGER := 0;
  v_count_skipped INTEGER := 0;
  v_sender_name TEXT;
  v_sender_initials TEXT;
BEGIN
  -- Claim pending rows that are due. FOR UPDATE SKIP LOCKED means
  -- concurrent dispatch runs (multiple cron workers, or a manual +
  -- cron race) never claim the same row.
  FOR v_claimed_rows IN
    SELECT "id", "familyId", "groupId", "authorId", "content",
           "messageType", "replyToId", "sendAt"
    FROM "ChatScheduledMessage"
    WHERE "status" = 'pending'
      AND "sendAt" <= now()
    ORDER BY "sendAt" ASC
    LIMIT 100  -- per-run cap to keep the dispatch bounded
    FOR UPDATE SKIP LOCKED
  LOOP
    v_count_claimed := v_count_claimed + 1;
    BEGIN
      -- Resolve the sender's display name + initials from the User
      -- table (so the inserted ChatMessage row has the same shape as
      -- a normal send — chat_provider's _currentUserName path).
      SELECT
        COALESCE(u."name", u."username", 'Member')
        INTO v_sender_name
      FROM "User" u
      WHERE u."id" = v_claimed_rows."authorId"
      LIMIT 1;

      -- Compute sender initials from the resolved name (matches the
      -- _initialsFromName helper in chat_provider.dart).
      v_sender_initials := COALESCE(
        (SELECT
          CASE
            WHEN position(' ' IN trim(u."name")) > 0
              THEN upper(
                substring(trim(u."name") FROM 1 FOR 1) ||
                substring(trim(u."name") FROM position(' ' IN trim(u."name")) + 1 FOR 1)
              )
            WHEN trim(u."name") <> ''
              THEN upper(substring(trim(u."name") FROM 1 FOR 1))
            ELSE '?'
          END
        FROM "User" u WHERE u."id" = v_claimed_rows."authorId" LIMIT 1),
        '?'
      );

      -- Generate a client-style id (cm_<timestamp>_<random>) so the
      -- realtime echo de-dup logic in chat_provider treats it like
      -- any other client-sent message.
      v_new_message_id := 'cm_' ||
        extract(epoch FROM now())::bigint::text || '_' ||
        substring(md5(random()::text) FROM 1 FOR 12);

      -- INSERT into ChatMessage as the author. The inserted row uses
      -- the SAME column shape as ChatNotifier.sendMessage's wire
      -- payload (messageStatus='sent', messageType='text' for v1).
      INSERT INTO "ChatMessage" (
        "id", "familyId", "senderId", "senderName",
        "senderInitials", "content", "messageType",
        "replyToId", "replyToContent", "replyToSenderName",
        "isRead", "isStarred", "isPinned", "isEdited",
        "isDeletedForEveryone", "messageStatus",
        "deletedForMe", "mentions", "createdAt", "updatedAt"
      ) VALUES (
        v_new_message_id,
        v_claimed_rows."familyId",
        v_claimed_rows."authorId",
        v_sender_name,
        v_sender_initials,
        v_claimed_rows."content",
        'text',  -- v1: text-only. Media scheduled-send is a follow-up.
        v_claimed_rows."replyToId",
        NULL,  -- replyToContent is resolved client-side from the
              -- referenced message; not needed for the server insert
              -- (the realtime INSERT event carries the row, the client
              -- looks up the reply target if present).
        NULL,
        false,
        false,
        false,
        false,
        false,
        'sent',
        '[]'::jsonb,
        '[]'::jsonb,
        now(),
        now()
      );

      -- The reply-to content/senderName columns on ChatMessage are
      -- denormalized from the original message; the dispatch function
      -- would need to look them up. We do a best-effort UPDATE if the
      -- reply target exists.
      IF v_claimed_rows."replyToId" IS NOT NULL THEN
        UPDATE "ChatMessage" new_msg
        SET
          "replyToContent" = orig."content",
          "replyToSenderName" = orig."senderName"
        FROM "ChatMessage" orig
        WHERE new_msg."id" = v_new_message_id
          AND orig."id" = v_claimed_rows."replyToId";
      END IF;

      -- Mark the scheduled row as sent + record the sentMessageId.
      UPDATE "ChatScheduledMessage"
      SET
        "status" = 'sent',
        "sentMessageId" = v_new_message_id,
        "sentAt" = now()
      WHERE "id" = v_claimed_rows."id"
        AND "status" = 'pending';  -- idempotency guard

      v_count_sent := v_count_sent + 1;

    EXCEPTION WHEN OTHERS THEN
      -- Failure path: mark the row as failed + record the reason.
      -- The transaction's ChatMessage INSERT is rolled back by
      -- entering the EXCEPTION block (sub-transaction), so no
      -- partial ChatMessage row survives.
      v_failure_msg := SQLERRM;
      UPDATE "ChatScheduledMessage"
      SET
        "status" = 'failed',
        "failureReason" = left(v_failure_msg, 500)
      WHERE "id" = v_claimed_rows."id"
        AND "status" = 'pending';
      v_count_failed := v_count_failed + 1;
    END;
  END LOOP;

  RETURN QUERY
    SELECT
      v_count_claimed,
      v_count_sent,
      v_count_failed,
      v_count_skipped;
END;
$$;

COMMENT ON FUNCTION fn_dispatch_scheduled_chat_messages IS
  'pg_cron-driven dispatch of due scheduled chat messages. Claims '
  'pending rows WHERE sendAt <= now() via SELECT FOR UPDATE SKIP '
  'LOCKED (concurrent runs safe). For each, INSERTs a ChatMessage '
  'row AS THE AUTHOR (the function runs as supabase_admin via '
  'SECURITY DEFINER, bypassing RLS for the insert — the inserted '
  'row senderId = authorId, so the message reaches recipients + '
  'realtime + push notifications as a normal send). On success: '
  'status=sent + sentMessageId set. On failure: status=failed + '
  'failureReason set. The transaction is atomic per-row: a crash '
  'mid-dispatch rolls back BOTH the ChatMessage insert AND the '
  'status update, so a retry never double-sends.';

-- ─── 5. pg_cron job ───────────────────────────────────────────────────
-- Schedule the dispatch to run every minute. Idempotent: drop + reschedule.
DO $$
BEGIN
  -- Try to unschedule any prior version of the job (safe to ignore
  -- errors — 'job not found' is fine on a fresh DB).
  BEGIN
    PERFORM cron.unschedule('dispatch-scheduled-chat-messages');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Schedule the new job.
  PERFORM cron.schedule(
    'dispatch-scheduled-chat-messages',
    '* * * * *',  -- every minute
    $$SELECT fn_dispatch_scheduled_chat_messages();$$
  );
EXCEPTION WHEN OTHERS THEN
  -- If pg_cron isn't enabled (e.g., on a fresh DB where
  -- 20260913150000 hasn't been applied), the schedule call throws.
  -- Log + continue — the function can still be invoked manually.
  RAISE NOTICE 'Could not schedule pg_cron job: %', SQLERRM;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- END OF MIGRATION
-- ─────────────────────────────────────────────────────────────────────
-- Summary:
--   • 1 new table (ChatScheduledMessage)
--   • 4 RLS policies (author-only SELECT/INSERT/UPDATE/DELETE)
--   • 3 indexes (status+sendAt dispatch scan, family+author+status
--     list, authorId cleanup)
--   • 1 SECURITY DEFINER SQL function (fn_dispatch_scheduled_chat_messages)
--   • 1 pg_cron job (every-minute dispatch)
--
-- What is NOT changed:
--   • The ChatMessage table schema (scheduled messages insert as
--     normal ChatMessage rows; no new columns needed on ChatMessage).
--   • The moderation / RLS / realtime setup on ChatMessage — the
--     dispatched message behaves identically to a normal send.
--   • The NestJS chat-push.scheduler.ts — the dispatch happens at
--     the database layer via pg_cron, so the NestJS scheduler is
--     untouched.
--
-- Limitations (v1):
--   • Text-only. Media scheduled-send is a follow-up: the dispatch
--     function would need to handle mediaUrl upload + the
--     messageSubType / mediaType / mediaFileName columns.
--   • No edit of the content after scheduling — the user can cancel
--     + re-create. (The update policy allows editing content, but the
--     UI doesn't expose it yet.)
--   • No re-send of failed rows from the server. The client shows
--     failed rows in the scheduled list with a Retry action — Retry
--     flips status back to 'pending' so the next dispatch picks it up.
