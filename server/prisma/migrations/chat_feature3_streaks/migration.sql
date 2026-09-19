-- Feature 3: Chat Streaks
--
-- Creates the ChatStreak table. A streak tracks consecutive-day messaging
-- in a family chat: increments when a message is sent within 24 hours of
-- the previous one, resets to 1 if the gap exceeds 24 hours.
--
-- Displayed in the Flutter chat header with a flame icon to drive daily
-- engagement ("You've been chatting with your family for 5 days straight!").
--
-- NOTE: This table does NOT exist in Supabase yet — it is created here.
-- Idempotent: uses CREATE TABLE IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS "ChatStreak" (
  "id" text NOT NULL,
  "chatId" text NOT NULL,            -- familyId for family group chats
  "currentStreak" integer NOT NULL DEFAULT 1,
  "longestStreak" integer NOT NULL DEFAULT 1,
  "lastMessageAt" timestamptz NOT NULL DEFAULT now(),
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "ChatStreak_pkey" PRIMARY KEY (id),
  CONSTRAINT "ChatStreak_chatId_key" UNIQUE ("chatId")
);

CREATE INDEX IF NOT EXISTS "ChatStreak_currentStreak_idx"
  ON "ChatStreak" ("currentStreak");

COMMENT ON TABLE "ChatStreak" IS
  'Feature 3: Consecutive-day messaging streaks per family chat. Increments if last message was within 24 hours, resets to 1 otherwise.';
COMMENT ON COLUMN "ChatStreak"."chatId" IS
  'familyId for family group chats. UNIQUE so one streak row per chat.';
COMMENT ON COLUMN "ChatStreak"."currentStreak" IS
  'Current consecutive-day count. 1 = first message today, 5 = 5 days straight.';
COMMENT ON COLUMN "ChatStreak"."longestStreak" IS
  'Highest streak ever achieved in this chat (for milestone celebration).';
COMMENT ON COLUMN "ChatStreak"."lastMessageAt" IS
  'Timestamp of the last message that updated this streak. Used to decide increment vs reset.';
