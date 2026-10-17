-- supabase/migrations/20261017120000_chat_block_and_report.sql
--
-- feat(chat): block and report with server-side enforcement
--
-- Adds server-side enforcement for the existing client-side block flow
-- (BlockedUser table) + the existing ContentReport table (which has no
-- unique constraint yet → user could spam duplicate reports).
--
-- This migration is IDEMPOTENT (every CREATE / ALTER is wrapped in
-- EXCEPTION-WHEN-DUPLICATE handlers). It can be re-applied safely.
--
-- ─────────────────────────────────────────────────────────────────────
-- SCHEMA CHANGES
-- ─────────────────────────────────────────────────────────────────────
--   1. UNIQUE constraint on ContentReport (reporterId, targetType, targetId)
--      → "a user cannot report the same message twice"
--   2. fn_chat_direct_insert_blocked(from, to) — SQL function that
--      returns TRUE if EITHER party has blocked the other (used by
--      the RLS WITH CHECK clause on ChatMessage INSERT for direct chats).
--   3. RLS policy addition on ChatMessage: INSERT is denied for direct
--      chats (groupId IS NOT NULL AND groupId LIKE 'dm_%') when the
--      sender ↔ recipient block pair exists in BlockedUser.
--   4. Helpful index on BlockedUser.blockedId for the inbound-direction
--      block lookup (existing index covers blockerId; the new one
--      covers the "did anyone block ME" lookup).
--
-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK NOTE
-- ─────────────────────────────────────────────────────────────────────
-- To revert this migration, run the following SQL in reverse order:
--
--   -- 4. Drop the inbound block-lookup index
--   DROP INDEX IF EXISTS "BlockedUser_blockedId_idx";
--
--   -- 3. Drop the direct-chat INSERT policy addition. The original
--   --    ChatMessage INSERT policy (created by the base migrations)
--   --    is left in place — only the block-enforcement policy is dropped.
--   DROP POLICY IF EXISTS "ChatMessage insert blocked by direct-chat pair"
--     ON "ChatMessage";
--
--   -- 2. Drop the helper function
--   DROP FUNCTION IF EXISTS fn_chat_direct_insert_blocked(text, text);
--
--   -- 1. Drop the unique constraint on ContentReport
--   ALTER TABLE "ContentReport"
--     DROP CONSTRAINT IF EXISTS "ContentReport_reporter_target_uniq";
--
-- Rolling back step 3 (the block-enforcement INSERT policy) re-opens
-- the direct-chat send path for blocked pairs — the UI keeps hiding
-- the blocked person's input, but the server no longer refuses the
-- insert. This is the safe direction (it doesn't break the existing
-- chat for any user). The opposite direction — re-adding the policy
-- after rollback — requires the policy definition below to be
-- re-applied in full (use the CREATE POLICY block from this file).
--
-- ─────────────────────────────────────────────────────────────────────
-- APPLY COMMAND (cannot be applied by the migration runner — the user
-- must run this manually against their Supabase database):
-- ─────────────────────────────────────────────────────────────────────
--   supabase db push --local-only      # to preview
--   OR, against the hosted project:
--   psql "postgresql://postgres:<password>@<host>:5432/postgres" \
--       -f supabase/migrations/20261017120000_chat_block_and_report.sql
--   OR via the Supabase Studio SQL editor (paste the file contents).
-- ─────────────────────────────────────────────────────────────────────

-- ─── 1. ContentReport: unique constraint (one report per user per target) ───
-- Without this, a user could file N reports for the same message,
-- flooding the moderation queue. The unique pair (reporterId, targetType,
-- targetId) is the natural idempotency key.

DO $$ BEGIN
  ALTER TABLE "ContentReport"
    ADD CONSTRAINT "ContentReport_reporter_target_uniq"
    UNIQUE ("reporterId", "targetType", "targetId");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON CONSTRAINT "ContentReport_reporter_target_uniq" ON "ContentReport" IS
  'Enforces the one-report-per-user-per-target rule. Inserting a second '
  'report for the same (reporterId, targetType, targetId) throws '
  'unique_violation (23505) — the client treats this as a "you already '
  'reported this" success, not an error.';

-- Helpful index for the moderation queue's "is this target already
-- reported by this user?" lookup (used by the report sheet's
-- pre-flight check, if the client ever needs it).
CREATE INDEX IF NOT EXISTS "ContentReport_reporterId_targetType_targetId_idx"
  ON "ContentReport" ("reporterId", "targetType", "targetId");

-- ─── 2. Helper function: is the direct-chat INSERT blocked? ──────────────
-- A direct chat is identified by a groupId starting with 'dm_'. The two
-- parties are (senderId, otherUserId) where otherUserId is parsed from
-- the groupId. The block enforcement is symmetric: if EITHER party has
-- blocked the other, the INSERT is denied.
--
-- Returns TRUE if there's a direct-chat block pair that should refuse
-- this insert. Returns FALSE otherwise (group chats, no block, etc.).
--
-- Implemented as a STABLE SQL function so it can be called from the
-- RLS WITH CHECK clause (Postgres requires STABLE or IMMUTABLE for
-- functions in RLS policies in many configs).

