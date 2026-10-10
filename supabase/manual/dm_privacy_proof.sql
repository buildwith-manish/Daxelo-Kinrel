-- =============================================================================
-- Daxelo Kinrel — DM Rebuild PRIVACY PROOF (manual, never run automatically)
-- =============================================================================
-- Run these queries YOURSELF with the Supabase SQL editor or psql while
-- signed in as the three users described below, to prove that a third
-- family member CANNOT see a private 2-person direct-group chat.
--
-- Setup:
--   • User A and User B: two members of the same family (e.g. its id is
--     <family_id>).
--   • User C: a third member of the SAME family (the "attacker").
--
-- The RLS policies under test live in
--   supabase/migrations/20261101120000_dm_rebuild_direct_groups.sql
-- (ChatMessage / GroupMember / Group / ChatMessageReaction /
--  ChatReadReceipt — groupType='direct' groups are GroupMember-only).
--
-- NOTE: run each block with `SET LOCAL role authenticated;` semantics —
-- i.e. via the app or the SQL editor signed in as that user, so
-- auth.uid() resolves. Direct psql access as postgres bypasses RLS and
-- proves nothing.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1 (as USER A): open the direct chat with B — this creates the
-- direct group. In the app this is the RPC the "message" button calls;
-- here we call it directly.
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT * FROM fn_get_or_create_direct_group('<user_b_id>', '<family_id>');
-- Expect: { "success": true, "action": "created", "groupId": "grp_direct_…",
--           "familyId": "<family_id>", "directKey": "<a>_<b>", … }
-- Note the returned groupId — call it <direct_group_id> below.


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2 (as USER A): send a message into the direct group.
-- ═══════════════════════════════════════════════════════════════════════════
-- INSERT INTO "ChatMessage" (
--   "id", "familyId", "groupId", "senderId", "senderName",
--   "content", "messageType", "messageStatus", "createdAt", "updatedAt"
-- ) VALUES (
--   'cm_proof_' || extract(epoch from now())::bigint::text,
--   '<family_id>', '<direct_group_id>', '<user_a_id>', 'User A',
--   'private hello from A', 'text', 'sent', now(), now()
-- );
-- Expect: INSERT 0 1 (the WITH CHECK passes: A is a GroupMember).


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3 (as USER A or B — a direct-group member): SEE the chat.
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT id, "groupId", content FROM "ChatMessage"
-- WHERE "groupId" = '<direct_group_id>';
-- Expect: 1 row — the private message.

-- SELECT "groupId", "userId", "displayName" FROM "GroupMember"
-- WHERE "groupId" = '<direct_group_id>';
-- Expect: exactly 2 rows (A and B).


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4 (as USER C — the third family member): TRY to see the chat.
-- This is the core privacy proof — every query must return 0 rows.
-- ═══════════════════════════════════════════════════════════════════════════
-- 4a. Read the messages:
-- SELECT id, content FROM "ChatMessage"
-- WHERE "groupId" = '<direct_group_id>';
-- Expect: 0 rows (RLS: direct group → GroupMember-only, C is not one).

-- 4b. Sneak via the family-wide query the app uses for the family chat:
-- SELECT id, "groupId", content FROM "ChatMessage"
-- WHERE "familyId" = '<family_id>' AND "groupId" IS NOT NULL;
-- Expect: 0 rows for <direct_group_id> (and any other group C is not in).

-- 4c. See WHO is in the direct group:
-- SELECT "userId" FROM "GroupMember" WHERE "groupId" = '<direct_group_id>';
-- Expect: 0 rows.

-- 4d. See the direct Group row itself:
-- SELECT id, name, "groupType", "directKey" FROM "Group"
-- WHERE id = '<direct_group_id>';
-- Expect: 0 rows (direct groups are member-only even at the Group level).

-- 4e. Try to WRITE into the private chat:
-- INSERT INTO "ChatMessage" (
--   "id", "familyId", "groupId", "senderId", "senderName",
--   "content", "messageType", "messageStatus", "createdAt", "updatedAt"
-- ) VALUES (
--   'cm_evil_' || extract(epoch from now())::bigint::text,
--   '<family_id>', '<direct_group_id>', '<user_c_id>', 'User C',
--   'injected message', 'text', 'sent', now(), now()
-- );
-- Expect: ERROR 42501 (new row violates row-level security policy for
-- table "ChatMessage").

-- 4f. Try to react to a message they cannot even see:
-- INSERT INTO "ChatMessageReaction" ("id", "messageId", "userId", "emoji", "createdAt")
-- VALUES ('cmr_evil_1', 'cm_proof_…', '<user_c_id>', '❤️', now());
-- Expect: ERROR 42501.

-- 4g. Try to create a SECOND direct group for the same pair (impersonate
-- the channel rather than read it):
-- SELECT * FROM fn_get_or_create_direct_group('<user_b_id>', '<family_id>');
-- Expect: {"success": true, "action": "existing", …} — the SAME groupId
-- (the unique directKey index guarantees one group per pair), and C is
-- still not a member of it.


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 5 (as USER B): confirm B sees everything A sees (full parity).
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT id, content FROM "ChatMessage" WHERE "groupId" = '<direct_group_id>';
-- Expect: 1 row. B can also insert messages and mark them read
-- (ChatReadReceipt INSERT allowed for GroupMembers only).


-- ═══════════════════════════════════════════════════════════════════════════
-- PASS CRITERIA
--   • Steps 1, 2, 3, 5 succeed for A and B.
--   • EVERY query in Step 4 returns 0 rows or a policy violation error.
--   • The family-wide chat (groupId IS NULL) is still fully readable by
--     A, B AND C (unchanged behavior):
--       SELECT count(*) FROM "ChatMessage"
--       WHERE "familyId" = '<family_id>' AND "groupId" IS NULL;
--     Expect: same count as before the migration for all three users.
-- =============================================================================
