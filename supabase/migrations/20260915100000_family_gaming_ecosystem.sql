-- =============================================================================
-- Daxelo-Kinrel — Family Gaming Ecosystem (comprehensive)
-- =============================================================================
-- Implements the full Family Gaming Ecosystem across all 14 games:
--
--   1.  game_match_history + game_match_players — PERMANENT match archive
--       (fixes the critical bug where fn_end_game hard-deleted
--       game_participants and win stats never persisted).
--   2.  game_user_stats / game_family_stats — cheap aggregate tables for
--       leaderboards (all-time), streaks, points, sportsmanship.
--   3.  fn__archive_family_match — THE central processor. Runs inside
--       fn_end_game (before hard-delete) and via fn_get_match_ecosystem.
--       Archives the match, updates stats, evaluates badges, advances
--       challenges, records milestones, writes the activity feed and
--       updates Family Cup season standings. Idempotent.
--   4.  Leaderboards v2 — weekly / monthly / all-time / per-game, sorted by
--       participation-weighted points (non-toxic framing).
--   5.  Challenges — weekly + monthly mission templates with lazy
--       per-(user, family, period) progress rows.
--   6.  Milestones — family milestones (1/10/25/50/100/250/500 matches
--       together, game variety) using the existing FamilyMilestone table.
--   7.  Activity feed — reuses FamilyActivityLog with action='game_*'.
--   8.  Seasons / Family Cups — monthly seasons with points standings,
--       lazy finalization + winner archive.
--   9.  Sportsmanship — post-match notes (gg / great move / well played)
--       that feed a sportsmanship score.
--  10.  Smart match suggestions — online members + play history.
--  11.  Player gaming profiles — favorite game, win rate, per-game stats.
--  12.  New game badges (Ludo Champion, Family Explorer, per-game masters,
--       sportsmanship, Family Cup champion, ...).
--  13.  fn_get_user_win_stats / fn_get_family_leaderboard / fn_get_recent_
--       playmates REWRITTEN to read persistent data (they previously read
--       game_participants rows that fn_end_game deletes).
--
-- Design rules (per docs/MIGRATIONS.md): every function SECURITY DEFINER
-- with search_path pinned to public; idempotent DDL; RLS on all new tables.
-- =============================================================================

-- =============================================================================
-- SECTION 1: PERSISTENT MATCH ARCHIVE
-- =============================================================================

CREATE TABLE IF NOT EXISTS "game_match_history" (
  "id"              text PRIMARY KEY,          -- same as the original game row id
  "gameTable"       text NOT NULL,
  "gameId"          text NOT NULL,
  "familyId"        text NOT NULL,
  "playerCount"     int  NOT NULL DEFAULT 0,
  "winnerUserIds"   text[] DEFAULT '{}',
  "winnerNames"     text[] DEFAULT '{}',
  "resultKind"      text NOT NULL DEFAULT 'played',  -- win | draw | played
  "finishedAt"      timestamptz NOT NULL DEFAULT now(),
  "startedAt"       timestamptz,
  "durationSeconds" int,
  "createdAt"       timestamptz NOT NULL DEFAULT now()
);

-- One archive per game row
CREATE UNIQUE INDEX IF NOT EXISTS uq_game_match_history_game
  ON "game_match_history" ("gameTable", "gameId");

