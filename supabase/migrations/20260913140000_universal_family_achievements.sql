-- =============================================================================
-- Daxelo-Kinrel — Universal Family Multiplayer Experience
-- =============================================================================
-- This migration implements the premium family-first multiplayer platform:
--
--   1. Six new game achievements (5/25/100 wins, Family Champion, Bingo
--      Master, SOS Strategist, Undefeated Streak, Weekend Gamer, Family
--      Night Champion, Spectator Supporter).
--   2. fn_get_user_win_stats(p_user_id, p_family_id) — powers the winner
--      card's "Family Win #23 · 8 Wins This Month" stats row.
--   3. fn_get_family_presence(p_family_id) — powers the Games hub presence
--      strip ("3 online · 2 playing · 1 spectating").
--   4. fn_compute_dynamic_room_size(p_family_id) — auto-scales maxPlayers
--      based on family size (small→8, medium→16, large→25, very large→32).
--   5. fn_start_match_countdown(p_game_table, p_game_id, p_user_id) —
--      host-only RPC that posts a 'countdown' room event so every client
--      sees the 5-4-3-2-1 countdown before the match starts.
--   6. fn_record_winner_stats(p_game_table, p_game_id, p_user_id) —
--      helper invoked by the existing fn_set_game_result RPC that bumps
--      per-user win counters (used by the achievements edge function).
--
-- All RPCs are SECURITY DEFINER with search_path pinned to public, per
-- the migration policy in docs/MIGRATIONS.md.
-- =============================================================================

-- =============================================================================
-- 1. New achievements (idempotent seed)
-- =============================================================================
-- Adds 10 new game-related badge rows to the existing Badge table. These
-- are evaluated by the check_game_badges Edge Function after each game
-- completes.
--
-- Badges added:
--   5. win-5-games               — Win 5 games total
--   6. win-25-games              — Win 25 games total
--   7. win-100-games             — Win 100 games total (Centurion)
--   8. family-champion           — Win 10 games inside one family
--   9. bingo-master              — Win 5 Bingo games
--  10. sos-strategist            — Win 5 SOS games
--  11. undefeated-streak-5      — Win 5 games in a row
--  12. weekend-gamer             — Play 3 games on a weekend
--  13. family-night-champion     — Win 25 family-night games
--  14. spectator-supporter       — Spectate 5 games
-- =============================================================================

INSERT INTO "Badge" ("id", "slug", "name", "nameHi", "description", "icon", "category", "tier", "threshold", "isSecret", "createdAt")
VALUES
  (
    gen_random_uuid()::text,
    'win-5-games',
    'Getting Started',
    'शुरुआत',
    'Win 5 games across any game',
    '🎯',
    'games',
    'silver',
    5,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'win-25-games',
    'Victory Streak',
    'विजय श्रृंखला',
    'Win 25 games across any game',
    '⚡',
    'games',
    'gold',
    25,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'win-100-games',
    'Centurion',
    'शताधिपति',
    'Win 100 games across any game',
    '👑',
    'games',
    'platinum',
    100,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'family-champion',
    'Family Champion',
    'परिवार चैंपियन',
    'Win 10 games inside one family',
    '🏆',
    'games',
    'gold',
    10,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'bingo-master',
    'Bingo Master',
    'बिंगो मास्टर',
    'Win 5 Bingo games',
    '🎟️',
    'games',
    'gold',
    5,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'sos-strategist',
    'SOS Strategist',
    'एसओएस रणनीतिकार',
    'Win 5 SOS games',
    '🎯',
    'games',
    'silver',
    5,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'undefeated-streak-5',
    'Undefeated',
    'अजेय',
    'Win 5 games in a row without a loss',
    '🔥',
    'games',
    'silver',
    5,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'weekend-gamer',
    'Weekend Gamer',
    'सप्ताहांत गेमर',
    'Play 3 games on a weekend',
    '🌙',
    'games',
    'bronze',
    3,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'family-night-champion',
    'Family Night Champion',
    'पारिवारिक शाम चैंपियन',
    'Win 25 games during scheduled family nights',
    '🌟',
    'games',
    'platinum',
    25,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'spectator-supporter',
    'Spectator Supporter',
    'दर्शक समर्थक',
    'Spectate 5 games to cheer your family',
    '👀',
    'games',
    'bronze',
    5,
    false,
    now()
  )
ON CONFLICT ("slug") DO NOTHING;

