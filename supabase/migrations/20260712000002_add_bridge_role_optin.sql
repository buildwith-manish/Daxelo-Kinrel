-- ============================================================
-- Migration: add_bridge_role_optin
-- Version:  20260712000002
-- Feature:  P1.4 — Make bridge role opt-in per family (default OFF)
--
-- Adds the bridgeRoleOptIn column to the "Family" table.
-- Default FALSE — the bridge role (silent alarm notifications) is not
-- active until the family explicitly opts in via family settings.
--
-- When OFF, silent alarms are still generated for admin visibility,
-- but the bridge is NOT notified. When ON, the bridge receives
-- silent alarm notifications per the 7/14/21-day absolute floor.
-- ============================================================

ALTER TABLE "Family"
  ADD COLUMN IF NOT EXISTS "bridgeRoleOptIn" BOOLEAN NOT NULL DEFAULT false;

-- Verify (run manually):
-- SELECT count(*) FILTER (WHERE "bridgeRoleOptIn" = true) AS opted_in,
--        count(*) AS total FROM "Family";