CREATE INDEX IF NOT EXISTS idx_gmh_family_finished
  ON "game_match_history" ("familyId", "finishedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_gmh_family_table
  ON "game_match_history" ("familyId", "gameTable", "finishedAt" DESC);

ALTER TABLE "game_match_history" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_match_history_select_family" ON "game_match_history"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- Per-player permanent record of each archived match
CREATE TABLE IF NOT EXISTS "game_match_players" (
  "id"          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "matchId"     text NOT NULL,              -- game_match_history.id
  "gameTable"   text NOT NULL,
  "gameId"      text NOT NULL,
  "familyId"    text NOT NULL,
  "userId"      text NOT NULL,
  "userName"    text,
  "result"      text NOT NULL DEFAULT 'played', -- win | loss | draw | played
  "finishedAt"  timestamptz NOT NULL DEFAULT now(),
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_match_players_match_user
  ON "game_match_players" ("matchId", "userId");

CREATE INDEX IF NOT EXISTS idx_gmp_user_finished
  ON "game_match_players" ("userId", "finishedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_gmp_family_user
  ON "game_match_players" ("familyId", "userId", "finishedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_gmp_family_finished
  ON "game_match_players" ("familyId", "finishedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_gmp_family_table_user
  ON "game_match_players" ("familyId", "gameTable", "userId");

ALTER TABLE "game_match_players" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_match_players_select_family" ON "game_match_players"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- =============================================================================
-- SECTION 2: AGGREGATE STATS TABLES
-- =============================================================================

-- Per (user, family, game) rolling stats. gameTable = '*' means all games.
CREATE TABLE IF NOT EXISTS "game_user_stats" (
  "id"                    text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"                text NOT NULL,
  "familyId"              text NOT NULL,
  "gameTable"             text NOT NULL DEFAULT '*',
  "matches"               int  NOT NULL DEFAULT 0,
  "wins"                  int  NOT NULL DEFAULT 0,
  "losses"                int  NOT NULL DEFAULT 0,
  "draws"                 int  NOT NULL DEFAULT 0,
  "played"                int  NOT NULL DEFAULT 0,   -- party-game participations
  "points"                int  NOT NULL DEFAULT 0,   -- win=3 draw=1 played=1 loss=0
  "streakCurrent"         int  NOT NULL DEFAULT 0,   -- consecutive wins (overall per user+family)
  "streakBest"            int  NOT NULL DEFAULT 0,
  "spectated"             int  NOT NULL DEFAULT 0,
  "sportsmanshipGiven"    int  NOT NULL DEFAULT 0,
  "sportsmanshipReceived" int  NOT NULL DEFAULT 0,
  "lastPlayedAt"          timestamptz,
  "updatedAt"             timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_user_stats_user_family_game
  ON "game_user_stats" ("userId", "familyId", "gameTable");

CREATE INDEX IF NOT EXISTS idx_gus_family_game
  ON "game_user_stats" ("familyId", "gameTable");

ALTER TABLE "game_user_stats" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_user_stats_select_family" ON "game_user_stats"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- Per-family aggregate
CREATE TABLE IF NOT EXISTS "game_family_stats" (
  "id"             text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"       text NOT NULL,
  "totalMatches"   int  NOT NULL DEFAULT 0,
  "distinctGames"  int  NOT NULL DEFAULT 0,
  "lastMatchAt"    timestamptz,
  "firstMatchAt"   timestamptz,
  "updatedAt"      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_family_stats_family
  ON "game_family_stats" ("familyId");

ALTER TABLE "game_family_stats" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_family_stats_select_family" ON "game_family_stats"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- =============================================================================
-- SECTION 3: CHALLENGES
-- =============================================================================

CREATE TABLE IF NOT EXISTS "game_challenge_templates" (
  "slug"         text PRIMARY KEY,
  "title"        text NOT NULL,
  "description"  text NOT NULL,
  "cadence"      text NOT NULL DEFAULT 'weekly',   -- weekly | monthly
  "metric"       text NOT NULL,                    -- matches | wins | variety | together | days | family_matches
  "target"       int  NOT NULL DEFAULT 3,
  "icon"         text NOT NULL DEFAULT '🎯',
  "rewardPoints" int  NOT NULL DEFAULT 25,
  "familyWide"   boolean NOT NULL DEFAULT false,
  "sortOrder"    int  NOT NULL DEFAULT 100,
  "isActive"     boolean NOT NULL DEFAULT true,
  "createdAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "game_challenge_progress" (
  "id"           text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "templateSlug" text NOT NULL,
  "familyId"     text NOT NULL,
  "userId"       text NOT NULL DEFAULT '*',   -- '*' = family-wide challenge
  "periodKey"    text NOT NULL,               -- '2026-W37' weekly | '2026-09' monthly
  "progress"     int  NOT NULL DEFAULT 0,
  "target"       int  NOT NULL,
  "completedAt"  timestamptz,
  "createdAt"    timestamptz NOT NULL DEFAULT now(),
  "updatedAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gcp_slug_family_user_period
  ON "game_challenge_progress" ("templateSlug", "familyId", "userId", "periodKey");

CREATE INDEX IF NOT EXISTS idx_gcp_family_period
  ON "game_challenge_progress" ("familyId", "periodKey");

ALTER TABLE "game_challenge_templates" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "game_challenge_templates_select_all" ON "game_challenge_templates"
  FOR SELECT TO authenticated USING (true);

ALTER TABLE "game_challenge_progress" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "game_challenge_progress_select_family" ON "game_challenge_progress"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- Seed challenge templates (idempotent)
INSERT INTO "game_challenge_templates"
  ("slug","title","description","cadence","metric","target","icon","rewardPoints","familyWide","sortOrder")
VALUES
  ('weekly-play-3',  'Warm-Up Week',        'Play 3 matches with your family this week',                'weekly',  'matches',   3, '🎮', 25, false, 10),
  ('weekly-win-2',   'Twin Triumph',        'Win 2 matches this week',                                  'weekly',  'wins',      2, '🏅', 40, false, 20),
  ('weekly-together','Better Together',     'Play with 2 or more different family members this week',   'weekly',  'together',  2, '🤝', 35, false, 30),
  ('weekly-variety', 'Fresh Flavors',       'Try 2 different games this week',                          'weekly',  'variety',   2, '✨', 30, false, 40),
  ('weekly-streak-2','Double Delight',      'Win 2 matches in a row this week',                         'weekly',  'streak',    2, '🔥', 45, false, 50),
  ('monthly-play-10','Family Regular',      'Play 10 matches this month',                               'monthly', 'matches',  10, '📅', 80, false, 60),
  ('monthly-win-5',  'Victory Month',       'Win 5 matches this month',                                 'monthly', 'wins',      5, '🏆', 120, false, 70),
  ('monthly-explorer','Family Explorer',    'Play 5 different games this month',                        'monthly', 'variety',   5, '🧭', 100, false, 80),
  ('monthly-days-5', 'Habit Builder',       'Play on 5 different days this month',                      'monthly', 'days',      5, '🌱', 90, false, 90),
  ('monthly-family-25','Family Force',      'Your whole family plays 25 matches this month',            'monthly', 'family_matches', 25, '👨‍👩‍👧‍👦', 150, true, 100)
ON CONFLICT ("slug") DO UPDATE SET
  "title" = EXCLUDED."title",
  "description" = EXCLUDED."description",
  "cadence" = EXCLUDED."cadence",
  "metric" = EXCLUDED."metric",
  "target" = EXCLUDED."target",
  "icon" = EXCLUDED."icon",
  "rewardPoints" = EXCLUDED."rewardPoints",
  "familyWide" = EXCLUDED."familyWide",
  "sortOrder" = EXCLUDED."sortOrder",
  "isActive" = true;

-- =============================================================================
-- SECTION 4: SEASONS / FAMILY CUPS
-- =============================================================================

CREATE TABLE IF NOT EXISTS "game_seasons" (
  "id"        text PRIMARY KEY,             -- e.g. 'cup-2026-09'
  "name"      text NOT NULL,                -- e.g. 'The Family Cup — September 2026'
  "periodKey" text NOT NULL,                -- '2026-09'
  "startsAt"  timestamptz NOT NULL,
  "endsAt"    timestamptz NOT NULL,
  "theme"     text NOT NULL DEFAULT 'kinrel',
  "badgeSlug" text,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_seasons_period ON "game_seasons" ("periodKey");

CREATE TABLE IF NOT EXISTS "game_season_standings" (
  "id"          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "seasonId"    text NOT NULL,
  "familyId"    text NOT NULL,
  "userId"      text NOT NULL,
  "points"      int  NOT NULL DEFAULT 0,
  "wins"        int  NOT NULL DEFAULT 0,
  "gamesPlayed" int  NOT NULL DEFAULT 0,
  "updatedAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gss_season_family_user
  ON "game_season_standings" ("seasonId", "familyId", "userId");
CREATE INDEX IF NOT EXISTS idx_gss_family ON "game_season_standings" ("familyId");

CREATE TABLE IF NOT EXISTS "game_season_winners" (
  "id"        text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "seasonId"  text NOT NULL,
  "familyId"  text NOT NULL,
  "userId"    text NOT NULL,
  "userName"  text,
  "rank"      int  NOT NULL,
  "points"    int  NOT NULL,
  "awardedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gsw_season_family_rank
  ON "game_season_winners" ("seasonId", "familyId", "rank");

ALTER TABLE "game_seasons" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "game_seasons_select_all" ON "game_seasons" FOR SELECT TO authenticated USING (true);

ALTER TABLE "game_season_standings" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "game_season_standings_select_family" ON "game_season_standings"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

ALTER TABLE "game_season_winners" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "game_season_winners_select_family" ON "game_season_winners"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

-- =============================================================================
-- SECTION 5: SPORTSMANSHIP
-- =============================================================================

CREATE TABLE IF NOT EXISTS "game_sportsmanship_notes" (
  "id"         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "matchId"    text NOT NULL,
  "gameTable"  text NOT NULL,
  "familyId"   text NOT NULL,
  "fromUserId" text NOT NULL,
  "fromName"   text,
  "toUserId"   text NOT NULL,
  "toName"     text,
  "kind"       text NOT NULL,   -- gg | great_move | well_played | fun_game | good_sport
  "message"    text,
  "createdAt"  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gsn_match_from_to
  ON "game_sportsmanship_notes" ("matchId", "fromUserId", "toUserId");

CREATE INDEX IF NOT EXISTS idx_gsn_to_user ON "game_sportsmanship_notes" ("toUserId", "createdAt" DESC);

ALTER TABLE "game_sportsmanship_notes" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_sportsmanship_select_family" ON "game_sportsmanship_notes"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));

CREATE POLICY "game_sportsmanship_insert_self" ON "game_sportsmanship_notes"
  FOR INSERT TO authenticated WITH CHECK ("fromUserId" = auth.uid()::text);

-- =============================================================================
-- SECTION 6: NEW GAME BADGES (idempotent seed)
-- =============================================================================

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt")
VALUES
  (gen_random_uuid()::text,'family-explorer','Family Explorer','परिवार खोजी','Play 8 different games with your family','🧭','games','gold',8,false,now()),
  (gen_random_uuid()::text,'ludo-champion','Ludo Champion','लूडो चैंपियन','Win 5 Ludo games','🎲','games','gold',5,false,now()),
  (gen_random_uuid()::text,'chess-master','Chess Master','शतरंज मास्टर','Win 5 Chess games','♞','games','gold',5,false,now()),
  (gen_random_uuid()::text,'carrom-king','Carrom King','कैरम राजा','Win 5 Carrom games','⚪','games','gold',5,false,now()),
  (gen_random_uuid()::text,'checkers-champ','Checkers Champ','चेकर्स चैंपियन','Win 5 Checkers games','🔴','games','silver',5,false,now()),
  (gen_random_uuid()::text,'tictactoe-tactician','Tic-Tac-Toe Tactician','टिक टैक टो रणनीतिकार','Win 5 Tic-Tac-Toe matches','#️⃣','games','silver',5,false,now()),
  (gen_random_uuid()::text,'dots-boxer','Dots Boxer','बिंदु बक्सर','Win 5 Dots and Boxes games','▪️','games','silver',5,false,now()),
  (gen_random_uuid()::text,'nameplace-scholar','Name Place Scholar','नाम स्थान विद्वान','Win 5 Name Place Animal Thing games','📖','games','silver',5,false,now()),
  (gen_random_uuid()::text,'antakshari-star','Antakshari Star','अंताक्षरी सितारा','Win 5 Antakshari games','🎤','games','gold',5,false,now()),
  (gen_random_uuid()::text,'twotruths-mastermind','Two Truths Mastermind','दो सत्य मास्टरमाइंड','Win 5 Two Truths and a Lie games','🕵️','games','silver',5,false,now()),
  (gen_random_uuid()::text,'truthordare-fearless','Truth or Dare Fearless','सत्य या साहस निडर','Play 10 Truth or Dare games','🎭','games','bronze',10,false,now()),
  (gen_random_uuid()::text,'chitmatch-collector','TripleMatch Collector','ट्रिपलमैच कलेक्टर','Win 5 TripleMatch games','🃏','games','silver',5,false,now()),
  (gen_random_uuid()::text,'freeze-dash-sprinter','Freeze & Dash Sprinter','फ्रीज़ डैश स्प्रिंटर','Win 5 Freeze & Dash rounds','🏃','games','silver',5,false,now()),
  (gen_random_uuid()::text,'play-50-games','Half Century','अर्धशतक','Play 50 games with your family','🏏','games','gold',50,false,now()),
  (gen_random_uuid()::text,'play-200-games','Game Legend','खेल किंवदंती','Play 200 games with your family','🌟','games','platinum',200,false,now()),
  (gen_random_uuid()::text,'social-gamer','Social Gamer','सामाजिक गेमर','Play 10 matches with 3 or more players','👥','games','silver',10,false,now()),
  (gen_random_uuid()::text,'early-bird','Early Bird','सुबह की चिड़िया','Play a match before 9 AM','🌅','games','bronze',1,false,now()),
  (gen_random_uuid()::text,'night-owl','Night Owl','नाइट आउल','Play a match after 10 PM','🦉','games','bronze',1,false,now()),
  (gen_random_uuid()::text,'cheering-champion','Cheering Champion','उत्साह चैंपियन','Send 10 sportsmanship cheers','📣','games','silver',10,false,now()),
  (gen_random_uuid()::text,'gracious-player','Gracious Player','सज्जन खिलाड़ी','Receive 10 sportsmanship cheers','💚','games','gold',10,false,now()),
  (gen_random_uuid()::text,'family-cup-champion','Family Cup Champion','पारिवारिक कप चैंपियन','Win a monthly Family Cup','🏆','games','platinum',1,false,now())
ON CONFLICT ("slug") DO NOTHING;

-- =============================================================================
-- SECTION 7: HELPER — game metadata (display names, icons)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__game_meta()
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'sos_games',          jsonb_build_object('id','sos','name','SOS','icon','🎯','accent','#F59E0B'),
    'bingo_games',        jsonb_build_object('id','bingo','name','Bingo','icon','🎟️','accent','#06B6D4'),
    'ludo_games',         jsonb_build_object('id','ludo','name','Ludo','icon','🎲','accent','#E11D48'),
    'antakshari_games',   jsonb_build_object('id','antakshari','name','Antakshari','icon','🎤','accent','#8B5CF6'),
    'chitmatch_games',    jsonb_build_object('id','chitmatch','name','TripleMatch','icon','🃏','accent','#EC4899'),
    'checkers_games',     jsonb_build_object('id','checkers','name','Checkers','icon','🔴','accent','#6366F1'),
    'chess_games',        jsonb_build_object('id','chess','name','Chess','icon','♞','accent','#64748B'),
    'carrom_games',       jsonb_build_object('id','carrom','name','Carrom','icon','⚪','accent','#F59E0B'),
    'tictactoe_games',    jsonb_build_object('id','tictactoe','name','Tic-Tac-Toe','icon','#️⃣','accent','#8B5CF6'),
    'truthordare_games',  jsonb_build_object('id','truthordare','name','Truth or Dare','icon','🎭','accent','#EF4444'),
    'twotruths_games',    jsonb_build_object('id','twotruths','name','Two Truths & a Lie','icon','🕵️','accent','#D946EF'),
    'dotsboxes_games',    jsonb_build_object('id','dotsboxes','name','Dots & Boxes','icon','▪️','accent','#06B6D4'),
    'nameplace_games',    jsonb_build_object('id','nameplace','name','Name Place Animal Thing','icon','📖','accent','#10B981'),
    'redlight_rounds',    jsonb_build_object('id','freeze-dash','name','Freeze & Dash','icon','🏃','accent','#10B981')
  );
$$;

-- =============================================================================
-- SECTION 8: CORE PROCESSOR — fn__archive_family_match
-- =============================================================================
-- Runs when a match reaches a terminal state (winner known OR status
-- terminal), BEFORE the room is hard-deleted. Archives the match
-- permanently, updates aggregate stats, evaluates badges, advances
-- challenges, checks milestones, writes the activity feed, and updates
-- Family Cup standings. IDEMPOTENT: a second call no-ops via the unique
-- index on game_match_history.
--
-- Called from:
--   • fn_end_game (server-side — catches timers, buttons, cron backstop)
--   • fn_get_match_ecosystem (client-side — first results screen render)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__archive_family_match(
  p_game_table text,
  p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family_id      text;
  v_status         text;
  v_created_at     timestamptz;
  v_finished_at    timestamptz;
  v_end_col        text;
  v_finished_status text;
  v_winner_col     text;
  v_winner_name_col text;
  v_winner_ids     text[] := '{}';
  v_winner_names   text[] := '{}';
  v_is_terminal    boolean := false;
  v_player_count   int := 0;
  v_meta           jsonb;
  v_result_kind    text := 'played';
  v_new_badges     jsonb := '[]'::jsonb;
  v_completed      jsonb := '[]'::jsonb;
  v_milestones     jsonb := '[]'::jsonb;
  v_badges_for_p   jsonb;
  v_chal_for_p     jsonb;
  v_participants   jsonb;
  v_p              jsonb;
  v_i              int;
  v_uid            text;
  v_uname          text;
  v_res            text;
  v_streak_before  int;
  v_duration       int;
  v_season_id      text;
  v_season_name    text;
  v_spectator      record;
  v_already        boolean;
BEGIN
  -- Whitelist game tables (security: p_game_table is used in dynamic SQL)
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games'
  ) THEN
    RETURN NULL;
  END IF;

  -- Idempotency: already archived → no-op
  SELECT EXISTS (
    SELECT 1 FROM "game_match_history"
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id
  ) INTO v_already;
  IF v_already THEN
    RETURN NULL;
  END IF;

  v_meta := public.fn__game_meta() -> p_game_table;

  -- ── Read the game row (dynamic: column names differ per table) ──
  -- sos_games + redlight_rounds use finishedAt; all others use completedAt.
  -- sos_games + redlight_rounds use status 'finished'; others 'completed'.
  IF p_game_table IN ('sos_games','redlight_rounds') THEN
    v_end_col := 'finishedAt';
    v_finished_status := 'finished';
  ELSE
    v_end_col := 'completedAt';
    v_finished_status := 'completed';
  END IF;

  EXECUTE format(
    'SELECT "familyId", "status", "createdAt", COALESCE(%I, now())
       FROM public.%I WHERE "id" = $1', v_end_col, p_game_table)
    INTO v_family_id, v_status, v_created_at, v_finished_at
    USING p_game_id;

  IF v_family_id IS NULL THEN
    RETURN NULL; -- game row already gone (e.g. race with cron)
  END IF;
  v_created_at := COALESCE(v_created_at, now());
  v_finished_at := COALESCE(v_finished_at, now());

  -- Terminal statuses per table (from RoomConfig presets)
  v_is_terminal := v_status IN (v_finished_status, 'ended', 'done');

  -- ── Extract winners (column name differs per table) ──
  -- Build ONLY the correct column reference — a CASE referencing columns of
  -- other tables fails to parse even when the branch is not taken.
  IF p_game_table = 'truthordare_games' THEN
    v_winner_ids := '{}';  -- party game: no winners, participation only
  ELSIF p_game_table IN ('antakshari_games','chitmatch_games','dotsboxes_games',
                          'nameplace_games','twotruths_games') THEN
    -- winnerUserIds is a jsonb array on these tables
    EXECUTE format(
      'SELECT ARRAY(SELECT jsonb_array_elements_text(COALESCE("winnerUserIds", ''[]''::jsonb))) FROM public.%I WHERE "id" = $1',
      p_game_table)
      INTO v_winner_ids USING p_game_id;
  ELSE
    v_winner_col := CASE
      WHEN p_game_table IN ('chess_games','checkers_games','carrom_games','ludo_games') THEN 'winnerId'
      WHEN p_game_table = 'tictactoe_games' THEN 'overallWinnerId'
      WHEN p_game_table = 'bingo_games' THEN 'winnerPlayerId'
      ELSE 'winnerUserId'  -- sos_games, redlight_rounds
    END;
    EXECUTE format(
      'SELECT ARRAY[COALESCE(%I, '''')] FROM public.%I WHERE "id" = $1',
      v_winner_col, p_game_table)
      INTO v_winner_ids USING p_game_id;
  END IF;

  v_winner_ids := COALESCE(v_winner_ids, '{}');
  v_winner_ids := ARRAY(SELECT x FROM unnest(v_winner_ids) AS x WHERE x IS NOT NULL AND x <> '');

  IF array_length(v_winner_ids, 1) IS NULL THEN
    IF NOT v_is_terminal THEN
      RETURN NULL; -- abandoned / cancelled / in-progress → do not archive
    END IF;
    v_result_kind := 'played';   -- finished without winners (party game / draw)
  ELSE
    v_result_kind := 'win';
    -- Winner display names — resolved uniformly from participants
    SELECT COALESCE(array_agg(gp."userName") FILTER (WHERE gp."userName" IS NOT NULL), '{}')
      INTO v_winner_names
    FROM "game_participants" gp
    WHERE gp."gameTable" = p_game_table
      AND gp."gameId" = p_game_id
      AND gp."userId" = ANY(v_winner_ids);
    IF array_length(v_winner_names, 1) IS NULL THEN
      -- fallback: the game row's name column (board games)
      v_winner_name_col := CASE
        WHEN p_game_table IN ('chess_games','checkers_games','carrom_games','ludo_games') THEN 'winnerName'
        WHEN p_game_table = 'tictactoe_games' THEN 'overallWinnerName'
        WHEN p_game_table = 'redlight_rounds' THEN 'winnerUserName'
        WHEN p_game_table = 'bingo_games' THEN 'winnerPlayerName'
        ELSE NULL
      END;
      IF v_winner_name_col IS NOT NULL THEN
        EXECUTE format(
          'SELECT ARRAY[COALESCE(%I, '''')] FROM public.%I WHERE "id" = $1',
          v_winner_name_col, p_game_table)
          INTO v_winner_names USING p_game_id;
        v_winner_names := ARRAY(SELECT x FROM unnest(COALESCE(v_winner_names,'{}')) AS x WHERE x IS NOT NULL AND x <> '');
      ELSE
        v_winner_names := '{}';
      END IF;
    END IF;
  END IF;

  -- ── Load live participants (rows still exist at this point) ──
  -- role filter includes 'host': the room host IS a player in every game
  -- (RoomController.createRoom records the host with role='host').
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'userId', gp."userId",
      'userName', COALESCE(gp."userName",'Family Member'),
      'role', gp."role")), '[]'::jsonb)
  INTO v_participants
  FROM "game_participants" gp
  WHERE gp."gameTable" = p_game_table
    AND gp."gameId" = p_game_id
    AND gp."role" IN ('player','host');

  v_player_count := jsonb_array_length(v_participants);

  -- ── Inline-player games (Pattern A: chess / checkers / carrom / tictactoe)
  --    create rooms via their own providers (ChallengeLobbyScreen), which do
  --    NOT write game_participants. Derive participants from the game row's
  --    player columns so those matches are archived too.
  IF v_player_count = 0 AND p_game_table IN ('chess_games','checkers_games','carrom_games','tictactoe_games') THEN
    DECLARE
      v_p1_id text; v_p1_name text; v_p2_id text; v_p2_name text;
    BEGIN
      IF p_game_table = 'tictactoe_games' THEN
        EXECUTE format('SELECT "playerXId","playerXName","playerOId","playerOName" FROM public.%I WHERE "id" = $1', p_game_table)
          INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      ELSIF p_game_table = 'chess_games' THEN
        EXECUTE format('SELECT "playerWhiteId","playerWhiteName","playerBlackId","playerBlackName" FROM public.%I WHERE "id" = $1', p_game_table)
          INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      ELSE -- checkers + carrom
        EXECUTE format('SELECT "playerOneId","playerOneName","playerTwoId","playerTwoName" FROM public.%I WHERE "id" = $1', p_game_table)
          INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      END IF;

      v_participants := jsonb_build_array(
        jsonb_build_object('userId', v_p1_id, 'userName', COALESCE(v_p1_name,'Player'), 'role', 'player'),
        jsonb_build_object('userId', v_p2_id, 'userName', COALESCE(v_p2_name,'Player'), 'role', 'player'));
      v_player_count := 2;
    END;
  END IF;

  IF v_player_count = 0 THEN
    RETURN NULL; -- nobody recorded → nothing to archive
  END IF;

  v_duration := GREATEST(0, EXTRACT(EPOCH FROM (v_finished_at - v_created_at))::int);

  -- ── 1. Archive the match ──
  INSERT INTO "game_match_history"
    ("id","gameTable","gameId","familyId","playerCount",
     "winnerUserIds","winnerNames","resultKind","finishedAt","startedAt","durationSeconds")
  VALUES
    (p_game_id, p_game_table, p_game_id, v_family_id, v_player_count,
     v_winner_ids, v_winner_names, v_result_kind, v_finished_at, v_created_at, v_duration)
  ON CONFLICT ("gameTable","gameId") DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM "game_match_history" WHERE "gameTable"=p_game_table AND "gameId"=p_game_id) THEN
    RETURN NULL; -- concurrent call won the race
  END IF;

  -- ── 2. Per-player rows + stats + badges + challenges ──
  FOR v_i IN 0 .. (v_player_count - 1) LOOP
    v_p := v_participants -> v_i;
    v_uid := v_p ->> 'userId';
    v_uname := v_p ->> 'userName';

    -- Result derivation
    IF v_winner_ids @> ARRAY[v_uid] THEN
      v_res := 'win';
    ELSIF array_length(v_winner_ids, 1) IS NULL THEN
      v_res := CASE WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
    ELSE
      v_res := CASE WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
    END IF;

    -- Streak snapshot BEFORE this match (for streak-based challenge checks)
    SELECT COALESCE(MAX("streakCurrent"), 0) INTO v_streak_before
    FROM "game_user_stats"
    WHERE "userId" = v_uid AND "familyId" = v_family_id AND "gameTable" = '*';

    INSERT INTO "game_match_players"
      ("matchId","gameTable","gameId","familyId","userId","userName","result","finishedAt")
    VALUES
      (p_game_id, p_game_table, p_game_id, v_family_id, v_uid, v_uname, v_res, v_finished_at)
    ON CONFLICT ("matchId","userId") DO NOTHING;

    -- game_user_stats: per-game row
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable",
       "matches","wins","losses","draws","played","points","lastPlayedAt")
    VALUES
      (v_uid, v_family_id, p_game_table,
       1,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='loss' THEN 1 ELSE 0 END,
       CASE WHEN v_res='draw' THEN 1 ELSE 0 END,
       CASE WHEN v_res='played' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
       v_finished_at)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "matches" = "game_user_stats"."matches" + 1,
      "wins" = "game_user_stats"."wins" + EXCLUDED."wins",
      "losses" = "game_user_stats"."losses" + EXCLUDED."losses",
      "draws" = "game_user_stats"."draws" + EXCLUDED."draws",
      "played" = "game_user_stats"."played" + EXCLUDED."played",
      "points" = "game_user_stats"."points" + EXCLUDED."points",
      "lastPlayedAt" = EXCLUDED."lastPlayedAt",
      "updatedAt" = now();

    -- game_user_stats: overall ('*') row with streak maintenance
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable",
       "matches","wins","losses","draws","played","points",
       "streakCurrent","streakBest","lastPlayedAt")
    VALUES
      (v_uid, v_family_id, '*',
       1,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='loss' THEN 1 ELSE 0 END,
       CASE WHEN v_res='draw' THEN 1 ELSE 0 END,
       CASE WHEN v_res='played' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       v_finished_at)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "matches" = "game_user_stats"."matches" + 1,
      "wins" = "game_user_stats"."wins" + EXCLUDED."wins",
      "losses" = "game_user_stats"."losses" + EXCLUDED."losses",
      "draws" = "game_user_stats"."draws" + EXCLUDED."draws",
      "played" = "game_user_stats"."played" + EXCLUDED."played",
      "points" = "game_user_stats"."points" + EXCLUDED."points",
      "streakCurrent" = CASE
        WHEN EXCLUDED."wins" > 0 THEN "game_user_stats"."streakCurrent" + 1
        ELSE 0 END,
      "streakBest" = CASE
        WHEN EXCLUDED."wins" > 0 THEN GREATEST("game_user_stats"."streakBest", "game_user_stats"."streakCurrent" + 1)
        ELSE "game_user_stats"."streakBest" END,
      "lastPlayedAt" = EXCLUDED."lastPlayedAt",
      "updatedAt" = now();

    -- Badges for this player
    v_badges_for_p := public.fn__evaluate_game_badges(v_uid, v_family_id);
    IF v_badges_for_p IS NOT NULL AND jsonb_array_length(v_badges_for_p) > 0 THEN
      v_new_badges := v_new_badges || jsonb_build_object(
        'userId', v_uid, 'userName', v_uname, 'badges', v_badges_for_p);
    END IF;

    -- Challenges for this player
    v_chal_for_p := public.fn__advance_challenges(v_uid, v_family_id);
    IF v_chal_for_p IS NOT NULL AND jsonb_array_length(v_chal_for_p) > 0 THEN
      v_completed := v_completed || jsonb_build_object(
        'userId', v_uid, 'userName', v_uname, 'challenges', v_chal_for_p);
    END IF;
  END LOOP;

  -- ── 3. Spectator archive (rows still exist pre-delete) ──
  FOR v_spectator IN
    SELECT "userId", "userName" FROM "game_spectators"
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id
  LOOP
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable","spectated")
    VALUES (v_spectator."userId", v_family_id, '*', 1)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "spectated" = "game_user_stats"."spectated" + 1,
      "updatedAt" = now();
  END LOOP;

  -- ── 4. Family aggregate ──
  INSERT INTO "game_family_stats" ("familyId","totalMatches","firstMatchAt","lastMatchAt")
  VALUES (v_family_id, 1, v_finished_at, v_finished_at)
  ON CONFLICT ("familyId") DO UPDATE SET
    "totalMatches" = "game_family_stats"."totalMatches" + 1,
    "lastMatchAt" = v_finished_at,
    "updatedAt" = now();

  UPDATE "game_family_stats" SET "distinctGames" = (
    SELECT COUNT(DISTINCT "gameTable") FROM "game_match_history" WHERE "familyId" = v_family_id
  ) WHERE "familyId" = v_family_id;

  -- ── 5. Activity feed: match completed ──
  INSERT INTO "FamilyActivityLog"
    ("id","familyId","actorUserId","actorName","action","description","metadata")
  VALUES (
    gen_random_uuid()::text,
    v_family_id,
    COALESCE(v_winner_ids[1], (v_participants->0->>'userId')),
    COALESCE(v_winner_names[1], (v_participants->0->>'userName'), 'Family'),
    'game_match_completed',
    CASE
      WHEN array_length(v_winner_ids,1) IS NULL
        THEN format('%s · %s players · a fun family moment', (v_meta->>'name'), v_player_count::text)
      ELSE format('%s won %s · %s players', array_to_string(v_winner_names, ' & '), (v_meta->>'name'), v_player_count)
    END,
    jsonb_build_object(
      'gameTable', p_game_table,
      'gameId', p_game_id,
      'gameName', v_meta->>'name',
      'gameIcon', v_meta->>'icon',
      'winners', to_jsonb(v_winner_names),
      'playerCount', v_player_count,
      'durationSeconds', v_duration
    )
  );

  -- ── 6. Season / Family Cup standings ──
  -- Ensure the current month's season exists BEFORE the lookup so the very
  -- first match of a month still earns Cup points (lazy season creation).
  IF v_finished_at >= date_trunc('month', now()) THEN
    PERFORM public.fn_get_current_season(NULL);
  END IF;

  SELECT "id","name" INTO v_season_id, v_season_name
  FROM "game_seasons"
  WHERE v_finished_at >= "startsAt" AND v_finished_at < "endsAt"
  LIMIT 1;

  IF v_season_id IS NOT NULL THEN
    FOR v_i IN 0 .. (v_player_count - 1) LOOP
      v_p := v_participants -> v_i;
      v_uid := v_p ->> 'userId';
      IF v_winner_ids @> ARRAY[v_uid] THEN v_res := 'win';
      ELSIF array_length(v_winner_ids,1) IS NULL THEN v_res := CASE WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
      ELSE v_res := CASE WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
      END IF;
      INSERT INTO "game_season_standings"
        ("seasonId","familyId","userId","points","wins","gamesPlayed")
      VALUES
        (v_season_id, v_family_id, v_uid,
         CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
         CASE WHEN v_res='win' THEN 1 ELSE 0 END, 1)
      ON CONFLICT ("seasonId","familyId","userId") DO UPDATE SET
        "points" = "game_season_standings"."points" + EXCLUDED."points",
        "wins" = "game_season_standings"."wins" + EXCLUDED."wins",
        "gamesPlayed" = "game_season_standings"."gamesPlayed" + 1,
        "updatedAt" = now();
    END LOOP;
  END IF;

  -- ── 7. Family milestones ──
  v_milestones := public.fn__check_family_milestones(v_family_id);

  RETURN jsonb_build_object(
    'matchId', p_game_id,
    'gameTable', p_game_table,
    'gameName', v_meta->>'name',
    'gameIcon', v_meta->>'icon',
    'familyId', v_family_id,
    'winners', to_jsonb(v_winner_names),
    'playerCount', v_player_count,
    'durationSeconds', v_duration,
    'newBadges', v_new_badges,
    'completedChallenges', v_completed,
    'milestones', v_milestones
  );
END;
$$;

-- =============================================================================
-- SECTION 9: BADGE EVALUATION — fn__evaluate_game_badges
-- =============================================================================
-- Checks every games-category badge condition for (user, family) using the
-- persistent stats tables. Inserts newly earned rows into UserBadge and an
-- activity-feed entry per badge. Returns the jsonb array of NEWLY earned
-- badges (slug, name, icon, tier). Idempotent — already-held badges are
-- skipped via the unique index on UserBadge (userId+badgeId+familyId).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__evaluate_game_badges(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overall   record;      -- overall stats row (gameTable='*')
  v_wins      int := 0;
  v_matches   int := 0;
  v_best      int := 0;
  v_spect     int := 0;
  v_given     int := 0;
  v_received  int := 0;
  v_variety   int := 0;
  v_week      int := 0;
  v_weekend   int := 0;
  v_social    int := 0;
  v_early     int := 0;
  v_late      int := 0;
  v_night_reg int := 0;
  v_night_win int := 0;
  v_cup_win   int := 0;
  v_earned    text[] := '{}';
  v_badge     record;
  v_new_badges jsonb := '[]'::jsonb;
  v_user_name text;
BEGIN
  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  v_wins := v_overall."wins"; v_matches := v_overall."matches";
  v_best := v_overall."streakBest"; v_spect := v_overall."spectated";
  v_given := v_overall."sportsmanshipGiven"; v_received := v_overall."sportsmanshipReceived";

  SELECT COUNT(DISTINCT "gameTable") INTO v_variety
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id;

  SELECT COUNT(*) INTO v_week
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND "finishedAt" >= now() - interval '7 days';

  SELECT COUNT(*) INTO v_weekend
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(ISODOW FROM "finishedAt") IN (6,7);

  SELECT COUNT(*) INTO v_social
  FROM "game_match_players" gmp
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id
    AND (SELECT COUNT(*) FROM "game_match_players" o
         WHERE o."matchId"=gmp."matchId") >= 3;

  SELECT COUNT(*) INTO v_early
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(HOUR FROM "finishedAt" AT TIME ZONE 'Asia/Kolkata') < 9;

  SELECT COUNT(*) INTO v_late
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(HOUR FROM "finishedAt" AT TIME ZONE 'Asia/Kolkata') >= 22;

  -- scheduled family game night participations
  SELECT COUNT(*) INTO v_night_reg
  FROM "game_match_players" gmp
  JOIN "scheduled_game_nights" sgn
    ON sgn."familyId" = gmp."familyId"
   AND gmp."finishedAt" BETWEEN COALESCE(sgn."startedAt", sgn."scheduledFor") AND COALESCE(sgn."startedAt", sgn."scheduledFor") + interval '4 hours'
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id;

  SELECT COUNT(*) INTO v_night_win
  FROM "game_match_players" gmp
  JOIN "scheduled_game_nights" sgn
    ON sgn."familyId" = gmp."familyId"
   AND gmp."finishedAt" BETWEEN COALESCE(sgn."startedAt", sgn."scheduledFor") AND COALESCE(sgn."startedAt", sgn."scheduledFor") + interval '4 hours'
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id AND gmp."result"='win';

  SELECT COUNT(*) INTO v_cup_win
  FROM "game_season_winners"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "rank"=1;

  -- ── Build the earned set ──
  IF v_wins >= 1        THEN v_earned := v_earned || ARRAY['first-game-win']; END IF;
  IF v_wins >= 5        THEN v_earned := v_earned || ARRAY['win-5-games']; END IF;
  IF v_wins >= 25       THEN v_earned := v_earned || ARRAY['win-25-games']; END IF;
  IF v_wins >= 100      THEN v_earned := v_earned || ARRAY['win-100-games']; END IF;
  IF v_wins >= 10       THEN v_earned := v_earned || ARRAY['family-champion']; END IF;
  IF v_best >= 3        THEN v_earned := v_earned || ARRAY['win-streak-3']; END IF;
  IF v_best >= 5        THEN v_earned := v_earned || ARRAY['undefeated-streak-5']; END IF;
  IF v_week >= 5        THEN v_earned := v_earned || ARRAY['played-5-games-week']; END IF;
  IF v_weekend >= 3     THEN v_earned := v_earned || ARRAY['weekend-gamer']; END IF;
  IF v_matches >= 50    THEN v_earned := v_earned || ARRAY['play-50-games']; END IF;
  IF v_matches >= 200   THEN v_earned := v_earned || ARRAY['play-200-games']; END IF;
  IF v_variety >= 8     THEN v_earned := v_earned || ARRAY['family-explorer']; END IF;
  IF v_spect >= 5       THEN v_earned := v_earned || ARRAY['spectator-supporter']; END IF;
  IF v_social >= 10     THEN v_earned := v_earned || ARRAY['social-gamer']; END IF;
  IF v_early >= 1       THEN v_earned := v_earned || ARRAY['early-bird']; END IF;
  IF v_late >= 1        THEN v_earned := v_earned || ARRAY['night-owl']; END IF;
  IF v_given >= 10      THEN v_earned := v_earned || ARRAY['cheering-champion']; END IF;
  IF v_received >= 10   THEN v_earned := v_earned || ARRAY['gracious-player']; END IF;
  IF v_night_reg >= 4   THEN v_earned := v_earned || ARRAY['family-game-night-regular']; END IF;
  IF v_night_win >= 25  THEN v_earned := v_earned || ARRAY['family-night-champion']; END IF;
  IF v_cup_win >= 1     THEN v_earned := v_earned || ARRAY['family-cup-champion']; END IF;

  -- Per-game champion badges (5 wins in that game)
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='bingo_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['bingo-master']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='sos_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['sos-strategist']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='ludo_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['ludo-champion']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='chess_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['chess-master']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='carrom_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['carrom-king']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='checkers_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['checkers-champ']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='tictactoe_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['tictactoe-tactician']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='dotsboxes_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['dots-boxer']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='nameplace_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['nameplace-scholar']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='antakshari_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['antakshari-star']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='twotruths_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['twotruths-mastermind']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='chitmatch_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['chitmatch-collector']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='redlight_rounds' AND "wins">=5) THEN v_earned := v_earned || ARRAY['freeze-dash-sprinter']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='truthordare_games' AND "matches">=10) THEN v_earned := v_earned || ARRAY['truthordare-fearless']; END IF;

  IF v_earned = '{}' THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(MAX("userName"), 'Family Member') INTO v_user_name
  FROM "game_match_players" WHERE "userId" = p_user_id LIMIT 1;

  -- Insert only NEW badges; build the returned array from what was inserted
  FOR v_badge IN
    SELECT b."id", b."slug", b."name", b."icon", b."tier"
    FROM "Badge" b
    WHERE b."category" = 'games' AND b."slug" = ANY(v_earned)
      AND NOT EXISTS (
        SELECT 1 FROM "UserBadge" ub
        WHERE ub."badgeId" = b."id"
          AND ub."userId" = p_user_id
          AND COALESCE(ub."familyId", p_family_id) = p_family_id)
  LOOP
    INSERT INTO "UserBadge" ("id","userId","badgeId","familyId","earnedAt")
    VALUES (gen_random_uuid()::text, p_user_id, v_badge."id", p_family_id, now())
    ON CONFLICT DO NOTHING;

    v_new_badges := v_new_badges || jsonb_build_object(
      'slug', v_badge."slug",
      'name', v_badge."name",
      'icon', v_badge."icon",
      'tier', v_badge."tier");

    INSERT INTO "FamilyActivityLog"
      ("id","familyId","actorUserId","actorName","action","description","metadata")
    VALUES (
      gen_random_uuid()::text, p_family_id, p_user_id, v_user_name,
      'game_badge_earned',
      format('%s earned the %s badge', v_user_name, v_badge."name"),
      jsonb_build_object('badgeSlug', v_badge."slug", 'badgeName', v_badge."name",
                         'badgeIcon', v_badge."icon", 'badgeTier', v_badge."tier"));
  END LOOP;

  RETURN v_new_badges;
END;
$$;

-- =============================================================================
-- SECTION 10: CHALLENGES ENGINE — fn__advance_challenges
-- =============================================================================
-- RECOMPUTES every active challenge's progress for (user, family) directly
-- from game_match_players within the current period. Recomputation (rather
-- than increment) makes the engine idempotent and immune to double-counts.
-- Returns the jsonb array of challenges that just reached their target
-- during this call (completedAt transitions NULL → set).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__advance_challenges(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_key text := to_char(now(), 'IYYY-"W"IW');
  v_month_key text := to_char(now(), 'YYYY-MM');
  v_week_start timestamptz := date_trunc('week', now());
  v_month_start timestamptz := date_trunc('month', now());
  v_progress int;
  v_completed_now jsonb := '[]'::jsonb;
  v_t record;
  v_period_key text;
  v_period_start timestamptz;
  v_uname text;
BEGIN
  SELECT COALESCE(MAX("userName"), 'Family Member') INTO v_uname
  FROM "game_match_players" WHERE "userId" = p_user_id LIMIT 1;

  FOR v_t IN
    SELECT * FROM "game_challenge_templates" WHERE "isActive"
  LOOP
    v_period_key := CASE WHEN v_t."cadence" = 'weekly' THEN v_week_key ELSE v_month_key END;
    v_period_start := CASE WHEN v_t."cadence" = 'weekly' THEN v_week_start ELSE v_month_start END;

    -- Compute progress per metric (recomputed from persistent history)
    CASE v_t."metric"
      WHEN 'matches' THEN
        SELECT COUNT(*) INTO v_progress FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= v_period_start;
      WHEN 'wins' THEN
        SELECT COUNT(*) INTO v_progress FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "result"='win' AND "finishedAt" >= v_period_start;
      WHEN 'variety' THEN
        SELECT COUNT(DISTINCT "gameTable") INTO v_progress FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= v_period_start;
      WHEN 'together' THEN
        SELECT COUNT(DISTINCT o."userId") INTO v_progress
        FROM "game_match_players" mine
        JOIN "game_match_players" o
          ON o."matchId" = mine."matchId" AND o."userId" <> p_user_id
        WHERE mine."userId"=p_user_id AND mine."familyId"=p_family_id
          AND mine."finishedAt" >= v_period_start;
      WHEN 'days' THEN
        SELECT COUNT(DISTINCT date("finishedAt")) INTO v_progress FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= v_period_start;
      WHEN 'streak' THEN
        SELECT COALESCE(MAX(s.n), 0) INTO v_progress FROM (
          SELECT COUNT(*) AS n FROM (
            SELECT "result", "finishedAt",
                   ROW_NUMBER() OVER (ORDER BY "finishedAt")
                 - ROW_NUMBER() OVER (PARTITION BY ("result"='win') ORDER BY "finishedAt") AS grp
            FROM "game_match_players"
            WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= v_period_start
          ) x WHERE "result"='win' GROUP BY grp
        ) s;
      WHEN 'family_matches' THEN
        SELECT COUNT(*) INTO v_progress FROM "game_match_players"
        WHERE "familyId"=p_family_id AND "finishedAt" >= v_period_start;
      ELSE v_progress := 0;
    END CASE;

    -- Upsert the progress row. Family-wide templates track under the '*'
    -- sentinel userId so every family member sees the SAME shared progress.
    INSERT INTO "game_challenge_progress"
      ("templateSlug","familyId","userId","periodKey","progress","target")
    VALUES
      (v_t."slug", p_family_id,
       CASE WHEN v_t."familyWide" THEN '*' ELSE p_user_id END,
       v_period_key, v_progress, v_t."target")
    ON CONFLICT ("templateSlug","familyId","userId","periodKey") DO UPDATE SET
      "progress" = EXCLUDED."progress",
      "updatedAt" = now();

    -- Completion transition (exactly-once activity entry)
    IF v_progress >= v_t."target" THEN
      UPDATE "game_challenge_progress"
      SET "completedAt" = now(), "updatedAt" = now()
      WHERE "templateSlug"=v_t."slug" AND "familyId"=p_family_id
        AND "userId" = CASE WHEN v_t."familyWide" THEN '*' ELSE p_user_id END
        AND "periodKey"=v_period_key
        AND "completedAt" IS NULL
      RETURNING 1 INTO v_progress;

      IF FOUND THEN
        v_completed_now := v_completed_now || jsonb_build_object(
          'slug', v_t."slug", 'title', v_t."title", 'icon', v_t."icon",
          'description', v_t."description", 'rewardPoints', v_t."rewardPoints");

        INSERT INTO "FamilyActivityLog"
          ("id","familyId","actorUserId","actorName","action","description","metadata")
        VALUES (
          gen_random_uuid()::text, p_family_id, p_user_id, v_uname,
          'game_challenge_completed',
          format('%s completed the challenge "%s"', v_uname, v_t."title"),
          jsonb_build_object('slug', v_t."slug", 'title', v_t."title",
                             'icon', v_t."icon", 'rewardPoints', v_t."rewardPoints"));
      END IF;
    END IF;
  END LOOP;

  RETURN v_completed_now;
END;
$$;

-- =============================================================================
-- SECTION 11: MILESTONES — fn__check_family_milestones
-- =============================================================================
-- Milestones are FAMILY-level (games played together). Uses the existing
-- FamilyMilestone table. Returns jsonb array of newly reached milestones.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__check_family_milestones(
  p_family_id text,
  p_actor_user_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total int;
  v_distinct int;
  v_new jsonb := '[]'::jsonb;
  m text;
  d text;
  v_threshold int;
BEGIN
  SELECT COALESCE("totalMatches",0), COALESCE("distinctGames",0)
    INTO v_total, v_distinct
  FROM "game_family_stats" WHERE "familyId" = p_family_id;

  FOREACH m IN ARRAY ARRAY['first_family_match','games_together_10','games_together_25','games_together_50','games_together_100','games_together_250','games_together_500'] LOOP
    v_threshold := CASE m
      WHEN 'first_family_match' THEN 1 WHEN 'games_together_10' THEN 10
      WHEN 'games_together_25' THEN 25 WHEN 'games_together_50' THEN 50
      WHEN 'games_together_100' THEN 100 WHEN 'games_together_250' THEN 250
      ELSE 500 END;
    d := CASE m
      WHEN 'first_family_match'   THEN 'First family match played together'
      WHEN 'games_together_10'    THEN '10 games played together'
      WHEN 'games_together_25'    THEN '25 games played together'
      WHEN 'games_together_50'    THEN '50 games played together'
      WHEN 'games_together_100'   THEN '100 games played together'
      WHEN 'games_together_250'   THEN '250 games played together'
      ELSE '500 games played together' END;

    IF v_total >= v_threshold
      AND NOT EXISTS (SELECT 1 FROM "FamilyMilestone" WHERE "familyId"=p_family_id AND "milestone"=m) THEN
      INSERT INTO "FamilyMilestone" ("id","familyId","milestone","reachedAt","celebrated")
      VALUES (gen_random_uuid()::text, p_family_id, m, now(), false);

      INSERT INTO "FamilyActivityLog"
        ("id","familyId","actorUserId","actorName","action","description","metadata")
      VALUES (gen_random_uuid()::text, p_family_id, COALESCE(p_actor_user_id, 'family'), 'Family',
        'game_milestone_reached', d, jsonb_build_object('milestone', m));

      v_new := v_new || jsonb_build_object('milestone', m, 'description', d);
    END IF;
  END LOOP;

  -- Game variety milestones
  FOREACH m IN ARRAY ARRAY['games_variety_5','games_variety_10'] LOOP
    v_threshold := CASE m WHEN 'games_variety_5' THEN 5 ELSE 10 END;
    d := CASE m WHEN 'games_variety_5' THEN '5 different games explored as a family'
                ELSE '10 different games explored as a family' END;

    IF v_distinct >= v_threshold
      AND NOT EXISTS (SELECT 1 FROM "FamilyMilestone" WHERE "familyId"=p_family_id AND "milestone"=m) THEN
      INSERT INTO "FamilyMilestone" ("id","familyId","milestone","reachedAt","celebrated")
      VALUES (gen_random_uuid()::text, p_family_id, m, now(), false);

      INSERT INTO "FamilyActivityLog"
        ("id","familyId","actorUserId","actorName","action","description","metadata")
      VALUES (gen_random_uuid()::text, p_family_id, COALESCE(p_actor_user_id, 'family'), 'Family',
        'game_milestone_reached', d, jsonb_build_object('milestone', m));

      v_new := v_new || jsonb_build_object('milestone', m, 'description', d);
    END IF;
  END LOOP;

  RETURN v_new;
END;
$$;

-- =============================================================================
-- SECTION 12: SEASONS / FAMILY CUP
-- =============================================================================

-- Returns (creating if needed) the current month's Family Cup season, and
-- lazily finalizes any PAST seasons for this family (awarding winners).
CREATE OR REPLACE FUNCTION public.fn_get_current_season(
  p_family_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period text := to_char(now(), 'YYYY-MM');
  v_season record;
  v_ends timestamptz;
  v_old record;
  v_rank int;
  v_row record;
  v_winners jsonb;
BEGIN
  -- Lazy finalization of ended seasons (per family when given)
  IF p_family_id IS NOT NULL THEN
    FOR v_old IN
      SELECT s.* FROM "game_seasons" s
      WHERE s."endsAt" <= now()
        AND EXISTS (SELECT 1 FROM "game_season_standings" g
                    WHERE g."seasonId" = s."id" AND g."familyId" = p_family_id)
        AND NOT EXISTS (SELECT 1 FROM "game_season_winners" w
                        WHERE w."seasonId" = s."id" AND w."familyId" = p_family_id)
    LOOP
      v_rank := 0;
      FOR v_row IN
        SELECT g."userId", MAX(COALESCE(mp."userName", u."name", 'Family Member')) AS "userName",
               SUM(g."points") AS pts
        FROM "game_season_standings" g
        LEFT JOIN "User" u ON u."id" = g."userId"
        LEFT JOIN (
          SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
          WHERE "familyId" = p_family_id GROUP BY "userId"
        ) mp ON mp."userId" = g."userId"
        WHERE g."seasonId" = v_old."id" AND g."familyId" = p_family_id
        GROUP BY g."userId"
        ORDER BY pts DESC
        LIMIT 3
      LOOP
        v_rank := v_rank + 1;
        INSERT INTO "game_season_winners"
          ("seasonId","familyId","userId","userName","rank","points")
        VALUES (v_old."id", p_family_id, v_row."userId", v_row."userName", v_rank, v_row.pts)
        ON CONFLICT ("seasonId","familyId","rank") DO NOTHING;

        IF v_rank = 1 THEN
          INSERT INTO "FamilyActivityLog"
            ("id","familyId","actorUserId","actorName","action","description","metadata")
          VALUES (gen_random_uuid()::text, p_family_id, v_row."userId", v_row."userName",
            'game_cup_won',
            format('%s won %s', v_row."userName", v_old."name"),
            jsonb_build_object('seasonId', v_old."id", 'seasonName', v_old."name",
                               'points', v_row.pts));
          -- Cup champion badge
          INSERT INTO "UserBadge" ("id","userId","badgeId","familyId","earnedAt")
          SELECT gen_random_uuid()::text, v_row."userId", b."id", p_family_id, now()
          FROM "Badge" b WHERE b."slug"='family-cup-champion'
          ON CONFLICT DO NOTHING;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  -- Get or create the current season
  SELECT * INTO v_season FROM "game_seasons" WHERE "periodKey" = v_period;
  IF NOT FOUND THEN
    INSERT INTO "game_seasons" ("id","name","periodKey","startsAt","endsAt","theme")
    VALUES (
      'cup-' || v_period,
      'The Family Cup — ' || to_char(now(), 'FMMonth YYYY'),
      v_period,
      date_trunc('month', now()),
      date_trunc('month', now()) + interval '1 month',
      'kinrel')
    ON CONFLICT ("periodKey") DO NOTHING
    RETURNING * INTO v_season;
  END IF;

  IF v_season IS NULL THEN
    SELECT * INTO v_season FROM "game_seasons" WHERE "periodKey" = v_period;
  END IF;

  v_ends := v_season."endsAt";

  RETURN jsonb_build_object(
    'id', v_season."id",
    'name', v_season."name",
    'periodKey', v_season."periodKey",
    'startsAt', v_season."startsAt",
    'endsAt', v_season."endsAt",
    'daysRemaining', GREATEST(0, EXTRACT(DAY FROM (v_ends - now()))::int));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_current_season(text) TO authenticated;

-- =============================================================================
-- SECTION 13: HOOK INTO fn_end_game (archive BEFORE hard-delete)
-- =============================================================================
-- Every room-cleanup path in the product (30s timers, Back-to-Hub buttons,
-- Play Again, hourly pg_cron safety net) flows through fn_end_game. Running
-- the ecosystem processor here guarantees NO completed match is ever lost,
-- regardless of which client or cron triggers the cleanup.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_end_game(
    p_game_table text,
    p_game_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    -- ── Family Gaming Ecosystem: archive completed matches BEFORE the
    --    hard delete (idempotent no-op for cancelled/abandoned rooms).
    BEGIN
        PERFORM public.fn__archive_family_match(p_game_table, p_game_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ecosystem archive failed for %/%: %', p_game_table, p_game_id, SQLERRM;
    END;

    PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_end_game(text, text) TO authenticated;

-- =============================================================================
-- SECTION 14: CLIENT-CALLABLE MATCH ECOSYSTEM RPC
-- =============================================================================
-- Called by the results screen of any game. If the match reached a terminal
-- state this processes + archives it immediately (so celebration UI shows
-- fresh badges / challenges / milestones) and returns the full summary.
-- Safe to call repeatedly — once archived it returns the stored summary.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_match_ecosystem(
  p_game_table text,
  p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_summary jsonb;
  v_meta jsonb;
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games'
  ) THEN
    RETURN NULL;
  END IF;

  -- Ensure processing has happened (no-op if already archived or not terminal)
  v_summary := public.fn__archive_family_match(p_game_table, p_game_id);

  -- If this call did the processing, return its rich summary directly
  IF v_summary IS NOT NULL THEN
    RETURN v_summary;
  END IF;

  -- Either already archived, or game row not terminal/gone.
  v_meta := public.fn__game_meta() -> p_game_table;

  SELECT jsonb_build_object(
    'matchId', h."id",
    'gameTable', h."gameTable",
    'gameName', COALESCE(v_meta->>'name', h."gameTable"),
    'gameIcon', COALESCE(v_meta->>'icon', '🎮'),
    'familyId', h."familyId",
    'winners', to_jsonb(h."winnerNames"),
    'playerCount', h."playerCount",
    'durationSeconds', h."durationSeconds",
    'archived', true,
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', p."userId", 'userName', p."userName", 'result', p."result"))
      FROM "game_match_players" p WHERE p."matchId" = h."id"
    ), '[]'::jsonb)
  )
  INTO v_summary
  FROM "game_match_history" h
  WHERE h."gameTable" = p_game_table AND h."gameId" = p_game_id;

  RETURN v_summary;  -- NULL when the room was cancelled (never archived)
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_match_ecosystem(text, text) TO authenticated;

-- =============================================================================
-- SECTION 15: SPORTSMANSHIP RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_send_sportsmanship(
  p_match_id text,
  p_game_table text,
  p_family_id text,
  p_to_user_id text,
  p_to_name text DEFAULT NULL,
  p_kind text DEFAULT 'gg',
  p_message text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_id text := auth.uid()::text;
  v_from_name text;
  v_allowed text[] := ARRAY['gg','great_move','well_played','fun_game','good_sport'];
  v_new jsonb := '[]'::jsonb;
  v_created timestamptz;
BEGIN
  IF v_from_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_kind <> ALL(v_allowed) THEN RAISE EXCEPTION 'Unknown sportsmanship kind: %', p_kind; END IF;
  IF v_from_id = p_to_user_id THEN RAISE EXCEPTION 'Cannot cheer yourself'; END IF;
  IF NOT EXISTS (SELECT 1 FROM "game_match_players" WHERE "matchId"=p_match_id AND "userId"=v_from_id) THEN
    RAISE EXCEPTION 'You did not play in this match';
  END IF;

  SELECT COALESCE(MAX("userName"), 'Family Member') INTO v_from_name
  FROM "game_match_players" WHERE "userId" = v_from_id LIMIT 1;

  INSERT INTO "game_sportsmanship_notes"
    ("matchId","gameTable","familyId","fromUserId","fromName","toUserId","toName","kind","message")
  VALUES
    (p_match_id, p_game_table, p_family_id, v_from_id, v_from_name, p_to_user_id, p_to_name, p_kind, p_message)
  ON CONFLICT ("matchId","fromUserId","toUserId") DO UPDATE SET
    "kind" = EXCLUDED."kind",
    "message" = EXCLUDED."message"
  RETURNING "createdAt" INTO v_created;

  IF v_created >= now() - interval '5 seconds' THEN
    -- fresh insert only (repeated sends never inflate counters)
    -- bump counters
    INSERT INTO "game_user_stats" ("userId","familyId","gameTable","sportsmanshipGiven")
    VALUES (v_from_id, p_family_id, '*', 1)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "sportsmanshipGiven" = "game_user_stats"."sportsmanshipGiven" + 1, "updatedAt" = now();

    INSERT INTO "game_user_stats" ("userId","familyId","gameTable","sportsmanshipReceived")
    VALUES (p_to_user_id, p_family_id, '*', 1)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "sportsmanshipReceived" = "game_user_stats"."sportsmanshipReceived" + 1, "updatedAt" = now();

    INSERT INTO "FamilyActivityLog"
      ("id","familyId","actorUserId","actorName","action","description","metadata")
    VALUES (gen_random_uuid()::text, p_family_id, v_from_id, v_from_name,
      'game_sportsmanship',
      format('%s cheered %s: %s', v_from_name, COALESCE(p_to_name,'a family member'),
             CASE p_kind WHEN 'gg' THEN 'good game!' WHEN 'great_move' THEN 'great move!'
                         WHEN 'well_played' THEN 'well played!' WHEN 'fun_game' THEN 'fun game!'
                         ELSE 'good sport!' END),
      jsonb_build_object('matchId', p_match_id, 'kind', p_kind,
                         'toUserId', p_to_user_id, 'toName', p_to_name));

    v_new := public.fn__evaluate_game_badges(v_from_id, p_family_id);
    v_new := v_new || public.fn__evaluate_game_badges(p_to_user_id, p_family_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'newBadges', v_new);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_send_sportsmanship(text, text, text, text, text, text, text) TO authenticated;

-- =============================================================================
-- SECTION 16: LEADERBOARD v2 — weekly / monthly / all-time + per-game
-- =============================================================================
-- Participation-weighted POINTS ordering (win 3 · draw 1 · played 1) so the
-- leaderboard rewards showing up, not just winning — motivating, non-toxic.
-- Losses are never displayed prominently; streaks are celebrated instead.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_leaderboard_v2(
  p_family_id text,
  p_period text DEFAULT 'all_time',   -- weekly | monthly | all_time
  p_game_table text DEFAULT NULL,
  p_limit int DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz := CASE p_period
    WHEN 'weekly' THEN date_trunc('week', now())
    WHEN 'monthly' THEN date_trunc('month', now())
    ELSE '-infinity'::timestamptz END;
  v_rows jsonb;
BEGIN
  IF p_period = 'all_time' THEN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."wins" DESC, t."matches" DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT s."userId",
             COALESCE(u."name", MAX(p."userName"), s."userId") AS "userName",
             u."avatarUrl",
             SUM(s."wins") AS "wins",
             SUM(s."matches") AS "matches",
             SUM(s."draws") AS "draws",
             SUM(s."points") AS "points",
             MAX(st."streakCurrent") AS "streakCurrent",
             MAX(st."streakBest") AS "streakBest",
             MAX(st."sportsmanshipReceived") AS "sportsmanship",
             ROUND(SUM(s."wins")::numeric / NULLIF(SUM(s."matches"),0), 3) AS "winRate"
      FROM "game_user_stats" s
      LEFT JOIN "game_user_stats" st
        ON st."userId" = s."userId" AND st."familyId" = s."familyId" AND st."gameTable" = '*'
      LEFT JOIN "User" u ON u."id" = s."userId"
      LEFT JOIN (
        SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
        WHERE "familyId" = p_family_id GROUP BY "userId"
      ) p ON p."userId" = s."userId"
      WHERE s."familyId" = p_family_id
        AND s."gameTable" <> '*'
        AND (p_game_table IS NULL OR s."gameTable" = p_game_table)
      GROUP BY s."userId", u."name", u."avatarUrl"
      HAVING SUM(s."matches") > 0
      LIMIT LEAST(GREATEST(p_limit,1),100)
    ) t;
  ELSE
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."wins" DESC, t."matches" DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT g."userId",
             COALESCE(u."name", MAX(g."userName"), g."userId") AS "userName",
             u."avatarUrl",
             COUNT(*) FILTER (WHERE g."result"='win') AS "wins",
             COUNT(*) AS "matches",
             COUNT(*) FILTER (WHERE g."result"='draw') AS "draws",
             SUM(CASE g."result" WHEN 'win' THEN 3 WHEN 'loss' THEN 0 ELSE 1 END) AS "points",
             0 AS "streakCurrent",
             0 AS "streakBest",
             0 AS "sportsmanship",
             ROUND(COUNT(*) FILTER (WHERE g."result"='win')::numeric / NULLIF(COUNT(*),0), 3) AS "winRate"
      FROM "game_match_players" g
      LEFT JOIN "User" u ON u."id" = g."userId"
      WHERE g."familyId" = p_family_id
        AND g."finishedAt" >= v_start
        AND (p_game_table IS NULL OR g."gameTable" = p_game_table)
      GROUP BY g."userId", u."name", u."avatarUrl"
      LIMIT LEAST(GREATEST(p_limit,1),100)
    ) t;
  END IF;

  RETURN jsonb_build_object('period', p_period, 'entries', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_leaderboard_v2(text, text, text, int) TO authenticated;

-- =============================================================================
-- SECTION 17: MATCH HISTORY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_match_history(
  p_user_id text,
  p_family_id text,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
  v_total int;
BEGIN
  SELECT COUNT(*) INTO v_total FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id;

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."finishedAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      mine."matchId",
      mine."gameTable",
      public.fn__game_meta() -> mine."gameTable" ->> 'name' AS "gameName",
      public.fn__game_meta() -> mine."gameTable" ->> 'icon' AS "gameIcon",
      mine."result",
      mine."finishedAt",
      h."durationSeconds",
      h."playerCount",
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object('userName', o."userName", 'result', o."result"))
        FROM "game_match_players" o
        WHERE o."matchId" = mine."matchId" AND o."userId" <> p_user_id
      ), '[]'::jsonb) AS "opponents"
    FROM "game_match_players" mine
    JOIN "game_match_history" h ON h."id" = mine."matchId"
    WHERE mine."userId"=p_user_id AND mine."familyId"=p_family_id
    ORDER BY mine."finishedAt" DESC
    OFFSET GREATEST(p_offset,0)
    LIMIT LEAST(GREATEST(p_limit,1),100)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'matches', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_match_history(text, text, int, int) TO authenticated;

-- =============================================================================
-- SECTION 18: FAMILY GAMING ACTIVITY FEED
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_gaming_activity(
  p_family_id text,
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', a."id",
      'actorUserId', a."actorUserId",
      'actorName', a."actorName",
      'action', a."action",
      'description', a."description",
      'metadata', a."metadata",
      'createdAt', a."createdAt")
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

GRANT EXECUTE ON FUNCTION public.fn_get_family_gaming_activity(text, int, int) TO authenticated;

-- =============================================================================
-- SECTION 19: PLAYER GAMING PROFILE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_player_gaming_profile(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overall record;
  v_user record;
  v_uname text;
  v_result jsonb;
BEGIN
  SELECT "id","name","avatarUrl","username" INTO v_user FROM "User" WHERE "id"=p_user_id;

  SELECT COALESCE(MAX("userName"), v_user."name", 'Family Member') INTO v_uname
  FROM "game_match_players" WHERE "userId"=p_user_id LIMIT 1;

  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';

  SELECT jsonb_build_object(
    'userId', p_user_id,
    'userName', v_uname,
    'avatarUrl', v_user."avatarUrl",
    'username', v_user."username",
    'matches', COALESCE(v_overall."matches",0),
    'wins', COALESCE(v_overall."wins",0),
    'losses', COALESCE(v_overall."losses",0),
    'draws', COALESCE(v_overall."draws",0),
    'points', COALESCE(v_overall."points",0),
    'streakCurrent', COALESCE(v_overall."streakCurrent",0),
    'streakBest', COALESCE(v_overall."streakBest",0),
    'sportsmanship', COALESCE(v_overall."sportsmanshipReceived",0),
    'spectated', COALESCE(v_overall."spectated",0),
    'winRate', ROUND(COALESCE(v_overall."wins",0)::numeric / NULLIF(COALESCE(v_overall."matches",0),0), 3),
    'favoriteGame', (
      SELECT jsonb_build_object(
        'gameTable', s."gameTable",
        'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
        'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
        'matches', s."matches",
        'wins', s."wins")
      FROM "game_user_stats" s
      WHERE s."userId"=p_user_id AND s."familyId"=p_family_id
        AND s."gameTable" <> '*' AND s."matches" > 0
      ORDER BY s."matches" DESC LIMIT 1),
    'perGame', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'gameTable', s."gameTable",
        'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
        'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
        'matches', s."matches", 'wins', s."wins", 'losses', s."losses", 'draws', s."draws")
      ORDER BY s."matches" DESC)
      FROM "game_user_stats" s
      WHERE s."userId"=p_user_id AND s."familyId"=p_family_id AND s."gameTable" <> '*'
    ), '[]'::jsonb),
    'badges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
        'description', b."description", 'earnedAt', ub."earnedAt")
      ORDER BY ub."earnedAt" DESC)
      FROM "UserBadge" ub
      JOIN "Badge" b ON b."id" = ub."badgeId"
      WHERE ub."userId"=p_user_id AND COALESCE(ub."familyId",p_family_id)=p_family_id
        AND b."category"='games'
    ), '[]'::jsonb),
    'recentMatches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'gameName', public.fn__game_meta() -> m."gameTable" ->> 'name',
        'gameIcon', public.fn__game_meta() -> m."gameTable" ->> 'icon',
        'result', m."result", 'finishedAt', m."finishedAt")
      ORDER BY m."finishedAt" DESC)
      FROM (SELECT * FROM "game_match_players"
            WHERE "userId"=p_user_id AND "familyId"=p_family_id
            ORDER BY "finishedAt" DESC LIMIT 5) m
    ), '[]'::jsonb),
    'recentActivity', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'action', a."action", 'description', a."description", 'createdAt', a."createdAt")
      ORDER BY a."createdAt" DESC)
      FROM (SELECT * FROM "FamilyActivityLog"
            WHERE "familyId"=p_family_id AND "actorUserId"=p_user_id AND "action" LIKE 'game_%'
            ORDER BY "createdAt" DESC LIMIT 8) a
    ), '[]'::jsonb),
    'rank', (
      SELECT COUNT(*) + 1 FROM (
        SELECT "userId", SUM("points") AS pts FROM "game_user_stats"
        WHERE "familyId"=p_family_id AND "gameTable" <> '*'
        GROUP BY "userId"
      ) t WHERE t."userId" <> p_user_id AND t.pts > COALESCE(v_overall."points",0)
    ),
    'daysActiveThisWeek', (
      SELECT COUNT(DISTINCT date("finishedAt")) FROM "game_match_players"
      WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= date_trunc('week', now())
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_player_gaming_profile(text, text) TO authenticated;

-- =============================================================================
-- SECTION 20: SMART MATCH SUGGESTIONS
-- =============================================================================
-- Combines live presence (who's online right now) with play history (who you
-- play with most + everyone's favorite games) into actionable suggestions.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_smart_match_suggestions(
  p_family_id text,
  p_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_online jsonb;
  v_suggestions jsonb := '[]'::jsonb;
  v_member record;
  v_game text;
  v_game_name text;
  v_game_icon text;
  v_games_together int;
  v_meta jsonb := public.fn__game_meta();
BEGIN
  -- Online members (last 5 min, excluding self)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'userId', mp."userId",
    'userName', COALESCE(u."name", 'Family Member'),
    'avatarUrl', u."avatarUrl",
    'lastSeenAt', mp."lastSeenAt")), '[]'::jsonb)
  INTO v_online
  FROM "MemberPresence" mp
  LEFT JOIN "User" u ON u."id" = mp."userId"
  WHERE mp."familyId" = p_family_id
    AND mp."userId" <> p_user_id
    AND COALESCE(mp."status",'') <> 'away'
    AND mp."lastSeenAt" >= now() - interval '5 minutes'
  LIMIT 6;

  FOR v_member IN
    SELECT * FROM jsonb_to_recordset(v_online) AS x("userId" text, "userName" text)
  LOOP
    -- Games you two played together most
    SELECT mine."gameTable", COUNT(*) INTO v_game, v_games_together
    FROM "game_match_players" mine
    JOIN "game_match_players" other
      ON other."matchId" = mine."matchId" AND other."userId" = v_member."userId"
    WHERE mine."userId" = p_user_id AND mine."familyId" = p_family_id
    GROUP BY mine."gameTable"
    ORDER BY 2 DESC
    LIMIT 1;

    IF v_game IS NULL THEN
      -- Their most-played game in this family
      SELECT s."gameTable" INTO v_game
      FROM "game_user_stats" s
      WHERE s."userId" = v_member."userId" AND s."familyId" = p_family_id
        AND s."gameTable" <> '*' AND s."matches" > 0
      ORDER BY s."matches" DESC
      LIMIT 1;
      v_games_together := 0;
    END IF;

    IF v_game IS NULL THEN
      -- Fall back to the family's most played game
      SELECT "gameTable" INTO v_game FROM "game_match_players"
      WHERE "familyId" = p_family_id
      GROUP BY "gameTable" ORDER BY COUNT(*) DESC LIMIT 1;
      v_games_together := 0;
    END IF;

    v_game_name := COALESCE(v_meta -> v_game ->> 'name', 'a game');
    v_game_icon := COALESCE(v_meta -> v_game ->> 'icon', '🎮');

    v_suggestions := v_suggestions || jsonb_build_object(
      'userId', v_member."userId",
      'userName', v_member."userName",
      'gameTable', v_game,
      'gameName', v_game_name,
      'gameIcon', v_game_icon,
      'gamesTogether', v_games_together,
      'reason', CASE WHEN v_games_together > 0
        THEN format('You two have played %s together %s times', v_game_name, v_games_together)
        ELSE format('%s is online — %s is their favorite', v_member."userName", v_game_name) END);
  END LOOP;

  RETURN jsonb_build_object(
    'onlineCount', jsonb_array_length(v_online),
    'online', v_online,
    'suggestions', v_suggestions);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_smart_match_suggestions(text, text) TO authenticated;

