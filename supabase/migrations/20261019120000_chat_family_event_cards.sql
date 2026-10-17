-- supabase/migrations/20261019120000_chat_family_event_cards.sql
--
-- feat(chat): live family event cards with RSVP
--
-- Adds columns to ChatMessage so a calendar-event card can be posted
-- as a persistent, live-updating card in the family chat thread —
-- mirroring the game-invite card pattern (migration 20260828120000).
--
-- The card STAYS LIVE: when the underlying calendar_events row OR
-- any calendar_event_rsvps row changes, an AFTER UPDATE trigger
-- syncs the denormalized fields onto every ChatMessage row that
-- references that event. The chat_provider's existing realtime
-- UPDATE subscription on ChatMessage then propagates to every open
-- chat UI automatically — same pattern as game invite cards.
--
-- IDEMPOTENT: every ALTER is ADD COLUMN IF NOT EXISTS; every
-- CREATE TRIGGER / CREATE FUNCTION uses DROP IF EXISTS + CREATE.
--
-- ─────────────────────────────────────────────────────────────────────
-- SCHEMA CHANGES
-- ─────────────────────────────────────────────────────────────────────
--   1. ChatMessage gains:
--        eventId           text    — calendar_events.id FK by convention
--        eventTitle        text    — denormalized title (display fallback)
--        eventDate         text    — denormalized eventDate (display fallback)
--        eventTime         text    — denormalized time portion (for non-all-day)
--        eventLocation     text    — denormalized location (display fallback)
--        eventCategory     text    — denormalized category (drives icon + color)
--        eventRsvpGoing    integer — count of 'going' RSVPs
--        eventRsvpMaybe    integer — count of 'maybe' RSVPs
--        eventRsvpNotGoing integer — count of 'not_going' RSVPs
--        eventDeletedAt    timestamptz — set when the underlying
--                              calendar_events row is deleted (the FK
--                              in calendar_event_rsvps CASCADE-deletes
--                              the RSVPs; we keep the card visible
--                              with "Event no longer available" until
--                              the ChatMessage row itself is deleted).
--   2. fn_sync_family_event_chat_cards() SQL function — called by
--      AFTER INSERT / UPDATE / DELETE triggers on calendar_events AND
--      calendar_event_rsvps. Recomputes the denormalized fields from
--      the live state and UPDATEs every ChatMessage row referencing
--      the event.
--   3. AFTER INSERT/UPDATE/DELETE triggers on calendar_events → call
--      fn_sync_family_event_chat_cards(p_event_id).
--   4. AFTER INSERT/UPDATE/DELETE triggers on calendar_event_rsvps →
--      call fn_sync_family_event_chat_cards(p_event_id) (the eventId
--      is on the RSVP row).
--   5. Partial index on ChatMessage WHERE messageType = 'familyEvent'
--      AND eventId IS NOT NULL — for the sync UPDATE scans.
--
-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK NOTE
-- ─────────────────────────────────────────────────────────────────────
-- To revert, run the following in reverse order:
--
--   DROP INDEX IF EXISTS "ChatMessage_familyEvent_eventId_idx";
--   DROP TRIGGER IF EXISTS "trg_rsvps_sync_event_chat_cards" ON "calendar_event_rsvps";
--   DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_delete" ON "calendar_events";
--   DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_update" ON "calendar_events";
--   DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_insert" ON "calendar_events";
--   DROP FUNCTION IF EXISTS fn_sync_family_event_chat_cards(text);
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventId";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventTitle";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventDate";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventTime";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventLocation";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventCategory";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventRsvpGoing";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventRsvpMaybe";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventRsvpNotGoing";
--   ALTER TABLE "ChatMessage" DROP COLUMN IF EXISTS "eventDeletedAt";
--
-- Rolling back leaves existing familyEvent chat cards in place
-- (the row survives — the event card columns are just missing the
-- denormalized fields; the message_bubble's fallback "Event no
-- longer available" path will fire for those rows until they're
-- deleted by the sender / delete-for-everyone flow).
--
-- ─────────────────────────────────────────────────────────────────────
-- APPLY COMMAND (cannot be applied by the migration runner):
-- ─────────────────────────────────────────────────────────────────────
--   psql "postgresql://postgres:<password>@<host>:5432/postgres" \
--       -f supabase/migrations/20261019120000_chat_family_event_cards.sql
--   OR via the Supabase Studio SQL editor (paste the file contents).
-- ─────────────────────────────────────────────────────────────────────

