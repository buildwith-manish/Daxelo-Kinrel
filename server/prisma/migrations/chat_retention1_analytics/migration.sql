-- Pack 13.3 Feature 1: Analytics & Instrumentation
--
-- Creates the Event table for chat engagement analytics tracking.
-- The ChatAnalyticsService.track() method writes here fire-and-forget.
--
-- Idempotent: uses CREATE TABLE IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS "Event" (
  "id" text NOT NULL,
  "eventName" text NOT NULL,
  "userId" text NOT NULL,
  "chatId" text,
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "Event_pkey" PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS "Event_eventName_createdAt_idx"
  ON "Event" ("eventName", "createdAt");

CREATE INDEX IF NOT EXISTS "Event_userId_createdAt_idx"
  ON "Event" ("userId", "createdAt");

CREATE INDEX IF NOT EXISTS "Event_chatId_createdAt_idx"
  ON "Event" ("chatId", "createdAt");

COMMENT ON TABLE "Event" IS
  'Pack 13.3: Generic analytics event tracking for chat engagement (message_sent, reaction_added, etc.)';