-- =============================================================================
-- SECTION 21: FAMILY GAMING MILESTONES (read)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_gaming_milestones(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total int := 0;
  v_distinct int := 0;
  v_last_match timestamptz;
BEGIN
  SELECT COALESCE("totalMatches",0), COALESCE("distinctGames",0), "lastMatchAt"
    INTO v_total, v_distinct, v_last_match
  FROM "game_family_stats" WHERE "familyId" = p_family_id;

  RETURN jsonb_build_object(
    'totalMatches', v_total,
    'distinctGames', v_distinct,
    'lastMatchAt', v_last_match,
    'milestones', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'milestone', m."milestone",
        'reachedAt', m."reachedAt",
        'celebrated', m."celebrated"))
      FROM "FamilyMilestone" m
      WHERE m."familyId" = p_family_id
        AND (m."milestone" LIKE 'games_%' OR m."milestone" = 'first_family_match')
    ), '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_gaming_milestones(text) TO authenticated;

-- =============================================================================
-- SECTION 22: FAMILY CHALLENGES (read)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_challenges(
  p_family_id text,
  p_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_key text := to_char(now(), 'IYYY-"W"IW');
  v_month_key text := to_char(now(), 'YYYY-MM');
BEGIN
  -- Ensure progress rows exist for this period (lazy seeding)
  PERFORM public.fn__advance_challenges(p_user_id, p_family_id);

  RETURN jsonb_build_object(
    'weekKey', v_week_key,
    'monthKey', v_month_key,
    'challenges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', t."slug", 'title', t."title", 'description', t."description",
        'cadence', t."cadence", 'icon', t."icon", 'target', t."target",
        'rewardPoints', t."rewardPoints", 'familyWide', t."familyWide",
        'progress', COALESCE(cp."progress", 0),
        'completedAt', cp."completedAt")
      ORDER BY t."sortOrder")
      FROM "game_challenge_templates" t
      LEFT JOIN "game_challenge_progress" cp
        ON cp."templateSlug" = t."slug"
       AND cp."familyId" = p_family_id
       AND cp."periodKey" = CASE WHEN t."cadence"='weekly' THEN v_week_key ELSE v_month_key END
       AND cp."userId" = CASE WHEN t."familyWide" THEN '*' ELSE p_user_id END
      WHERE t."isActive"
    ), '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_challenges(text, text) TO authenticated;

