-- 20260920160000_mind_match_game.sql
-- Mind Match — "Think Like The Group" social party game. 2–8 players.
--
-- Each round, a question appears (e.g. "Name a fruit"). Players submit
-- answers privately. When all answers are locked (or the timer expires),
-- answers are grouped by similarity. Players who matched the most popular
-- answer earn the most points. After N rounds the player with the most
-- points wins.
--
-- Architecture reuses the hidden-submission pattern from impostor +
-- secret_heist: answers live in a separate table with RLS that hides
-- other players' rows until the round resolves. The boardState JSONB
-- on the games row contains only aggregate counters + the resolved
-- answer groups — never the pending answers.
--
-- Question uniqueness: a question_history table tracks which questions
-- each family has seen. The pick_question RPC prioritizes unseen
-- questions and never repeats within 365 days.

CREATE TABLE IF NOT EXISTS "mind_match_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "hostUserId" TEXT NOT NULL,
  "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT,
  status TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "currentPlayerId" TEXT,
  "currentTurnIndex" INTEGER NOT NULL DEFAULT 0,
  "turnEndsAt" TIMESTAMPTZ,
  "boardState" JSONB,
  "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason" TEXT,
  "startedAt" TIMESTAMPTZ,
  "completedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ,
  "cancelledAt" TIMESTAMPTZ,
  "closedAt" TIMESTAMPTZ,
  "hostReady" BOOLEAN DEFAULT true,
  "spectatorsEnabled" BOOLEAN NOT NULL DEFAULT true,
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  -- Game-specific config
  "totalRounds" INTEGER NOT NULL DEFAULT 10,
  "answerSeconds" INTEGER NOT NULL DEFAULT 30,
  "categories" JSONB NOT NULL DEFAULT '["everyday","fun","family","global"]'::jsonb,
  "familyQuestionsEnabled" BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_mmg_family ON "mind_match_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "mind_match_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "mind_match_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_mmp_game ON "mind_match_players" ("gameId", "joinedAt");

-- Hidden-answer table. RLS exposes ONLY the caller's own row to each
-- player; the resolution RPC reads all rows for the round and updates
-- the games.boardState with the *resolved* groups.
CREATE TABLE IF NOT EXISTS "mind_match_answers" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "mind_match_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "roundNumber" INTEGER NOT NULL,
  "answer" TEXT NOT NULL,
  "normalizedAnswer" TEXT NOT NULL,
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "userId", "roundNumber")
);
CREATE INDEX IF NOT EXISTS idx_mma_game_round ON "mind_match_answers" ("gameId", "roundNumber");

-- ─────────────────────────────────────────────────────────────────
-- Question pool — seeded with 200+ questions across 4 categories.
-- Supports adding more via INSERT.
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "mind_match_questions" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  category TEXT NOT NULL,           -- everyday | fun | family | global
  prompt TEXT NOT NULL,             -- "Name a fruit"
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  active BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_mmq_category ON "mind_match_questions" (category, active);

-- Tracks which questions each family has seen (for the 365-day no-repeat rule).
CREATE TABLE IF NOT EXISTS "mind_match_question_history" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "questionId" TEXT NOT NULL REFERENCES "mind_match_questions"(id) ON DELETE CASCADE,
  "gameId" TEXT NOT NULL,
  "shownAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("familyId", "questionId")
);
CREATE INDEX IF NOT EXISTS idx_mmh_family_time ON "mind_match_question_history" ("familyId", "shownAt" DESC);

-- ─────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "mind_match_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mind_match_games_select_family" ON "mind_match_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "mind_match_games_insert_host" ON "mind_match_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "mind_match_games_update_family" ON "mind_match_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "mind_match_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mind_match_players_select_family" ON "mind_match_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "mind_match_games" g WHERE g.id = "mind_match_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "mind_match_players_insert_self_or_host" ON "mind_match_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "mind_match_games" g WHERE g.id = "mind_match_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "mind_match_players_update_self" ON "mind_match_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "mind_match_players_delete_self" ON "mind_match_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "mind_match_answers" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mind_match_answers_select_own" ON "mind_match_answers" FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "mind_match_answers_insert_own" ON "mind_match_answers" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "mind_match_answers_update_own" ON "mind_match_answers" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "mind_match_answers_delete_own" ON "mind_match_answers" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "mind_match_questions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mind_match_questions_select_all" ON "mind_match_questions" FOR SELECT TO authenticated USING (active = true);

ALTER TABLE "mind_match_question_history" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mind_match_question_history_select_family" ON "mind_match_question_history" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "mind_match_question_history_insert_family" ON "mind_match_question_history" FOR INSERT TO authenticated WITH CHECK (public.fn_user_is_family_member("familyId"));

