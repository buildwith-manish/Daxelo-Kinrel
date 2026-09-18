-- =============================================================================
-- 20260917150000_test_family_moment_reactions_rls.sql
--
-- RLS TEST: A user who is NOT a member of the family the moment belongs to
-- MUST NOT be able to:
--   V1: SELECT rows from family_moment_reactions for that family
--   V2: INSERT a reaction row claiming to be themselves on a moment in
--       that family
--   V3: Toggle a reaction via fn_toggle_moment_reaction (should return
--       ok=false, error='not_family_member')
--
-- A user who IS a family member MUST be able to:
--   V4: SELECT reactions on their family's moments
--   V5: Toggle a reaction via fn_toggle_moment_reaction (ok=true)
--
-- Setup:
--   • Create two test families.
--   • family_moment_reactions rows are scoped to family A.
--   • "outsider" user is a member of family B, NOT family A.
--   • "insider" user is a member of family A.
--
-- This file is idempotent — uses ON CONFLICT DO NOTHING for setup inserts.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Setup: families, members, a moment row in FamilyActivityLog (family A)
-- ---------------------------------------------------------------------------
INSERT INTO "Family" (id, name, "createdBy", "memberCount", "createdAt", "updatedAt")
VALUES
  ('test-rls-fam-A-001', 'RLS Test Family A', NULL, 1, now(), now()),
  ('test-rls-fam-B-002', 'RLS Test Family B', NULL, 1, now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "FamilyMember" (id, "familyId", "userId", "role", "joinedAt")
VALUES
  ('fm-rls-insider-A', 'test-rls-fam-A-001', 'aa7ece5f-47ff-4309-9333-450c5fbf1985', 'member', now()),
  ('fm-rls-outsider-B', 'test-rls-fam-B-002', 'c66c3935-4c93-4930-8408-81300a7e9905', 'member', now())
ON CONFLICT DO NOTHING;

INSERT INTO "FamilyActivityLog" (id, "familyId", "actorUserId", "actorName", "action", "description", "metadata", "createdAt")
VALUES
  ('test-moment-rls-001', 'test-rls-fam-A-001', 'aa7ece5f-47ff-4309-9333-450c5fbf1985', 'Manish', 'game_match_completed',
   'Manish won a game of Chess', '{}'::jsonb, now())
ON CONFLICT (id) DO NOTHING;

-- Pre-insert one reaction from the insider so V1 has something to count.
INSERT INTO "family_moment_reactions" ("momentId", "familyId", "userId", "reactionType", "createdAt")
VALUES ('test-moment-rls-001', 'test-rls-fam-A-001', 'aa7ece5f-47ff-4309-9333-450c5fbf1985', 'heart', now())
ON CONFLICT ("momentId", "userId", "reactionType") DO NOTHING;

-- ---------------------------------------------------------------------------
-- V1: Outsider cannot SELECT reactions on family A's moments.
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  'c66c3935-4c93-4930-8408-81300a7e9905',
  'email','outsider@test.local'
);

SELECT 'V1: outsider cannot see family A reactions' AS test,
       COUNT(*) AS rows_visible
FROM "family_moment_reactions"
WHERE "familyId" = 'test-rls-fam-A-001';
-- Expected: rows_visible = 0 (RLS blocks the outsider)

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V2: Outsider cannot INSERT a reaction on family A's moment.
-- ---------------------------------------------------------------------------
-- Run this as a SEPARATE supabase db query call (not inside a DO block —
-- the DO block's EXCEPTION handler doesn't catch RLS violations cleanly
-- in the supabase db query runner). The expected outcome is the error:
--   "new row violates row-level security policy for table family_moment_reactions"
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  'c66c3935-4c93-4930-8408-81300a7e9905',
  'email','outsider@test.local'
);

INSERT INTO "family_moment_reactions" ("momentId", "familyId", "userId", "reactionType")
VALUES ('test-moment-rls-001', 'test-rls-fam-A-001', 'c66c3935-4c93-4930-8408-81300a7e9905', 'clap');
-- Expected: ERROR 42501 — new row violates row-level security policy

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V3: Outsider cannot toggle a reaction via fn_toggle_moment_reaction.
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  'c66c3935-4c93-4930-8408-81300a7e9905',
  'email','outsider@test.local'
);

SELECT 'V3: outsider toggle rejected' AS test,
       (public.fn_toggle_moment_reaction('test-moment-rls-001', 'test-rls-fam-A-001', 'clap') ->> 'ok')::boolean AS ok,
       public.fn_toggle_moment_reaction('test-moment-rls-001', 'test-rls-fam-A-001', 'clap') ->> 'error' AS error_msg;
-- Expected: ok = false, error_msg = 'not_family_member'

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V4: Insider CAN SELECT reactions on family A's moments.
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  'aa7ece5f-47ff-4309-9333-450c5fbf1985',
  'email','insider@test.local'
);

SELECT 'V4: insider can see family A reactions' AS test,
       COUNT(*) AS rows_visible
FROM "family_moment_reactions"
WHERE "familyId" = 'test-rls-fam-A-001';
-- Expected: rows_visible >= 1

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V5: Insider CAN toggle a reaction via fn_toggle_moment_reaction.
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  'aa7ece5f-47ff-4309-9333-450c5fbf1985',
  'email','insider@test.local'
);

SELECT 'V5a: insider toggle accepted (adds clap)' AS test,
       (public.fn_toggle_moment_reaction('test-moment-rls-001', 'test-rls-fam-A-001', 'clap') ->> 'ok')::boolean AS ok,
       (public.fn_toggle_moment_reaction('test-moment-rls-001', 'test-rls-fam-A-001', 'clap') ->> 'active')::boolean AS active_after_second_toggle;

SELECT 'V5b: reaction counts after insider toggle' AS test,
       public.fn_toggle_moment_reaction('test-moment-rls-001', 'test-rls-fam-A-001', 'heart') -> 'reactionCounts' AS counts;
-- Expected: ok = true, active_after_second_toggle = false (second toggle removes clap)

-- Cleanup the test moment + reactions (leave families/members for reruns).
DELETE FROM "family_moment_reactions" WHERE "momentId" = 'test-moment-rls-001';
DELETE FROM "FamilyActivityLog" WHERE id = 'test-moment-rls-001';

RESET role;
RESET request.jwt.claims;