-- =============================================================================
-- SECTION 23: GAMING DASHBOARD (single aggregate call for the hub)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_gaming_dashboard(
  p_family_id text,
  p_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_overall record;
  v_season jsonb;
  v_rank int;
  v_family_total int;
BEGIN
  PERFORM public.fn__advance_challenges(p_user_id, p_family_id);
  v_season := public.fn_get_current_season(p_family_id);

  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';

  SELECT COUNT(*)+1 INTO v_rank FROM (
    SELECT "userId", SUM("points") AS pts FROM "game_user_stats"
    WHERE "familyId"=p_family_id AND "gameTable" <> '*'
    GROUP BY "userId" HAVING SUM("points") > COALESCE(v_overall."points",0)
  ) t;

  SELECT COALESCE("totalMatches",0) INTO v_family_total
  FROM "game_family_stats" WHERE "familyId"=p_family_id;

  SELECT jsonb_build_object(
    'familyTotalMatches', v_family_total,
    'familyDistinctGames', (
      SELECT COALESCE("distinctGames",0) FROM "game_family_stats" WHERE "familyId"=p_family_id),
    'me', jsonb_build_object(
      'userId', p_user_id,
      'matches', COALESCE(v_overall."matches",0),
      'wins', COALESCE(v_overall."wins",0),
      'points', COALESCE(v_overall."points",0),
      'streakCurrent', COALESCE(v_overall."streakCurrent",0),
      'rank', v_rank),
    'season', v_season,
    'challenges', (public.fn_get_family_challenges(p_family_id, p_user_id) -> 'challenges'),
    'leaderboard', (public.fn_get_family_leaderboard_v2(p_family_id, 'all_time', NULL, 5) -> 'entries'),
    'weeklyLeaderboard', (public.fn_get_family_leaderboard_v2(p_family_id, 'weekly', NULL, 5) -> 'entries'),
    'activity', public.fn_get_family_gaming_activity(p_family_id, 6),
    'suggestions', (public.fn_get_smart_match_suggestions(p_family_id, p_user_id) -> 'suggestions'),
    'milestones', (public.fn_get_family_gaming_milestones(p_family_id) -> 'milestones'),
    'seasonStandings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', g."userId",
        'userName', COALESCE(u."name", mp."userName", g."userId"),
        'points', g."points", 'wins', g."wins", 'gamesPlayed', g."gamesPlayed")
      ORDER BY g."points" DESC)
      FROM "game_season_standings" g
      LEFT JOIN "User" u ON u."id" = g."userId"
      LEFT JOIN (SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
                 WHERE "familyId"=p_family_id GROUP BY "userId") mp ON mp."userId" = g."userId"
      WHERE g."familyId" = p_family_id AND g."seasonId" = (v_season->>'id')
    ), '[]'::jsonb),
    'myBadges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
        'description', b."description", 'earnedAt', ub."earnedAt")
      ORDER BY ub."earnedAt" DESC)
      FROM "UserBadge" ub
      JOIN "Badge" b ON b."id" = ub."badgeId"
      WHERE ub."userId"=p_user_id AND COALESCE(ub."familyId",p_family_id)=p_family_id
        AND b."category"='games'
    ), '[]'::jsonb),
    'allGameBadges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
        'description', b."description", 'threshold', b."threshold",
        'earned', EXISTS (SELECT 1 FROM "UserBadge" ub2
                          WHERE ub2."badgeId"=b."id" AND ub2."userId"=p_user_id
                            AND COALESCE(ub2."familyId",p_family_id)=p_family_id))
      ORDER BY b."tier", b."name")
      FROM "Badge" b WHERE b."category"='games'
    ), '[]'::jsonb),
    'familyMembers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', u."id", 'userName', COALESCE(u."name", 'Family Member'),
        'avatarUrl', u."avatarUrl", 'points', COALESCE(s."points",0),
        'matches', COALESCE(s."matches",0))
      ORDER BY COALESCE(s."points",0) DESC)
      FROM "FamilyMember" fm
      JOIN "User" u ON u."id" = fm."userId"
      LEFT JOIN "game_user_stats" s
        ON s."userId" = fm."userId" AND s."familyId" = fm."familyId" AND s."gameTable"='*'
      WHERE fm."familyId" = p_family_id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_gaming_dashboard(text, text) TO authenticated;

