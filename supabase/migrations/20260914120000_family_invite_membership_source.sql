-- =============================================================================
-- Daxelo-Kinrel — Family Invite: load members from the membership source
-- =============================================================================
-- PROBLEM: fn_get_linked_family_members only returned users linked via
-- Person."linkedUserId" INSIDE the given family. But Person."linkedUserId"
-- has a GLOBAL UNIQUE index — a user's Person node exists in exactly ONE
-- family. As a result:
--   • family creators in any family other than their first have an anchor
--     Person with linkedUserId = NULL in those families, and
--   • members who accepted a family invite get a FamilyMember row while
--     their Person node stays in another family (fn_accept_family_invite
--     reuses the existing Person for exactly this reason).
-- For those families the RPC returned 0 rows, so the game invite sheet
-- showed the FALSE empty state "No linked Kinrel members in this family
-- yet" even though real, linked members existed.
--
-- FIX: source the list directly from the family membership source:
--   Branch A (members):  "FamilyMember" JOIN "User"
--                        — every real joined member with a Kinrel account.
--   Branch B (links):    "Person"."linkedUserId" JOIN "User"
--                        — Find-on-Kinrel linked persons (invitable even
--                          before they have a FamilyMember row).
-- Deduped by user id (branch A wins). LEFT JOIN "UserPresence" so each row
-- also carries the member's online status in the same single round trip.
--
-- New columns (additive — existing clients ignore unknown JSON keys):
--   "isMember"  boolean      — true when sourced from FamilyMember
--   "isOnline"  boolean      — UserPresence."isOnline" (null = no row)
--   "lastSeenAt" timestamptz — UserPresence."lastSeenAt"
--
-- Order: joined members first, online first, then name — matches how the
-- invite sheet and the board-game challenge screens present the roster.
-- =============================================================================

-- The return type changes (three new columns), so the existing function
-- must be dropped first (safe on fresh databases too).
DROP FUNCTION IF EXISTS fn_get_linked_family_members(text);

CREATE OR REPLACE FUNCTION fn_get_linked_family_members(
  p_family_id text
)
RETURNS TABLE(
  id text,
  name text,
  username text,
  email text,
  "avatarUrl" text,
  "photoThumb" text,
  bio text,
  gender text,
  "personId" text,
  "linkedAt" timestamptz,
  "isMember" boolean,
  "isOnline" boolean,
  "lastSeenAt" timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH mem AS (
    -- Branch A: real members (the family membership source).
    -- DISTINCT ON guards against duplicate FamilyMember rows for the same
    -- user (earliest joinedAt wins).
    SELECT DISTINCT ON (u.id)
      u.id            AS uid,
      u.name          AS uname,
      u.username,
      u.email,
      u."avatarUrl",
      u."photoThumb",
      u.bio,
      u.gender,
      p.id            AS person_id,
      COALESCE(p."linkedAt", fm."joinedAt") AS linked_at,
      true            AS is_member
    FROM "FamilyMember" fm
    INNER JOIN "User" u ON u.id::text = fm."userId"::text
    LEFT JOIN "Person" p
      ON p."familyId" = p_family_id
     AND p."deletedAt" IS NULL
     AND p."linkedUserId"::text = fm."userId"::text
    WHERE fm."familyId" = p_family_id
      AND u."deletedAt" IS NULL
      -- Only exclude the caller when auth.uid() is NOT NULL (null-safe —
      -- matches the 20260705200000 fix).
      AND (
        auth.uid() IS NULL
        OR u.id::text <> auth.uid()::text
      )
    ORDER BY u.id, fm."joinedAt" ASC
  ),
  lp AS (
    -- Branch B: Person rows in THIS family linked to a real Kinrel account
    -- (added via Find-on-Kinrel) that have no FamilyMember row yet.
    SELECT
      u.id            AS uid,
      u.name          AS uname,
      u.username,
      u.email,
      u."avatarUrl",
      u."photoThumb",
      u.bio,
      u.gender,
      p.id            AS person_id,
      p."linkedAt"    AS linked_at,
      false           AS is_member
    FROM "Person" p
    INNER JOIN "User" u ON u.id::text = p."linkedUserId"::text
    WHERE p."familyId" = p_family_id
      AND p."deletedAt" IS NULL
      AND p."linkedUserId" IS NOT NULL
      AND u."deletedAt" IS NULL
      AND (
        auth.uid() IS NULL
        OR u.id::text <> auth.uid()::text
      )
  ),
  merged AS (
    SELECT * FROM mem
    UNION ALL
    SELECT * FROM lp
    WHERE uid NOT IN (SELECT uid FROM mem)
  )
  SELECT
    m.uid,
    m.uname,
    m.username,
    m.email,
    m."avatarUrl",
    m."photoThumb",
    m.bio,
    m.gender,
    m.person_id,
    m.linked_at,
    m.is_member,
    pres."isOnline",
    pres."lastSeenAt"
  FROM merged m
  LEFT JOIN "UserPresence" pres ON pres."userId"::text = m.uid
  ORDER BY
    m.is_member DESC,
    (pres."isOnline" = true) DESC NULLS LAST,
    m.uname ASC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION fn_get_linked_family_members(text) TO authenticated;

COMMENT ON FUNCTION fn_get_linked_family_members(text) IS
  'Returns every Kinrel account that can be invited inside a family: all '
  'real members (FamilyMember JOIN User — the membership source) plus '
  'Find-on-Kinrel linked Persons, deduped by user id, with live online '
  'status from UserPresence. Caller is excluded (null-safe).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Realtime: keep the invite list live-synced.
--   FamilyMember  — already in supabase_realtime with REPLICA IDENTITY FULL.
--   Person        — new: fires when members are linked/unlinked via
--                   Find-on-Kinrel or removed from the graph.
--   game_invites  — new: fires when invites are sent / accepted / declined,
--                   so the host's invite sheet statuses stay accurate.
-- REPLICA IDENTITY FULL is required so DELETE events carry the filterable
-- columns (familyId / gameId) in the old record.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE "Person" REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'Person'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "Person";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Person realtime setup: %', SQLERRM;
END $$;

ALTER TABLE game_invites REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'game_invites'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE game_invites;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'game_invites realtime setup: %', SQLERRM;
END $$;
