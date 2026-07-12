-- ============================================================
-- Rollback: add_notification_timing_optin
-- Version:  20260712000001
-- Feature:  P1.3
--
-- Drops the notificationTimingOptIn column. Reverting re-introduces the
-- dark pattern (ML runs for all users). Prefer iterating on transparency
-- copy rather than reverting.
-- ============================================================

ALTER TABLE "User" DROP COLUMN IF EXISTS "notificationTimingOptIn";