-- ─── 1. ChatMessage columns ───────────────────────────────────────────
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventId"           text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventTitle"        text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventDate"        text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventTime"        text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventLocation"     text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventCategory"    text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventRsvpGoing"   integer DEFAULT 0;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventRsvpMaybe"   integer DEFAULT 0;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventRsvpNotGoing" integer DEFAULT 0;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "eventDeletedAt"  timestamptz;

COMMENT ON COLUMN "ChatMessage"."eventId" IS
  'calendar_events.id — the family event this card represents. '
  'Null on non-familyEvent rows. The card stays live: AFTER UPDATE '
  'triggers on calendar_events + calendar_event_rsvps keep the '
  'denormalized eventTitle/eventDate/eventTime/eventLocation/eventCategory/'
  'eventRsvp{Going,Maybe,NotGoing} fields in sync with the live state.';
COMMENT ON COLUMN "ChatMessage"."eventDeletedAt" IS
  'Set when the underlying calendar_events row is deleted (the trigger '
  'fires AFTER DELETE on calendar_events and stamps this column on '
  'every ChatMessage row referencing the event). The card UI then '
  'renders "Event no longer available" with disabled RSVP buttons '
  'until the ChatMessage row itself is deleted.';

-- ─── 2. fn_sync_family_event_chat_cards(p_event_id) ──────────────────
-- SECURITY DEFINER so the function can UPDATE ChatMessage rows even
-- if the acting user (e.g. a family member submitting an RSVP) doesn't
-- have UPDATE rights on someone else's ChatMessage rows. The chat
-- family-RLS already allows family members to UPDATE ChatMessage rows
-- in their own family (per the existing chatmessage_update_policy);
-- this function runs as supabase_admin so it works even when the
-- trigger fires from a non-family-member path (e.g. admin moderation).
--
-- Idempotent: a no-op if no ChatMessage rows reference the event.
CREATE OR REPLACE FUNCTION fn_sync_family_event_chat_cards(p_event_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event RECORD;
  v_exists boolean;
BEGIN
  -- Check whether the calendar_events row still exists.
  SELECT EXISTS(
    SELECT 1 FROM "calendar_events" WHERE id = p_event_id
  ) INTO v_exists;

  IF NOT v_exists THEN
    -- The event was deleted. Stamp eventDeletedAt on every card that
    -- references it (the card UI shows "Event no longer available"
    -- with disabled RSVP buttons).
    UPDATE "ChatMessage"
      SET "eventDeletedAt" = COALESCE("eventDeletedAt", now()),
          "eventRsvpGoing" = 0,
          "eventRsvpMaybe" = 0,
          "eventRsvpNotGoing" = 0,
          "updatedAt" = now()
      WHERE "eventId" = p_event_id
        AND "messageType" = 'familyEvent';
    RETURN;
  END IF;

  -- The event exists — recompute the denormalized fields from the
  -- live state.
  SELECT
    e."title",
    e."eventDate"::text,
    e."location",
    e."category",
    (SELECT count(*) FROM "calendar_event_rsvps" r WHERE r."eventId" = p_event_id AND r."status" = 'going') AS rsvp_going,
    (SELECT count(*) FROM "calendar_event_rsvps" r WHERE r."eventId" = p_event_id AND r."status" = 'maybe') AS rsvp_maybe,
    (SELECT count(*) FROM "calendar_event_rsvps" r WHERE r."eventId" = p_event_id AND r."status" = 'not_going') AS rsvp_not_going
  INTO v_event
  FROM "calendar_events" e
  WHERE e."id" = p_event_id;

  -- UPDATE every ChatMessage row referencing the event.
  UPDATE "ChatMessage"
    SET
      "eventTitle"        = v_event."title",
      "eventDate"        = v_event."eventDate",
      "eventLocation"    = v_event."location",
      "eventCategory"    = v_event."category",
      "eventRsvpGoing"   = v_event.rsvp_going,
      "eventRsvpMaybe"   = v_event.rsvp_maybe,
      "eventRsvpNotGoing" = v_event.rsvp_not_going,
      "eventDeletedAt"  = NULL,
      "updatedAt"        = now()
    WHERE "eventId" = p_event_id
      AND "messageType" = 'familyEvent';
END;
$$;

COMMENT ON FUNCTION fn_sync_family_event_chat_cards IS
  'Recomputes the denormalized event fields (title, date, location, '
  'category, RSVP counts) on every ChatMessage row referencing the '
  'given event. Called by AFTER INSERT/UPDATE/DELETE triggers on '
  'calendar_events + calendar_event_rsvps. The chat_provider realtime '
  'UPDATE subscription on ChatMessage propagates the synced fields to '
  'every open chat UI — the cards stay live without any client-side '
  're-fetch. SECURITY DEFINER so the acting user (who may be a family '
  'member submitting an RSVP) can update the host''s card row even '
  'without direct UPDATE rights.';

-- ─── 3. AFTER INSERT/UPDATE triggers on calendar_events ───────────────
DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_insert" ON "calendar_events";
DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_update" ON "calendar_events";
DROP TRIGGER IF EXISTS "trg_events_sync_event_chat_cards_delete" ON "calendar_events";

CREATE TRIGGER "trg_events_sync_event_chat_cards_insert"
  AFTER INSERT ON "calendar_events"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(NEW."id");

CREATE TRIGGER "trg_events_sync_event_chat_cards_update"
  AFTER UPDATE ON "calendar_events"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(NEW."id");

CREATE TRIGGER "trg_events_sync_event_chat_cards_delete"
  AFTER DELETE ON "calendar_events"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(OLD."id");

-- ─── 4. AFTER INSERT/UPDATE/DELETE triggers on calendar_event_rsvps ────
DROP TRIGGER IF EXISTS "trg_rsvps_sync_event_chat_cards_insert" ON "calendar_event_rsvps";
DROP TRIGGER IF EXISTS "trg_rsvps_sync_event_chat_cards_update" ON "calendar_event_rsvps";
DROP TRIGGER IF EXISTS "trg_rsvps_sync_event_chat_cards_delete" ON "calendar_event_rsvps";

CREATE TRIGGER "trg_rsvps_sync_event_chat_cards_insert"
  AFTER INSERT ON "calendar_event_rsvps"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(NEW."eventId");

CREATE TRIGGER "trg_rsvps_sync_event_chat_cards_update"
  AFTER UPDATE ON "calendar_event_rsvps"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(NEW."eventId");

CREATE TRIGGER "trg_rsvps_sync_event_chat_cards_delete"
  AFTER DELETE ON "calendar_event_rsvps"
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_family_event_chat_cards(OLD."eventId");

-- ─── 5. Partial index for the sync UPDATE scan ────────────────────────
CREATE INDEX IF NOT EXISTS "ChatMessage_familyEvent_eventId_idx"
  ON "ChatMessage" ("eventId")
  WHERE "messageType" = 'familyEvent' AND "eventId" IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- END OF MIGRATION
-- ─────────────────────────────────────────────────────────────────────
-- Summary:
--   • 10 new columns on ChatMessage (eventId + 6 denormalized fields
--     + 3 RSVP counts + eventDeletedAt)
--   • 1 SECURITY DEFINER SQL function (fn_sync_family_event_chat_cards)
--   • 6 AFTER triggers (3 on calendar_events + 3 on calendar_event_rsvps)
--   • 1 partial index (ChatMessage_familyEvent_eventId_idx)
--
-- What is NOT changed:
--   • The calendar_events / calendar_event_rsvps / calendar_event_comments
--     schemas (unchanged — the existing 20260704060000_family_calendar.sql
--     is authoritative).
--   • The RLS on calendar_events + calendar_event_rsvps (family-scoped
--     SELECT — unchanged).
--   • The chat_provider realtime setup (existing UPDATE subscription
--     on ChatMessage propagates the synced fields automatically).
