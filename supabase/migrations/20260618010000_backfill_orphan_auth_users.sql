-- ============================================================
-- Migration: backfill_orphan_auth_users
-- Date:      2026-06-18
-- Source:    Super Z audit — orphan auth.users / public."User" linkage
--
-- Two auth.users rows were created WITHOUT a corresponding
-- public."User" row (the on_auth_user_created trigger was either
-- missing or transiently failing at the time):
--
--   c66c3935-4c93-4930-8408-81300a7e9905  manishn32007@gmail.com   (name: Manish)
--   aa7ece5f-47ff-4309-9333-450c5fbf1985  manishnkotian11@gmail.com (name: manishn)
--
-- These users successfully signed in. Backfilling their public."User"
-- rows restores full app functionality (notifications, family membership,
-- feed posts, etc.) and brings the linkage back to 1:1.
--
-- Idempotent: uses ON CONFLICT (id) DO NOTHING so re-running is safe.
-- ============================================================

INSERT INTO public."User" (id, email, name, "preferredLanguage", role, "createdAt", "updatedAt")
VALUES
  (
    'c66c3935-4c93-4930-8408-81300a7e9905',
    'manishn32007@gmail.com',
    'Manish',
    'en',
    'user',
    NOW(),
    NOW()
  ),
  (
    'aa7ece5f-47ff-4309-9333-450c5fbf1985',
    'manishnkotian11@gmail.com',
    'manishn',
    'en',
    'user',
    NOW(),
    NOW()
  )
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Note on the third orphan: demo@kinrel.app (id=cmpkq8dsd00009lpas5vwphgh)
-- ============================================================
-- This row was intentionally KEPT as a seed/demo account. It has a
-- CUID-style ID (not a UUID), so it cannot be linked to auth.users.
-- It cannot log in (no auth.users entry). It exists only to provide
-- demo data in dev/staging environments.
--
-- No action needed. Document here for posterity.
-- ============================================================
