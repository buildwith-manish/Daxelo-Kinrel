-- Family Calendar — comprehensive event management system
-- Creates calendar_events table for family-scoped events

CREATE TABLE IF NOT EXISTS "calendar_events" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "createdBy"     TEXT NOT NULL,
    "personId"      TEXT,          -- linked Person (for birthdays/anniversaries)
    "title"         TEXT NOT NULL,
    "description"   TEXT,
    "category"      TEXT NOT NULL DEFAULT 'custom', -- birthday|anniversary|wedding|engagement|baby_shower|pregnancy|graduation|school|reunion|vacation|festival|medical|memorial|custom
    "eventDate"     DATE NOT NULL,
    "endDate"       DATE,          -- for multi-day events (vacations, reunions)
    "location"      TEXT,
    "locationUrl"   TEXT,
    "isAllDay"      BOOLEAN NOT NULL DEFAULT true,
    "isRecurring"   BOOLEAN NOT NULL DEFAULT false,
    "recurrenceRule" TEXT,         -- daily|weekly|monthly|yearly|custom
    "recurrenceEndDate" DATE,
    "notes"         TEXT,
    "attachments"   JSONB DEFAULT '[]'::jsonb,  -- array of {type, url, name}
    "metadata"      JSONB DEFAULT '{}'::jsonb,  -- extra fields: giftIdeas, budget, etc.
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cal_events_family
    ON "calendar_events"("familyId");
CREATE INDEX IF NOT EXISTS idx_cal_events_date
    ON "calendar_events"("eventDate");
CREATE INDEX IF NOT EXISTS idx_cal_events_family_date
    ON "calendar_events"("familyId", "eventDate");
CREATE INDEX IF NOT EXISTS idx_cal_events_category
    ON "calendar_events"("category");

-- ─────────────────────────────────────────────────────────────────
-- RSVPs for events
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "calendar_event_rsvps" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "eventId"       TEXT NOT NULL REFERENCES "calendar_events"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "status"        TEXT NOT NULL DEFAULT 'pending', -- going|maybe|not_going|pending
    "respondedAt"   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("eventId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_cal_rsvps_event
    ON "calendar_event_rsvps"("eventId");

-- ─────────────────────────────────────────────────────────────────
-- Event comments
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "calendar_event_comments" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "eventId"       TEXT NOT NULL REFERENCES "calendar_events"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "comment"       TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cal_comments_event
    ON "calendar_event_comments"("eventId", "createdAt");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as truth_streak / ghost_painter)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "calendar_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "calendar_event_rsvps" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "calendar_event_comments" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cal_events_select" ON "calendar_events"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "calendar_events"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "cal_events_insert" ON "calendar_events"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "calendar_events"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "cal_events_update" ON "calendar_events"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "calendar_events"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "cal_events_delete" ON "calendar_events"
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "calendar_events"."familyId" AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "cal_rsvps_select" ON "calendar_event_rsvps"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "calendar_events" e JOIN "FamilyMember" fm ON fm."familyId" = e."familyId" WHERE e.id = "calendar_event_rsvps"."eventId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "cal_rsvps_insert" ON "calendar_event_rsvps"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "cal_rsvps_update" ON "calendar_event_rsvps"
    FOR UPDATE USING ("userId" = auth.uid()::text);

CREATE POLICY "cal_comments_select" ON "calendar_event_comments"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "calendar_events" e JOIN "FamilyMember" fm ON fm."familyId" = e."familyId" WHERE e.id = "calendar_event_comments"."eventId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "cal_comments_insert" ON "calendar_event_comments"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

-- Realtime for live RSVPs and comments
ALTER PUBLICATION supabase_realtime ADD TABLE "calendar_event_rsvps";
ALTER PUBLICATION supabase_realtime ADD TABLE "calendar_event_comments";
