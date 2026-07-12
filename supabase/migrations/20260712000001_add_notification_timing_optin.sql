-- ============================================================
-- Migration: add_notification_timing_optin
-- Version:  20260712000001
-- Feature:  P1.3 — Make ML-driven notification timing opt-in (default OFF)
--
-- Adds the notificationTimingOptIn column to the "User" table.
-- Default FALSE — no behavioral data collection without explicit consent.
--
-- This is a pure additive migration (new nullable-with-default column).
-- It does NOT backfill or modify existing rows beyond setting the default.
-- Existing users get notificationTimingOptIn = false, which means the
-- ML-driven engagement histogram service immediately stops collecting
-- samples for them until they explicitly opt in.
-- ============================================================

-- Step 1: Add the column with DEFAULT false.
-- Using ADD COLUMN ... DEFAULT ... is safe on Postgres 11+ (no table rewrite).
ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "notificationTimingOptIn" BOOLEAN NOT NULL DEFAULT false;

-- Step 2: Verify (run manually to confirm).
-- SELECT count(*) FILTER (WHERE "notificationTimingOptIn" = true) AS opted_in,
--        count(*) FILTER (WHERE "notificationTimingOptIn" = false) AS opted_out,
--        count(*) AS total
-- FROM "User";