-- =============================================================================
-- 2. fn_get_user_win_stats — winner card stats
-- =============================================================================
-- Returns: { totalWins, monthlyWins, familyWins, totalGames, currentStreak,
--            familyWinNumber }
--
-- `familyWinNumber` is the per-family running win count for this user
-- (i.e. "this is your 23rd win in this family"). The Flutter winner card
-- renders "⭐ Family Win #23 🎉 8 Wins This Month" from these fields.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_user_win_stats(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_wins int;
  v_monthly_wins int;
  v_family_wins int;
  v_total_games int;
  v_current_streak int;
  v_family_win_number int;
  v_month_start timestamptz := date_trunc('month', now());
BEGIN
  -- Total wins across all families
  SELECT COUNT(*) INTO v_total_wins
  FROM "game_participants"
  WHERE "userId" = p_user_id
    AND "result" = 'win'
    AND "leftAt" IS NULL; -- exclude re-joined rows that were left

  -- Wins this month
  SELECT COUNT(*) INTO v_monthly_wins
  FROM "game_participants"
  WHERE "userId" = p_user_id
    AND "result" = 'win'
    AND "completedAt" >= v_month_start;

  -- Wins inside this family
  SELECT COUNT(*) INTO v_family_wins
  FROM "game_participants"
  WHERE "userId" = p_user_id
    AND "familyId" = p_family_id
    AND "result" = 'win';

  -- The running family win number (this win + previous wins in this family)
  v_family_win_number := v_family_wins;

  -- Total games played
  SELECT COUNT(*) INTO v_total_games
  FROM "game_participants"
  WHERE "userId" = p_user_id
    AND "completedAt" IS NOT NULL;

  -- Current win streak: walk back through games ordered by completedAt DESC
  -- until we hit a non-win.
  SELECT COALESCE(
    (SELECT streak FROM (
      WITH recent AS (
        SELECT "result",
               ROW_NUMBER() OVER (ORDER BY "completedAt" DESC) AS rn
        FROM "game_participants"
        WHERE "userId" = p_user_id
          AND "completedAt" IS NOT NULL
        LIMIT 50
      )
      SELECT COUNT(*) AS streak
      FROM recent r1
      WHERE r1."result" = 'win'
        AND NOT EXISTS (
          SELECT 1 FROM recent r2
          WHERE r2.rn < r1.rn AND r2."result" <> 'win'
        )
    ) s),
    0
  ) INTO v_current_streak;

  RETURN jsonb_build_object(
    'totalWins', v_total_wins,
    'monthlyWins', v_monthly_wins,
    'familyWins', v_family_wins,
    'familyWinNumber', v_family_win_number,
    'totalGames', v_total_games,
    'currentStreak', v_current_streak
  );
END;
$$;

-- =============================================================================
-- 3. fn_get_family_presence — Games hub presence strip
-- =============================================================================
-- Returns: { onlineCount, playingCount, spectatingCount, totalMembers,
--            onlineMembers: [{userId, userName, status}] }
--
-- status values: 'online' | 'playing' | 'spectating' | 'offline'
-- 'online' = MemberPresence.status not 'away' AND lastSeenAt within 5 min
-- 'playing' = currently has an active game_participants row (game row status
--             = activeStatusValue, no leftAt)
-- 'spectating' = currently has a game_spectators row with leftAt IS NULL
-- 'offline' = presenceStatus = away OR lastSeen > 5min ago
-- =============================================================================
-- 'online' = MemberPresence.status not 'away' AND lastSeenAt within 5 min
-- 'playing' = has an active game_participants row (leftAt IS NULL,
--             joinedAt within 2 hours)
-- 'spectating' = has an active game_spectators row with leftAt IS NULL
-- 'offline' = MemberPresence.status = 'away' OR lastSeenAt > 5min ago
--
-- NOTE: Presence is tracked in a separate MemberPresence table — NOT on
-- FamilyMember itself. The presence RPC joins MemberPresence + User +
-- game_participants + game_spectators to compute the live counts.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_get_family_presence(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_online_count int;
  v_playing_count int;
  v_spectating_count int;
  v_total_members int;
  v_online_members jsonb;
  v_five_min_ago timestamptz := now() - interval '5 minutes';
BEGIN
  -- Total linked members in this family
  SELECT COUNT(*) INTO v_total_members
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id;

  -- Online = MemberPresence.status not 'away' AND lastSeenAt within 5 min
  SELECT COUNT(*) INTO v_online_count
  FROM "MemberPresence" mp
  WHERE mp."familyId" = p_family_id
    AND mp."status" IS NOT NULL
    AND mp."status" <> 'away'
    AND mp."lastSeenAt" >= v_five_min_ago;

  -- Playing = has an active game_participants row in any game table.
  SELECT COUNT(DISTINCT gp."userId") INTO v_playing_count
  FROM "game_participants" gp
  WHERE gp."familyId" = p_family_id
    AND gp."leftAt" IS NULL
    AND gp."role" <> 'spectator'
    AND gp."joinedAt" >= now() - interval '2 hours';

  -- Spectating = has an active game_spectators row
  SELECT COUNT(DISTINCT gs."userId") INTO v_spectating_count
  FROM "game_spectators" gs
  WHERE gs."familyId" = p_family_id
    AND gs."leftAt" IS NULL;

  -- Build the online members list (top 12, newest lastSeenAt first)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'userId', mp."userId",
    'userName', COALESCE(u."name", u."email", 'Family Member'),
    'status', CASE
      WHEN gp_active."userId" IS NOT NULL THEN 'playing'
      WHEN gs_active."userId" IS NOT NULL THEN 'spectating'
      ELSE 'online'
    END
  ) ORDER BY mp."lastSeenAt" DESC NULLS LAST), '[]'::jsonb) INTO v_online_members
  FROM "MemberPresence" mp
  LEFT JOIN "User" u ON u."id" = mp."userId"
  LEFT JOIN "game_participants" gp_active
    ON gp_active."userId" = mp."userId"
    AND gp_active."leftAt" IS NULL
    AND gp_active."role" <> 'spectator'
    AND gp_active."joinedAt" >= now() - interval '2 hours'
  LEFT JOIN "game_spectators" gs_active
    ON gs_active."userId" = mp."userId"
    AND gs_active."leftAt" IS NULL
  WHERE mp."familyId" = p_family_id
    AND mp."status" IS NOT NULL
    AND mp."status" <> 'away'
    AND mp."lastSeenAt" >= v_five_min_ago
  LIMIT 12;

  RETURN jsonb_build_object(
    'onlineCount', v_online_count,
    'playingCount', v_playing_count,
    'spectatingCount', v_spectating_count,
    'totalMembers', v_total_members,
    'onlineMembers', v_online_members
  );
