-- ============================================================
-- Rollback: add_bridge_role_optin
-- Version:  20260712000002
-- Feature:  P1.4
-- ============================================================

ALTER TABLE "Family" DROP COLUMN IF EXISTS "bridgeRoleOptIn";