-- =============================================================================
-- SECTION 24: REWRITE BROKEN LEGACY RPCs (they read hard-deleted rows)
-- =============================================================================

-- fn_get_user_win_stats — was reading game_participants (wiped by fn_end_game)
CREATE OR REPLACE FUNCTION public.fn_get_user_win_stats(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overall record;
  v_monthly_wins int;
BEGIN
  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';

  SELECT COUNT(*) INTO v_monthly_wins FROM "game_match_players"
  WHERE "userId"=p_user_id AND "result"='win'
    AND "finishedAt" >= date_trunc('month', now());

  RETURN jsonb_build_object(
    'totalWins', COALESCE(v_overall."wins",0),
    'monthlyWins', v_monthly_wins,
    'familyWins', COALESCE(v_overall."wins",0),
    'familyWinNumber', COALESCE(v_overall."wins",0) + 1,
    'totalGames', COALESCE(v_overall."matches",0),
    'currentStreak', COALESCE(v_overall."streakCurrent",0));
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_get_user_win_stats(text, text) TO authenticated;

-- fn_get_family_leaderboard — same fix, persistent data, same signature
CREATE OR REPLACE FUNCTION fn_get_family_leaderboard(
  p_family_id text,
  p_game_table text DEFAULT NULL
)
RETURNS TABLE(
  "userId" text,
  "userName" text,
  "wins" bigint,
  "losses" bigint,
  "draws" bigint,
  "gamesPlayed" bigint,
  "winRate" numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s."userId",
    COALESCE(u."name", MAX(p."userName"), s."userId") AS "userName",
    SUM(s."wins")::bigint AS "wins",
    SUM(s."losses")::bigint AS "losses",
    SUM(s."draws")::bigint AS "draws",
    SUM(s."matches")::bigint AS "gamesPlayed",
    ROUND(SUM(s."wins")::numeric / NULLIF(SUM(s."matches"),0)::numeric, 3) AS "winRate"
  FROM "game_user_stats" s
  LEFT JOIN "User" u ON u."id" = s."userId"
  LEFT JOIN (
    SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
    WHERE "familyId" = p_family_id GROUP BY "userId"
  ) p ON p."userId" = s."userId"
  WHERE s."familyId" = p_family_id
    AND s."gameTable" <> '*'
    AND (p_game_table IS NULL OR s."gameTable" = p_game_table)
  GROUP BY s."userId", u."name"
  HAVING SUM(s."matches") > 0
  ORDER BY SUM(s."wins") DESC, "winRate" DESC, SUM(s."matches") DESC;
$$;
GRANT EXECUTE ON FUNCTION fn_get_family_leaderboard(text, text) TO authenticated;

-- fn_get_recent_playmates — persistent history
CREATE OR REPLACE FUNCTION fn_get_recent_playmates(
  p_user_id text,
  p_family_id text,
  p_limit int DEFAULT 5,
  p_days_back int DEFAULT 30
)
RETURNS TABLE(
  "userId" text,
  "userName" text,
  "lastPlayedAt" timestamptz,
  "gamesPlayed" bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    other."userId",
    MAX(other."userName") AS "userName",
    MAX(other."finishedAt") AS "lastPlayedAt",
    COUNT(DISTINCT other."matchId") AS "gamesPlayed"
  FROM "game_match_players" mine
  INNER JOIN "game_match_players" other
    ON other."matchId" = mine."matchId"
    AND other."userId" <> p_user_id
  WHERE mine."userId" = p_user_id
    AND mine."familyId" = p_family_id
    AND other."finishedAt" >= now() - (p_days_back || ' days')::interval
    AND other."familyId" = p_family_id
  GROUP BY other."userId"
  ORDER BY "lastPlayedAt" DESC
  LIMIT LEAST(p_limit, 20);
$$;
GRANT EXECUTE ON FUNCTION fn_get_recent_playmates(text, text, int, int) TO authenticated;

-- =============================================================================
-- SECTION 25: REALTIME publication for live dashboards
-- =============================================================================

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_match_history";
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_challenge_progress";
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE "game_season_standings";
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE "FamilyActivityLog";
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

ALTER TABLE "game_match_history" REPLICA IDENTITY FULL;
ALTER TABLE "game_challenge_progress" REPLICA IDENTITY FULL;
ALTER TABLE "FamilyActivityLog" REPLICA IDENTITY FULL;