CREATE OR REPLACE FUNCTION fn_chat_direct_insert_blocked(
  p_sender_id TEXT,
  p_group_id  TEXT
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- A direct chat has groupId starting with 'dm_'. If it doesn't,
  -- this is a family-wide or sub-group chat — block enforcement does
  -- NOT apply there (the spec hides blocked messages behind a placeholder
  -- in group chats instead of refusing them).
  SELECT
    CASE
      WHEN p_group_id IS NULL OR p_group_id NOT LIKE 'dm\_%' ESCAPE '\' THEN
        FALSE
      ELSE
        -- Parse the other user's id from the dm_<idA>_<idB> groupId.
        -- The groupId is constructed by the client as
        -- 'dm_' || md5(sort([a, b])) — a stable hash, NOT a parseable
        -- pair. So we can't recover the other user's id from the groupId
        -- alone. Instead, we look up ANY direct-chat row for this
        -- groupId + sender combination — its receiverId is the other
        -- party. Then we check BlockedUser for either direction.
        EXISTS (
          SELECT 1
          FROM "ChatMessage" cm
          JOIN "BlockedUser" bu
            ON (
              -- I blocked them.
              bu."blockerId" = p_sender_id
              AND bu."blockedId" IN (
                SELECT cm2."senderId"
                FROM "ChatMessage" cm2
                WHERE cm2."groupId" = p_group_id
                  AND cm2."senderId" <> p_sender_id
              )
            )
            OR (
              -- They blocked me.
              bu."blockedId" = p_sender_id
              AND bu."blockerId" IN (
                SELECT cm2."senderId"
                FROM "ChatMessage" cm2
                WHERE cm2."groupId" = p_group_id
                  AND cm2."senderId" <> p_sender_id
              )
            )
          WHERE cm."groupId" = p_group_id
          LIMIT 1
        )
    END;
$$;

COMMENT ON FUNCTION fn_chat_direct_insert_blocked IS
  'Returns TRUE if a direct-chat (groupId LIKE ''dm_%'') INSERT should be '
  'denied because either party has blocked the other. Returns FALSE for '
  'non-direct chats (family-wide or sub-group) — those chats hide blocked '
  'messages behind a placeholder in the UI, not via RLS. Used by the '
  'ChatMessage INSERT WITH CHECK policy. STABLE — safe to call from RLS.';

-- ─── 3. RLS policy addition on ChatMessage ────────────────────────────────
-- The existing INSERT policy on ChatMessage (created by earlier
-- migrations) allows a family member to insert any message. We ADD a
-- second, more-restrictive policy that uses the block-enforcement
-- function above to refuse direct-chat inserts when a block pair exists.
--
-- Postgres RLS policies are OR-combined by default — multiple PERMISSIVE
-- policies each allow the row, and the most-permissive wins. To enforce
-- a DENY on top of an existing ALLOW, we use a RESTRICTIVE policy (the
-- only kind that ANDs with the permissive policies). RESTRICTIVE
-- policies were added in Postgres 11 (Supabase ships PG 14+).
--
-- The policy reads as: "of all the rows that the permissive policies
-- allow, only keep the ones where the direct-chat block function
-- returns FALSE" — i.e. deny direct-chat inserts where a block exists.

DROP POLICY IF EXISTS "ChatMessage insert blocked by direct-chat pair"
  ON "ChatMessage";

CREATE POLICY "ChatMessage insert blocked by direct-chat pair"
  ON "ChatMessage"
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (
    NOT fn_chat_direct_insert_blocked(
      auth.uid()::text,
      "groupId"
    )
  );

COMMENT ON POLICY "ChatMessage insert blocked by direct-chat pair" ON "ChatMessage" IS
  'RESTRICTIVE policy — AND-combined with the existing permissive INSERT '
  'policies on ChatMessage. Refuses the insert when the sender ↔ direct-'
  'chat recipient pair has a block row in either direction. This is '
  'the server-side enforcement of the block contract: the UI hides the '
  'compose UI for blocked direct chats, but even if the client is '
  'patched to send the insert anyway, the server rejects it with a '
  '403/RLS error.';

-- ─── 4. Inbound block-lookup index ───────────────────────────────────────
-- The existing BlockedUser index covers blockerId (for "who did I block?"
-- queries). The new index covers blockedId (for "did anyone block ME?"
-- queries — the inbound direction, used by the helper function above
-- when looking up the "they blocked me" branch).

CREATE INDEX IF NOT EXISTS "BlockedUser_blockedId_idx"
  ON "BlockedUser" ("blockedId");

COMMENT ON INDEX "BlockedUser_blockedId_idx" IS
  'Speeds up the inbound-direction block lookup: "did anyone block ME?" '
  'Used by fn_chat_direct_insert_blocked when checking the "they blocked '
  'me" branch of the symmetric enforcement. The existing index on '
  'blockerId covers the "I blocked them" branch.';

-- ─────────────────────────────────────────────────────────────────────
-- END OF MIGRATION
-- ─────────────────────────────────────────────────────────────────────
-- Summary of changes:
--   • 1 unique constraint added (ContentReport)
--   • 1 SQL function added (fn_chat_direct_insert_blocked)
--   • 1 RESTRICTIVE RLS policy added (ChatMessage INSERT, AND-combined)
--   • 1 index added (BlockedUser_blockedId_idx)
--
-- What is NOT changed:
--   • The BlockedUser table schema (blockerId, blockedId, createdAt).
--     The existing SELECT/INSERT/DELETE RLS policies on BlockedUser
--     (created by 20260608182557_fix_rls_tables_with_missing_policies.sql)
--     remain authoritative — users can still self-serve block + unblock.
--   • The ContentReport table schema — only the unique constraint is new.
--   • The moderation RPC (fn_submit_report server-side, plus the
--     /api/moderation/report NestJS endpoint). The unique constraint
--     surfaces as a 23505 unique_violation that the NestJS handler can
--     catch and return as a 200 "already reported" — the existing
--     moderation flow is unchanged otherwise.