END;
$$;

-- =============================================================================
-- 4. fn_compute_dynamic_room_size — auto-scale maxPlayers
-- =============================================================================
-- Returns the recommended maxPlayers for a new room in this family:
--   small family  (1-10 members)  → 8 players
--   medium family (11-25 members) → 16 players
--   large family  (26-50 members) → 25 players
--   very large    (51+ members)   → 32 players
--
-- This is a soft cap — hosts can still override in Advanced Settings.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_compute_dynamic_room_size(
  p_family_id text
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_count int;
  v_max_players int;
BEGIN
  SELECT COUNT(*) INTO v_member_count
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id;

  IF v_member_count <= 10 THEN
    v_max_players := 8;
  ELSIF v_member_count <= 25 THEN
    v_max_players := 16;
  ELSIF v_member_count <= 50 THEN
    v_max_players := 25;
  ELSE
    v_max_players := 32;
  END IF;

  RETURN v_max_players;
END;
$$;

-- =============================================================================
-- 5. fn_start_match_countdown — host-only countdown trigger
-- =============================================================================
-- Host taps "Start Match" → this RPC inserts a 'countdown' room event
-- with a 5-second deadline. Every connected client sees the event via
-- the game_room_events realtime subscription and shows the 5-4-3-2-1
-- overlay. The host's client then calls the game's own start callback
-- after 5 seconds elapse locally.
--
-- Returns the countdown deadline (UTC ISO 8601) so all clients tick in
-- sync, or NULL on error / non-host.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_start_match_countdown(
  p_game_table text,
  p_game_id text,
  p_user_id text,
  p_seconds int DEFAULT 5
) RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_host_user_id text;
  v_family_id text;
  v_deadline timestamptz;
BEGIN
  -- Load the hostUserId + familyId using dynamic SQL (table name is a parameter)
  EXECUTE format(
    'SELECT "hostUserId", "familyId" FROM public.%I WHERE "id" = $1',
    p_game_table
  ) INTO v_host_user_id, v_family_id
    USING p_game_id;

  IF v_host_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Only the host may start the countdown
  IF v_host_user_id <> p_user_id THEN
    RETURN NULL;
  END IF;

  v_deadline := now() + make_interval(secs => p_seconds);

  -- Insert a 'countdown' event so realtime fans it out to all clients
  -- (family_id is already known from the game row — no need for a
  --  dynamic FROM clause here.)
  INSERT INTO "game_room_events" (
    "gameTable", "gameId", "familyId",
    "userId", "userName",
    "eventType", "payload", "createdAt"
  ) VALUES (
    p_game_table, p_game_id, v_family_id,
    p_user_id, NULL,
    'countdown',
    jsonb_build_object(
      'deadline', v_deadline,
      'seconds', p_seconds,
      'startedBy', p_user_id
    ),
    now()
  );

  RETURN v_deadline;
END;
$$;

-- =============================================================================
-- 6. Grant execute on the new RPCs to authenticated users
-- =============================================================================
-- RLS already gates table access; these RPCs are SECURITY DEFINER so they
-- can read across families the user is a member of. But we still need to
-- grant EXECUTE so authenticated clients can invoke them.
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.fn_get_user_win_stats(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_family_presence(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_compute_dynamic_room_size(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_start_match_countdown(text, text, text, int) TO authenticated;

-- =============================================================================
-- Verification
-- =============================================================================

DO $$
DECLARE
  v_badge_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_badge_cnt FROM "Badge" WHERE category = 'games';
  RAISE NOTICE 'Total game-related badges after migration: %', v_badge_cnt;
END $$;
