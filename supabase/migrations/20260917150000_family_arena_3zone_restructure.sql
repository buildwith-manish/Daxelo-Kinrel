-- =============================================================================
-- 20260917150000_family_arena_3zone_restructure.sql
--
-- Family Arena 3-zone restructure — backend support for:
--   • Zone 2 "Play With" row: get_play_with_suggestions RPC
--   • Zone 3 "Family Moments" feed: family_moment_reactions table + RLS +
--     reaction counts surfaced via fn_get_family_gaming_activity_v2
--
-- DESIGN NOTES
--   • get_play_with_suggestions is SECURITY DEFINER so it can read
--     game_match_players (which has tight RLS post-privacy-migration) and
--     surface co-play aggregates without leaking per-match results. The
--     function returns ONLY: userId, userName, avatarUrl, isOnline,
--     sharedGamesCount, lastSharedGameId, lastSharedGameName,
--     lastSharedGameIcon, lastPlayedTogetherAt. It NEVER returns win/loss
--     data — participation count only (consistent with the privacy contract).
--   • family_moment_reactions is RLS-gated to family members. The unique
--     constraint on (moment_id, user_id, reaction_type) prevents spam.
--   • fn_get_family_gaming_activity_v2 mirrors v1 but additionally returns
--     reactionCounts (per-type counts) and myReactions (the requesting
--     user's own reaction types for this moment). v1 is kept for backward
--     compatibility.
-- =============================================================================

-- =============================================================================
-- SECTION 1: get_play_with_suggestions(requesting_user_id, family_id)
-- =============================================================================
-- Returns one row per family member (other than the requester) with:
--   • sharedGamesCount  — # of matches the requester + this member both played
--   • lastSharedGameId  — game table of the most recent shared match
--   • lastSharedGameName / Icon — display strings from fn__game_meta()
--   • lastPlayedTogetherAt — timestamptz of most recent shared match
--   • isOnline          — whether the member is currently online (presence)
--   • avatarUrl, userName — display fields
--
-- Ordering is enforced by the caller (Flutter) so the SQL keeps it simple:
--   ORDER BY isOnline DESC, sharedGamesCount DESC, userName ASC
--
-- Privacy: never returns wins/losses/winRate. The sharedGamesCount is a
-- participation metric (both played), not an outcome.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_play_with_suggestions(
  p_requesting_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
  v_meta jsonb := public.fn__game_meta();
BEGIN
  -- Defensive: requester must be a family member.
  IF NOT public.fn_user_is_family_member(p_family_id) THEN
    RETURN jsonb_build_object('suggestions', '[]'::jsonb);
  END IF;

  -- For every other family member, aggregate their co-played matches with
  -- the requester. We join game_match_players to itself on matchId to find
  -- matches both participated in. The result NEVER includes the match
  -- result column (privacy contract — only participation info).
  --
  -- We use a two-step LATERAL: first an aggregate to get count + max
  -- finishedAt, then a separate LATERAL to fetch the gameTable of that
  -- specific most-recent match (avoids "aggregate functions are not
  -- allowed in FILTER" — can't nest MAX() inside a FILTER clause).
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY
              t.is_online DESC,
              t.shared_games_count DESC,
              t.user_name ASC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      fm."userId"                   AS user_id,
      COALESCE(u."name", fm."userId") AS user_name,
      u."avatarUrl"                 AS avatar_url,
      COALESCE(po."isOnline", false) AS is_online,
      COALESCE(cp.shared_count, 0)  AS shared_games_count,
      lg."gameTable"                AS last_shared_game_id,
      CASE WHEN lg."gameTable" IS NOT NULL
           THEN v_meta -> lg."gameTable" ->> 'name'
           ELSE NULL END             AS last_shared_game_name,
      CASE WHEN lg."gameTable" IS NOT NULL
           THEN v_meta -> lg."gameTable" ->> 'icon'
           ELSE NULL END             AS last_shared_game_icon,
      cp.last_played_at             AS last_played_together_at
    FROM "FamilyMember" fm
    LEFT JOIN "User" u ON u."id" = fm."userId"
    LEFT JOIN LATERAL (
      SELECT
        COUNT(*)                    AS shared_count,
        MAX(mine."finishedAt")      AS last_played_at
      FROM "game_match_players" mine
      INNER JOIN "game_match_players" other
        ON other."matchId" = mine."matchId"
       AND other."userId"  = fm."userId"
      WHERE mine."userId"  = p_requesting_user_id
        AND mine."familyId" = p_family_id
        AND other."userId" <> p_requesting_user_id
    ) cp ON true
    LEFT JOIN LATERAL (
      -- Fetch the game table of the most-recent shared match.
      SELECT mine."gameTable"
      FROM "game_match_players" mine
      INNER JOIN "game_match_players" other
        ON other."matchId" = mine."matchId"
       AND other."userId"  = fm."userId"
      WHERE mine."userId"  = p_requesting_user_id
        AND mine."familyId" = p_family_id
        AND other."userId" <> p_requesting_user_id
      ORDER BY mine."finishedAt" DESC
      LIMIT 1
    ) lg ON true
    LEFT JOIN LATERAL (
      SELECT true AS "isOnline"
      FROM "MemberPresence"
      WHERE "userId" = fm."userId"
        AND "familyId" = p_family_id
        AND "status" IS NOT NULL
        AND "status" <> 'away'
        AND "lastSeenAt" > now() - interval '90 seconds'
      LIMIT 1
    ) po ON true
    WHERE fm."familyId" = p_family_id
      AND fm."userId"   <> p_requesting_user_id
  ) t;

  RETURN jsonb_build_object('suggestions', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_play_with_suggestions(text, text) TO authenticated;

-- =============================================================================
-- SECTION 2: family_moment_reactions table + RLS
-- =============================================================================
-- One row per (moment, user, reaction_type). The unique constraint means
-- a user can leave at most ONE of each reaction type per moment — they can
-- ❤️ AND 👏 the same moment, but not ❤️ it twice.
--
-- reaction_type is a small enum-ish text — currently 'heart' | 'clap'.
-- Kept as text (not a Postgres enum) so the frontend can add new types
-- without a migration.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "family_moment_reactions" (
  "id"            text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "momentId"      text NOT NULL,
  "familyId"      text NOT NULL,
  "userId"        text NOT NULL,
  "reactionType"  text NOT NULL,
  "createdAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fmr_moment_user_type
  ON "family_moment_reactions" ("momentId", "userId", "reactionType");

CREATE INDEX IF NOT EXISTS idx_fmr_moment
  ON "family_moment_reactions" ("momentId");
CREATE INDEX IF NOT EXISTS idx_fmr_family_user
  ON "family_moment_reactions" ("familyId", "userId");

ALTER TABLE "family_moment_reactions" ENABLE ROW LEVEL SECURITY;

-- SELECT: only family members can read reactions on their family's moments.
DROP POLICY IF EXISTS family_moment_reactions_select_family ON "family_moment_reactions";
CREATE POLICY family_moment_reactions_select_family ON "family_moment_reactions"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

-- INSERT: only a family member can react, and only on their own behalf.
DROP POLICY IF EXISTS family_moment_reactions_insert_self ON "family_moment_reactions";
CREATE POLICY family_moment_reactions_insert_self ON "family_moment_reactions"
  FOR INSERT TO authenticated
  WITH CHECK (
    "userId" = auth.uid()::text
    AND public.fn_user_is_family_member("familyId")
  );

-- DELETE: only the original reactor can un-react.
DROP POLICY IF EXISTS family_moment_reactions_delete_self ON "family_moment_reactions";
CREATE POLICY family_moment_reactions_delete_self ON "family_moment_reactions"
  FOR DELETE TO authenticated
  USING ("userId" = auth.uid()::text);

-- =============================================================================
-- SECTION 3: fn_toggle_moment_reaction(p_moment_id, p_family_id, p_reaction_type)
-- =============================================================================
-- Idempotent toggle: if the (moment, user, reaction_type) row exists, delete
-- it (un-react); otherwise insert it (react). Returns the new aggregate
-- reaction counts for the moment so the caller can update UI optimistically
-- and confirm with the server response.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_toggle_moment_reaction(
  p_moment_id text,
  p_family_id text,
  p_reaction_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requester text := auth.uid()::text;
  v_existing text;
BEGIN
  IF v_requester IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  IF NOT public.fn_user_is_family_member(p_family_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_family_member');
  END IF;

  SELECT id INTO v_existing
  FROM "family_moment_reactions"
  WHERE "momentId" = p_moment_id
    AND "userId"   = v_requester
    AND "reactionType" = p_reaction_type
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    DELETE FROM "family_moment_reactions" WHERE id = v_existing;
  ELSE
    INSERT INTO "family_moment_reactions"
      ("momentId", "familyId", "userId", "reactionType")
    VALUES
      (p_moment_id, p_family_id, v_requester, p_reaction_type);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'momentId', p_moment_id,
    'reactionType', p_reaction_type,
    'active', v_existing IS NULL,  -- true if we just reacted, false if un-reacted
    'reactionCounts', COALESCE((
      SELECT jsonb_object_agg("reactionType", cnt)
      FROM (
        SELECT "reactionType", COUNT(*)::int AS cnt
        FROM "family_moment_reactions"
        WHERE "momentId" = p_moment_id
        GROUP BY "reactionType"
      ) t
    ), '{}'::jsonb),
    'myReactions', COALESCE((
      SELECT jsonb_agg("reactionType")
      FROM "family_moment_reactions"
      WHERE "momentId" = p_moment_id
        AND "userId" = v_requester
    ), '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_toggle_moment_reaction(text, text, text) TO authenticated;

-- =============================================================================
-- SECTION 4: fn_get_family_gaming_activity_v2 — adds reaction counts
-- =============================================================================
-- Mirrors fn_get_family_gaming_activity but each entry includes:
--   • reactionCounts: { "heart": 2, "clap": 1 }  — total per type
--   • myReactions:    ["heart"]                   — types the viewer left
--
-- Privacy note: entries about match results continue to flow from
-- FamilyActivityLog (which is family-readable). The reframe task adds the
-- "X and Y played together" phrasing in the FRONTEND for non-participants;
-- the backend just continues to log the event. The frontend is responsible
-- for swapping result-revealing copy for non-participants (it already has
-- the participant list via metadata.participants when present).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_gaming_activity_v2(
  p_family_id text,
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requester text := auth.uid()::text;
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', a."id",
      'actorUserId', a."actorUserId",
      'actorName', a."actorName",
      'action', a."action",
      'description', a."description",
      'metadata', a."metadata",
      'createdAt', a."createdAt",
      'reactionCounts', COALESCE((
        SELECT jsonb_object_agg("reactionType", cnt)
        FROM (
          SELECT "reactionType", COUNT(*)::int AS cnt
          FROM "family_moment_reactions"
          WHERE "momentId" = a."id"
          GROUP BY "reactionType"
        ) t
      ), '{}'::jsonb),
      'myReactions', COALESCE((
        SELECT jsonb_agg("reactionType")
        FROM "family_moment_reactions"
        WHERE "momentId" = a."id"
          AND "userId" = v_requester
      ), '[]'::jsonb))
    ORDER BY a."createdAt" DESC)
    FROM (
      SELECT * FROM "FamilyActivityLog"
      WHERE "familyId" = p_family_id AND "action" LIKE 'game_%'
      ORDER BY "createdAt" DESC
      OFFSET GREATEST(p_offset,0)
      LIMIT LEAST(GREATEST(p_limit,1),100)
    ) a
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_gaming_activity_v2(text, int, int) TO authenticated;

-- =============================================================================
-- SECTION 5: Comment markers
-- =============================================================================
COMMENT ON TABLE public."family_moment_reactions" IS
  'Per-moment ❤️ / 👏 reactions from family members. Unique on (momentId, userId, reactionType) so a user can leave at most one of each type per moment. RLS-gated to family members.';
COMMENT ON FUNCTION public.get_play_with_suggestions(text, text) IS
  'People-first Play With row for the Family Arena home screen. Returns one entry per family member (other than the requester) with shared-games count, last shared game, online status. Never returns win/loss data — participation only.';
COMMENT ON FUNCTION public.fn_toggle_moment_reaction(text, text, text) IS
  'Idempotent toggle for a single (moment, user, reactionType). Returns the new aggregate counts plus the viewer''s own active reactions.';