ALTER PUBLICATION supabase_realtime ADD TABLE "mind_match_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "mind_match_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "mind_match_answers";
ALTER TABLE "mind_match_games" REPLICA IDENTITY FULL;
ALTER TABLE "mind_match_players" REPLICA IDENTITY FULL;
ALTER TABLE "mind_match_answers" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_pick_question — pick an unseen question for the family.
-- Prioritizes questions not shown in the last 365 days. If all questions
-- have been seen, falls back to the least-recently-shown.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_pick_question(
  p_family_id text,
  p_categories text[],
  p_game_id text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_question_id text;
  v_cat_filter text;
BEGIN
  -- Build category filter
  IF p_categories IS NULL OR array_length(p_categories, 1) IS NULL THEN
    v_cat_filter := '';
  ELSE
    v_cat_filter := format(' AND category = ANY(ARRAY[%s])',
      array_to_string(ARRAY(SELECT quote_literal(c) FROM unnest(p_categories) AS c), ','));
  END IF;

  -- First, try to find a question NOT in the family's history (last 365 days)
  EXECUTE format(
    'SELECT q.id FROM mind_match_questions q
     WHERE q.active = true %s
       AND q.id NOT IN (
         SELECT h."questionId" FROM mind_match_question_history h
         WHERE h."familyId" = $1
           AND h."shownAt" > now() - interval ''365 days''
       )
     ORDER BY random()
     LIMIT 1', v_cat_filter)
  USING p_family_id
  INTO v_question_id;

  -- If all questions have been seen, fall back to least-recently-shown
  IF v_question_id IS NULL THEN
    EXECUTE format(
      'SELECT q.id FROM mind_match_questions q
       WHERE q.active = true %s
       ORDER BY (
         SELECT COALESCE(MAX(h."shownAt"), ''1970-01-01''::timestamptz)
         FROM mind_match_question_history h
         WHERE h."familyId" = $1 AND h."questionId" = q.id
       ) ASC, random()
       LIMIT 1', v_cat_filter)
    USING p_family_id
    INTO v_question_id;
  END IF;

  -- Record the question as shown for this family
  IF v_question_id IS NOT NULL THEN
    INSERT INTO mind_match_question_history ("familyId", "questionId", "gameId")
    VALUES (p_family_id, v_question_id, p_game_id)
    ON CONFLICT ("familyId", "questionId") DO UPDATE SET "shownAt" = now(), "gameId" = p_game_id;
  END IF;

  RETURN v_question_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_pick_question(text, text[], text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_start — host starts the match.
-- Initializes boardState with N players and round 1.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_players jsonb;
  v_count int;
  v_order text[];
  v_i int;
  v_board jsonb;
  v_players_arr jsonb;
  v_answer_seconds int;
  v_question_id text;
  v_question record;
  v_categories text[];
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "mind_match_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 2 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  -- Build players array with 0 score
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i,
      'userId', v_players->v_i->>'userId',
      'name', v_players->v_i->>'userName',
      'score', 0,
      'lastRoundPoints', 0,
      'streak', 0,
      'perfectMatches', 0
    );
  END LOOP;
  v_answer_seconds := v_game."answerSeconds";
  -- Convert categories JSONB to text[]
  SELECT COALESCE(array_agg(c::text), ARRAY[]::text[]) INTO v_categories
  FROM jsonb_array_elements_text(v_game."categories") AS c;
  -- Pick first question
  v_question_id := public.fn_mindmatch_pick_question(v_game."familyId", v_categories, p_game_id);
  IF v_question_id IS NULL THEN
    -- No questions available — shouldn't happen, but fall back
    RETURN jsonb_build_object('ok', false, 'reason', 'no_questions_available');
  END IF;
  SELECT * INTO v_question FROM mind_match_questions WHERE id = v_question_id;
  v_board := jsonb_build_object(
    'playerCount', v_count,
    'totalRounds', v_game."totalRounds",
    'answerSeconds', v_answer_seconds,
    'categories', v_game."categories",
    'familyQuestionsEnabled', v_game."familyQuestionsEnabled",
    'currentRound', 1,
    'rounds', jsonb_build_array(jsonb_build_object(
      'roundNumber', 1,
      'phase', 'answering',
      'questionId', v_question_id,
      'questionPrompt', v_question.prompt,
      'questionCategory', v_question.category,
      'lockedCount', 0,
      'answerGroups', '[]'::jsonb,
      'crowdFavorite', null,
      'perfectMatch', false,
      'pointsAwarded', '[]'::jsonb
    )),
    'players', v_players_arr,
    'status', 'in_progress',
    'winner', -1
  );
  UPDATE "mind_match_games" SET
    status = 'in_progress',
    "playerOrder" = to_jsonb(v_order),
    "currentPlayerId" = v_order[1],
    "boardState" = v_board,
    "startedAt" = now(),
    "turnEndsAt" = now() + (v_answer_seconds || ' seconds')::interval,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_start(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_normalize_answer — lowercase + trim + collapse spaces.
-- This is the matching key.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_normalize_answer(p_answer text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(btrim(regexp_replace(p_answer, '\s+', ' ', 'g')))
$$;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_submit_answer — a player submits their answer.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_submit_answer(
  p_game_id text,
  p_answer text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_idx int;
  v_player_count int;
  v_existing record;
  v_answer_seconds int;
  v_locked_count int;
  v_normalized text;
  v_trimmed text;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'answering' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_answering_phase'); END IF;

  v_trimmed := btrim(p_answer);
  IF v_trimmed = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'empty_answer'); END IF;
  IF length(v_trimmed) > 60 THEN RETURN jsonb_build_object('ok', false, 'reason', 'answer_too_long'); END IF;
  v_normalized := public.fn_mindmatch_normalize_answer(v_trimmed);

  -- Insert or update (player can change their answer during answering phase)
  SELECT * INTO v_existing FROM "mind_match_answers"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "mind_match_answers" ("gameId","userId","roundNumber","answer","normalizedAnswer")
    VALUES (p_game_id, auth.uid()::text, v_current, v_trimmed, v_normalized);
  ELSE
    UPDATE "mind_match_answers" SET "answer" = v_trimmed, "normalizedAnswer" = v_normalized, "submittedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  SELECT count(*) INTO v_locked_count FROM "mind_match_answers"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current;

  v_round := jsonb_set(v_round, '{lockedCount}', v_locked_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  v_player_count := (v_board->>'playerCount')::int;
  v_answer_seconds := (v_board->>'answerSeconds')::int;

  -- Auto-resolve when all players have locked
  IF v_locked_count >= v_player_count THEN
    v_round := jsonb_set(v_round, '{phase}', '"resolving"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "mind_match_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_mindmatch_resolve(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "mind_match_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_submit_answer(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_resolve — group answers by normalized form, calculate
-- matches, award points. Scoring:
--   - Each player in a group of size N gets N*5 points (so matching 3 people = 15)
--   - Solo answers (group of 1) get 2 points
--   - Perfect Match (everyone same): +20 bonus to everyone
--   - Crowd Favorite (largest group, tie broken by alphabetical): members get +5 bonus
--   - Streak: 2+ consecutive matched rounds = +5 per streak level
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_resolve(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_total_rounds int;
  v_players jsonb;
  v_answer_seconds int;
  v_answer_rec record;
  v_categories text[];
  v_answer_groups jsonb := '[]'::jsonb;
  v_group_obj jsonb;
  v_normalized text;
  v_display_answer text;
  v_user_ids text[];
  v_user_names text[];
  v_player_indices int[];
  v_group_size int;
  v_max_group_size int := 0;
  v_crowd_favorite text;
  v_perfect_match boolean := false;
  v_points_arr jsonb := '[]'::jsonb;
  v_points int;
  v_player_idx int;
  v_player_score int;
  v_player_streak int;
  v_player_perfect int;
  v_last_round_points int;
  v_matched_this_round boolean;
  v_i int;
  v_question_id text;
  v_new_round jsonb;
  v_new_question_id text;
  v_new_question record;
  v_max_score int;
  v_winner_idx int;
  v_tie boolean;
  v_s int;
  v_group_count int;
  v_crowd_bonus boolean;
  v_perfect_bonus boolean;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_players := v_board->'players';
  v_answer_seconds := (v_board->>'answerSeconds')::int;

  -- ── Group answers by normalized form ──
  -- We use a temp table to aggregate
  CREATE TEMP TABLE IF NOT EXISTS _mm_groups (
    normalized text,
    display_answer text,
    user_ids text[],
    user_names text[],
    player_indices int[],
    group_size int
  ) ON COMMIT DROP;
  DELETE FROM _mm_groups;

  FOR v_answer_rec IN SELECT * FROM "mind_match_answers" WHERE "gameId" = p_game_id AND "roundNumber" = v_current LOOP
    v_player_idx := (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_answer_rec."userId");
    -- Try to merge into existing group
    UPDATE _mm_groups
    SET user_ids = array_append(user_ids, v_answer_rec."userId"),
        user_names = array_append(user_names, (SELECT name FROM jsonb_array_elements(v_players) WITH ORDINALITY AS t(p, i) WHERE i - 1 = v_player_idx LIMIT 1)->>'name'),
        player_indices = array_append(player_indices, v_player_idx),
        group_size = group_size + 1,
        display_answer = CASE
          WHEN length(v_answer_rec."answer") < length(display_answer) THEN v_answer_rec."answer"
          ELSE display_answer
        END
    WHERE normalized = v_answer_rec."normalizedAnswer";
    IF NOT FOUND THEN
      INSERT INTO _mm_groups (normalized, display_answer, user_ids, user_names, player_indices, group_size)
      VALUES (
        v_answer_rec."normalizedAnswer",
        v_answer_rec."answer",
        ARRAY[v_answer_rec."userId"],
        ARRAY[(SELECT name FROM jsonb_array_elements(v_players) WITH ORDINALITY AS t(p, i) WHERE i - 1 = v_player_idx LIMIT 1)->>'name'],
        ARRAY[v_player_idx],
        1
      );
    END IF;
  END LOOP;

  -- ── Build answer groups JSONB (sorted by group_size desc) ──
  v_max_group_size := 0;
  FOR v_group_obj IN
    SELECT jsonb_build_object(
      'answer', g.display_answer,
      'normalizedAnswer', g.normalized,
      'userIds', to_jsonb(g.user_ids),
      'userNames', to_jsonb(g.user_names),
      'playerIndices', to_jsonb(g.player_indices),
      'size', g.group_size
    )
    FROM _mm_groups g
    ORDER BY g.group_size DESC, g.display_answer ASC
  LOOP
    v_answer_groups := v_answer_groups || v_group_obj;
    v_group_size := (v_group_obj->>'size')::int;
    IF v_group_size > v_max_group_size THEN
      v_max_group_size := v_group_size;
    END IF;
  END LOOP;

  -- ── Perfect Match: everyone gave the same answer ──
  v_perfect_match := (v_max_group_size = v_player_count AND v_player_count > 1);

  -- ── Crowd Favorite: the largest group (first one if tie) ──
  IF v_max_group_size >= 2 THEN
    v_crowd_favorite := v_answer_groups->0->>'answer';
  ELSE
    v_crowd_favorite := null;
  END IF;

  -- ── Award points ──
  -- For each player, find their group and award points
  v_points_arr := '[]'::jsonb;
  FOR v_i IN 0..v_player_count - 1 LOOP
    v_matched_this_round := false;
    v_points := 0;
    v_crowd_bonus := false;
    v_perfect_bonus := false;

    -- Find the group this player is in
    SELECT group_size INTO v_group_size FROM _mm_groups WHERE v_i = ANY(player_indices);
    IF v_group_size IS NOT NULL THEN
      v_matched_this_round := v_group_size >= 2;
      IF v_group_size >= 2 THEN
        -- Matched: group_size * 5 points
        v_points := v_group_size * 5;
      ELSE
        -- Solo answer: 2 points
        v_points := 2;
      END IF;

      -- Crowd favorite bonus
      IF v_crowd_favorite IS NOT NULL AND v_group_size = v_max_group_size AND v_max_group_size >= 2 THEN
        v_points := v_points + 5;
        v_crowd_bonus := true;
      END IF;

      -- Perfect match bonus
      IF v_perfect_match THEN
        v_points := v_points + 20;
        v_perfect_bonus := true;
      END IF;
    END IF;

    -- Streak bonus: if player matched this round AND matched last round, +5 per streak level
    v_player_streak := (v_players->v_i->>'streak')::int;
    IF v_matched_this_round THEN
      v_player_streak := v_player_streak + 1;
      IF v_player_streak >= 2 THEN
        v_points := v_points + (v_player_streak - 1) * 5;
      END IF;
    ELSE
      v_player_streak := 0;
    END IF;

    -- Update player score
    v_player_score := (v_players->v_i->>'score')::int + v_points;
    v_player_perfect := (v_players->v_i->>'perfectMatches')::int + (CASE WHEN v_perfect_bonus THEN 1 ELSE 0 END);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'score'], v_player_score::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'lastRoundPoints'], v_points::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'streak'], v_player_streak::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'perfectMatches'], v_player_perfect::text::jsonb);

    -- Record points awarded
    v_points_arr := v_points_arr || jsonb_build_object(
      'playerIndex', v_i,
      'points', v_points,
      'matched', v_matched_this_round,
      'groupSize', v_group_size,
      'crowdBonus', v_crowd_bonus,
      'perfectBonus', v_perfect_bonus,
      'streak', v_player_streak
    );
  END LOOP;

  -- ── Update round with resolved state ──
  v_round := v_board->'rounds'->(v_current - 1);
  v_round := jsonb_set(v_round, '{phase}', '"revealing"');
  v_round := jsonb_set(v_round, '{answerGroups}', v_answer_groups);
  v_round := jsonb_set(v_round, '{crowdFavorite}', to_jsonb(v_crowd_favorite));
  v_round := jsonb_set(v_round, '{perfectMatch}', to_jsonb(v_perfect_match));
  v_round := jsonb_set(v_round, '{pointsAwarded}', v_points_arr);

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  v_board := jsonb_set(v_board, '{players}', v_players);

  UPDATE "mind_match_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  -- Clean up temp table
  DROP TABLE IF EXISTS _mm_groups;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_resolve(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_advance — advance phase (revealing → next round or finish)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_advance(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb;
  v_current int; v_player_count int; v_total_rounds int; v_answer_seconds int;
  v_categories text[];
  v_new_question_id text; v_new_question record; v_new_round jsonb;
  v_max_score int; v_winner_idx int; v_tie boolean; v_s int; v_i int;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_answer_seconds := (v_board->>'answerSeconds')::int;
  v_round := v_board->'rounds'->(v_current - 1);

  IF v_round->>'phase' = 'answering' THEN
    -- Timer expired during answering — auto-resolve with whoever has locked
    PERFORM public.fn_mindmatch_resolve(p_game_id);
    RETURN jsonb_build_object('ok', true, 'auto_resolved', true);
  ELSIF v_round->>'phase' = 'revealing' THEN
    -- Advance to next round, or finish
    IF v_current >= v_total_rounds THEN
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_max_score := -1; v_winner_idx := -1; v_tie := false;
      FOR v_i IN 0..v_player_count - 1 LOOP
        v_s := (v_board->'players'->v_i->>'score')::int;
        IF v_s > v_max_score THEN v_max_score := v_s; v_winner_idx := v_i; v_tie := false;
        ELSIF v_s = v_max_score THEN v_tie := true; END IF;
      END LOOP;
      v_board := jsonb_set(v_board, '{winner}', v_winner_idx::text::jsonb);
      UPDATE "mind_match_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN NOT v_tie AND v_winner_idx >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_idx::text) ELSE '[]'::jsonb END,
        "endReason" = 'most_points', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    ELSE
      -- Pick next question
      SELECT COALESCE(array_agg(c::text), ARRAY[]::text[]) INTO v_categories
      FROM jsonb_array_elements_text(v_board->'categories') AS c;
      v_new_question_id := public.fn_mindmatch_pick_question(v_game."familyId", v_categories, p_game_id);
      IF v_new_question_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_questions_available');
      END IF;
      SELECT * INTO v_new_question FROM mind_match_questions WHERE id = v_new_question_id;
      v_new_round := jsonb_build_object(
        'roundNumber', v_current + 1,
        'phase', 'answering',
        'questionId', v_new_question_id,
        'questionPrompt', v_new_question.prompt,
        'questionCategory', v_new_question.category,
        'lockedCount', 0,
        'answerGroups', '[]'::jsonb,
        'crowdFavorite', null,
        'perfectMatch', false,
        'pointsAwarded', '[]'::jsonb
      );
      v_rounds := v_board->'rounds' || v_new_round;
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      v_board := jsonb_set(v_board, '{currentRound}', (v_current + 1)::text::jsonb);
      UPDATE "mind_match_games" SET "boardState" = v_board,
        "turnEndsAt" = now() + (v_answer_seconds || ' seconds')::interval,
        "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true);
    END IF;
  ELSIF v_round->>'phase' = 'resolving' THEN
    RETURN jsonb_build_object('ok', true);
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_advance(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_tick — 2s watchdog. Auto-advances on timer expiry.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "mind_match_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN
    PERFORM public.fn_mindmatch_advance(p_game_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_mindmatch_leave
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mindmatch_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "mind_match_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "mind_match_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "mind_match_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "mind_match_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mindmatch_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__mindmatch_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('mind_match_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'mindmatch archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_mindmatch_archive ON "mind_match_games";
CREATE TRIGGER trg_mindmatch_archive AFTER UPDATE ON "mind_match_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__mindmatch_on_complete();

-- ─────────────────────────────────────────────────────────────────
-- Whitelists + metadata
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games',
    'dotsboxes_games','nameplace_games','truthordare_games','twotruths_games',
    'redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games',
    'tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds',
    'connect4_games','impostor_games','color_trap_games','freeze_auction_games',
    'flick_arena_games','secret_heist_games','mind_match_games'
  ) THEN
    RAISE EXCEPTION 'Unknown game table: %', p_game_table;
  END IF;
  EXECUTE format('UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;', p_game_table) USING p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn__game_meta() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tictactoe_games', jsonb_build_object('id','tictactoe','name','Tic-Tac-Toe','icon','#️⃣','accent','#8B5CF6'),
    'chess_games', jsonb_build_object('id','chess','name','Chess','icon','♟️','accent','#64748B'),
    'checkers_games', jsonb_build_object('id','checkers','name','Checkers','icon','🔴','accent','#6366F1'),
    'carrom_games', jsonb_build_object('id','carrom','name','Carrom','icon','⚪','accent','#F59E0B'),
    'ludo_games', jsonb_build_object('id','ludo','name','Ludo','icon','🎲','accent','#E11D48'),
    'bingo_games', jsonb_build_object('id','bingo','name','Bingo','icon','🎰','accent','#06B6D4'),
    'dotsboxes_games', jsonb_build_object('id','dotsboxes','name','Dots and Boxes','icon','📐','accent','#06B6D4'),
    'truthordare_games', jsonb_build_object('id','truthordare','name','Truth or Dare','icon','🎲','accent','#EF4444'),
    'twotruths_games', jsonb_build_object('id','twotruths','name','Two Truths and a Lie','icon','🤥','accent','#D946EF'),
    'chitmatch_games', jsonb_build_object('id','chitmatch','name','TripleMatch','icon','🎫','accent','#EC4899'),
    'redlight_rounds', jsonb_build_object('id','freeze-dash','name','Freeze & Dash','icon','🚦','accent','#10B981'),
    'ghost_painter_rounds', jsonb_build_object('id','ghost-painter','name','Ghost Painter','icon','👻','accent','#EC4899'),
    'antakshari_games', jsonb_build_object('id','antakshari','name','Antakshari','icon','🎵','accent','#8B5CF6'),
    'nameplace_games', jsonb_build_object('id','nameplace','name','Name, Place, Animal, Thing','icon','📝','accent','#10B981'),
    'sos_games', jsonb_build_object('id','sos','name','SOS','icon','🔤','accent','#F59E0B'),
    'tugofwar_games', jsonb_build_object('id','tug-of-war','name','Tug of War','icon','💪','accent','#E8612A'),
    'memorymatch_games', jsonb_build_object('id','memory-match','name','Memory Match','icon','🧠','accent','#A855F7'),
    'ashta_chamma_games', jsonb_build_object('id','ashta-chamma','name','Ashta Chamma','icon','🐚','accent','#E11D48'),
    'connect4_games', jsonb_build_object('id','connect4','name','Connect 4','icon','🔴','accent','#0EA5E9'),
    'impostor_games', jsonb_build_object('id','impostor','name','Who''s the Impostor?','icon','🕵️','accent','#8B5CF6'),
    'color_trap_games', jsonb_build_object('id','color-trap','name','Color Trap','icon','🎨','accent','#F59E0B'),
    'freeze_auction_games', jsonb_build_object('id','freeze-auction','name','Freeze Auction','icon','📦','accent','#F59E0B'),
    'flick_arena_games', jsonb_build_object('id','flick-arena','name','Flick Arena','icon','🎯','accent','#22D3EE'),
    'secret_heist_games', jsonb_build_object('id','secret-heist','name','Secret Heist','icon','💰','accent','#10B981'),
    'mind_match_games', jsonb_build_object('id','mind-match','name','Mind Match','icon','🧠','accent','#F472B6')
  );
$$;

-- Achievement — Mind Reader
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'mind-reader','Mind Reader','माइंड रीडर','Win 5 Mind Match games','🧠','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Seed the question pool — 200+ questions across 4 categories.
-- Each question is unique and family-friendly.
-- ─────────────────────────────────────────────────────────────────
INSERT INTO "mind_match_questions" (category, prompt) VALUES
  -- ── Everyday Life (60 questions) ──
  ('everyday', 'Name a breakfast food.'),
  ('everyday', 'Name a color.'),
  ('everyday', 'Name something found in a kitchen.'),
  ('everyday', 'Name a household chore.'),
  ('everyday', 'Name a mode of transportation.'),
  ('everyday', 'Name a common pet.'),
  ('everyday', 'Name a vegetable.'),
  ('everyday', 'Name a type of bread.'),
  ('everyday', 'Name a fruit.'),
  ('everyday', 'Name a dairy product.'),
  ('everyday', 'Name a hot beverage.'),
  ('everyday', 'Name a cold beverage.'),
  ('everyday', 'Name a fast food item.'),
  ('everyday', 'Name a dessert.'),
  ('everyday', 'Name a snack.'),
  ('everyday', 'Name a spice.'),
  ('everyday', 'Name a grain.'),
  ('everyday', 'Name a nut.'),
  ('everyday', 'Name a sea creature.'),
  ('everyday', 'Name a bird.'),
  ('everyday', 'Name a wild animal.'),
  ('everyday', 'Name a farm animal.'),
  ('everyday', 'Name an insect.'),
  ('everyday', 'Name a flower.'),
  ('everyday', 'Name a tree.'),
  ('everyday', 'Name a piece of furniture.'),
  ('everyday', 'Name an appliance.'),
  ('everyday', 'Name a tool.'),
  ('everyday', 'Name a piece of clothing.'),
  ('everyday', 'Name a footwear brand.'),
  ('everyday', 'Name a department store.'),
  ('everyday', 'Name a cleaning product.'),
  ('everyday', 'Name a personal care item.'),
  ('everyday', 'Name a school subject.'),
  ('everyday', 'Name an office supply.'),
  ('everyday', 'Name a electronic device.'),
  ('everyday', 'Name a social media app.'),
  ('everyday', 'Name a streaming service.'),
  ('everyday', 'Name a phone brand.'),
  ('everyday', 'Name a car brand.'),
  ('everyday', 'Name a motorbike brand.'),
  ('everyday', 'Name a sport.'),
  ('everyday', 'Name a board game.'),
  ('everyday', 'Name a card game.'),
  ('everyday', 'Name a video game console.'),
  ('everyday', 'Name a video game genre.'),
  ('everyday', 'Name a TV show genre.'),
  ('everyday', 'Name a music genre.'),
  ('everyday', 'Name a musical instrument.'),
  ('everyday', 'Name a dance style.'),
  ('everyday', 'Name a holiday.'),
  ('everyday', 'Name a day of the week.'),
  ('everyday', 'Name a month.'),
  ('everyday', 'Name a season.'),
  ('everyday', 'Name a weather condition.'),
  ('everyday', 'Name a body part.'),
  ('everyday', 'Name an emotion.'),
  ('everyday', 'Name a job profession.'),
  ('everyday', 'Name a place in your city.'),
  ('everyday', 'Name a room in a house.'),

  -- ── Fun (60 questions) ──
  ('fun', 'Name a superpower.'),
  ('fun', 'Name a movie genre.'),
  ('fun', 'Name something people lose often.'),
  ('fun', 'Name a fictional character.'),
  ('fun', 'Name a superhero.'),
  ('fun', 'Name a villain.'),
  ('fun', 'Name a Disney movie.'),
  ('fun', 'Name an animated movie.'),
  ('fun', 'Name a sci-fi movie.'),
  ('fun', 'Name a horror movie.'),
  ('fun', 'Name a comedy movie.'),
  ('fun', 'Name an action movie star.'),
  ('fun', 'Name a famous singer.'),
  ('fun', 'Name a famous band.'),
  ('fun', 'Name a famous rapper.'),
  ('fun', 'Name a TikTok trend.'),
  ('fun', 'Name a YouTube category.'),
  ('fun', 'Name a podcast topic.'),
  ('fun', 'Name a video game.'),
  ('fun', 'Name an arcade game.'),
  ('fun', 'Name a mobile game.'),
  ('fun', 'Name a cartoon character.'),
  ('fun', 'Name an anime.'),
  ('fun', 'Name a manga series.'),
  ('fun', 'Name a comic book hero.'),
  ('fun', 'Name a magic spell.'),
  ('fun', 'Name a mythical creature.'),
  ('fun', 'Name a fairy tale.'),
  ('fun', 'Name a princess.'),
  ('fun', 'Name a pirate item.'),
  ('fun', 'Name a ninja weapon.'),
  ('fun', 'Name a knight''s equipment.'),
  ('fun', 'Name a dinosaur.'),
  ('fun', 'Name a planet.'),
  ('fun', 'Name a constellation.'),
  ('fun', 'Name a Greek god.'),
  ('fun', 'Name an Egyptian god.'),
  ('fun', 'Name a famous monument.'),
  ('fun', 'Name a world wonder.'),
  ('fun', 'Name a museum exhibit.'),
  ('fun', 'Name a circus act.'),
  ('fun', 'Name a magic trick.'),
  ('fun', 'Name a board game piece.'),
  ('fun', 'Name a casino game.'),
  ('fun', 'Name a party game.'),
  ('fun', 'Name a drinking game.'),
  ('fun', 'Name a Halloween costume.'),
  ('fun', 'Name a Christmas song.'),
  ('fun', 'Name a birthday party item.'),
  ('fun', 'Name a wedding tradition.'),
  ('fun', 'Name a vacation activity.'),
  ('fun', 'Name a beach item.'),
  ('fun', 'Name a camping item.'),
  ('fun', 'Name an amusement park ride.'),
  ('fun', 'Name a water sport.'),
  ('fun', 'Name a winter sport.'),
  ('fun', 'Name an extreme sport.'),
  ('fun', 'Name an Olympic event.'),
  ('fun', 'Name a football team.'),
  ('fun', 'Name a cricket player.'),
  ('fun', 'Name a basketball player.'),

  -- ── Family (40 questions) ──
  ('family', 'Name a holiday destination.'),
  ('family', 'Name a family activity.'),
  ('family', 'Name a family tradition.'),
  ('family', 'Name a festival food.'),
  ('family', 'Name a Diwali item.'),
  ('family', 'Name a Holi color.'),
  ('family', 'Name a Raksha Bandhan item.'),
  ('family', 'Name a wedding food.'),
  ('family', 'Name a birthday food.'),
  ('family', 'Name a family game.'),
  ('family', 'Name a family movie.'),
  ('family', 'Name a family TV show.'),
  ('family', 'Name a relative.'),
  ('family', 'Name a family photo location.'),
  ('family', 'Name a family vacation spot.'),
  ('family', 'Name a family chore.'),
  ('family', 'Name a family rule.'),
  ('family', 'Name a family memory.'),
  ('family', 'Name a family heirloom.'),
  ('family', 'Name a family recipe.'),
  ('family', 'Name a bedtime story.'),
  ('family', 'Name a lullaby.'),
  ('family', 'Name a school memory.'),
  ('family', 'Name a childhood toy.'),
  ('family', 'Name a childhood game.'),
  ('family', 'Name a family car.'),
  ('family', 'Name a family pet name.'),
  ('family', 'Name a family nickname.'),
  ('family', 'Name a family gathering food.'),
  ('family', 'Name a family celebration.'),
  ('family', 'Name a family ritual.'),
  ('family', 'Name a family prayer.'),
  ('family', 'Name a family song.'),
  ('family', 'Name a family dance.'),
  ('family', 'Name a family outfit.'),
  ('family', 'Name a family jewelry.'),
  ('family', 'Name a family gift.'),
  ('family', 'Name a family story.'),
  ('family', 'Name a family lesson.'),
  ('family', 'Name a family value.'),

  -- ── Global (40 questions) ──
  ('global', 'Name a country.'),
  ('global', 'Name a famous animal.'),
  ('global', 'Name a world capital.'),
  ('global', 'Name a world city.'),
  ('global', 'Name a world language.'),
  ('global', 'Name a world currency.'),
  ('global', 'Name a world landmark.'),
  ('global', 'Name a world mountain.'),
  ('global', 'Name a world river.'),
  ('global', 'Name a world ocean.'),
  ('global', 'Name a world desert.'),
  ('global', 'Name a world island.'),
  ('global', 'Name a world flag color.'),
  ('global', 'Name a world cuisine.'),
  ('global', 'Name a world religion.'),
  ('global', 'Name a world festival.'),
  ('global', 'Name a world holiday.'),
  ('global', 'Name a world sport.'),
  ('global', 'Name a world athlete.'),
  ('global', 'Name a world leader.'),
  ('global', 'Name a world scientist.'),
  ('global', 'Name a world artist.'),
  ('global', 'Name a world author.'),
  ('global', 'Name a world composer.'),
  ('global', 'Name a world invention.'),
  ('global', 'Name a world discovery.'),
  ('global', 'Name a world explorer.'),
  ('global', 'Name a world war.'),
  ('global', 'Name a world treaty.'),
  ('global', 'Name a world organization.'),
  ('global', 'Name a world currency symbol.'),
  ('global', 'Name a world time zone.'),
  ('global', 'Name a world continent.'),
  ('global', 'Name a world climate.'),
  ('global', 'Name a world natural wonder.'),
  ('global', 'Name a world man-made wonder.'),
  ('global', 'Name a world heritage site.'),
  ('global', 'Name a world national park.'),
  ('global', 'Name a world beach.'),
  ('global', 'Name a world forest.')
ON CONFLICT DO NOTHING;
