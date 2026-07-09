-- ============================================================
-- Migration: add_thinking_of_you
-- Feature: "Thinking of You" — one-tap silent presence signal
-- Safety: 100% additive — no DROPs, no breaking changes
-- ============================================================

CREATE TABLE IF NOT EXISTS "thinking_of_you_taps" (
  "id"          TEXT        NOT NULL DEFAULT gen_random_uuid()::text,
  "senderId"    TEXT        NOT NULL,
  "receiverId"  TEXT        NOT NULL,
  "familyId"    TEXT        NOT NULL,
  "tappedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "thinking_of_you_taps_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "thinking_of_you_taps_senderId_fkey"
    FOREIGN KEY ("senderId")   REFERENCES "User"("id") ON DELETE CASCADE,
  CONSTRAINT "thinking_of_you_taps_receiverId_fkey"
    FOREIGN KEY ("receiverId") REFERENCES "User"("id") ON DELETE CASCADE,
  CONSTRAINT "thinking_of_you_taps_familyId_fkey"
    FOREIGN KEY ("familyId")   REFERENCES "Family"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "idx_toy_receiver_tapped"
  ON "thinking_of_you_taps" ("receiverId", "tappedAt" DESC);

CREATE INDEX IF NOT EXISTS "idx_toy_sender_receiver"
  ON "thinking_of_you_taps" ("senderId", "receiverId");

CREATE INDEX IF NOT EXISTS "idx_toy_family"
  ON "thinking_of_you_taps" ("familyId", "tappedAt" DESC);

ALTER TABLE "thinking_of_you_taps" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "toy_insert_own" ON "thinking_of_you_taps"
  FOR INSERT
  WITH CHECK (auth.uid()::text = "senderId");

CREATE POLICY "toy_select_own" ON "thinking_of_you_taps"
  FOR SELECT
  USING (auth.uid()::text = "senderId" OR auth.uid()::text = "receiverId");

GRANT SELECT, INSERT ON "thinking_of_you_taps" TO authenticated;
