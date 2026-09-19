-- 20260920240000_word_forge_game.sql
-- Word Forge — Balderdash-style fake-definitions party game. 3–8 players.
--
-- Each round, an obscure real word is shown (e.g. "floccinaucinihilipilification").
-- Players secretly write fake definitions. All fake definitions + the real
-- definition are shuffled and revealed. Players vote for which definition
-- they think is real. Points:
--   • +10 for guessing the real definition
--   • +5 per vote your fake definition receives (fooling others)
--   • +15 bonus if your definition mirrors the real one (close match)
-- After N rounds, the player with the most points wins.
--
-- Architecture reuses the hidden-submission pattern from mind_match +
-- secret_heist: definitions + votes live in separate tables with RLS that
-- hides other players' rows until the round resolves. The boardState JSONB
-- on the games row contains only aggregate counters + the resolved
-- definitions — never the pending submissions.
--
-- Word uniqueness: a word_history table tracks which words each family has
-- seen. The pick_word RPC prioritizes unseen words and never repeats within
-- 365 days.

CREATE TABLE IF NOT EXISTS "word_forge_games" (
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
  "answerSeconds" INTEGER NOT NULL DEFAULT 60
);
CREATE INDEX IF NOT EXISTS idx_wfg_family ON "word_forge_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "word_forge_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "word_forge_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_wfp_game ON "word_forge_players" ("gameId", "joinedAt");

-- Hidden-definition table. RLS exposes ONLY the caller's own row to each
-- player; the resolve RPC reads all rows for the round and updates the
-- games.boardState with the *resolved* definitions (shuffled + indexed).
CREATE TABLE IF NOT EXISTS "word_forge_definitions" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "word_forge_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "roundNumber" INTEGER NOT NULL,
  "definition" TEXT NOT NULL,
  "isReal" BOOLEAN NOT NULL DEFAULT false,
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "userId", "roundNumber")
);
CREATE INDEX IF NOT EXISTS idx_wfd_game_round ON "word_forge_definitions" ("gameId", "roundNumber");

-- Hidden-vote table. RLS exposes ONLY the caller's own row to each player.
-- The resolve RPC reads all votes and updates boardState with per-player
-- points awarded + definition vote counts.
CREATE TABLE IF NOT EXISTS "word_forge_votes" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "word_forge_games"(id) ON DELETE CASCADE,
  "voterUserId" TEXT NOT NULL,
  "roundNumber" INTEGER NOT NULL,
  "votedForUserId" TEXT NOT NULL DEFAULT '',  -- empty = voted for the real definition
  "votedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "voterUserId", "roundNumber")
);
CREATE INDEX IF NOT EXISTS idx_wfv_game_round ON "word_forge_votes" ("gameId", "roundNumber");

-- ─────────────────────────────────────────────────────────────────
-- Word pool — seeded with 100+ obscure real words + their definitions.
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "word_forge_words" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  word TEXT NOT NULL UNIQUE,
  "realDefinition" TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'obscure',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  active BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_wfw_category ON "word_forge_words" (category, active);

-- Tracks which words each family has seen (for the 365-day no-repeat rule).
CREATE TABLE IF NOT EXISTS "word_forge_word_history" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "wordId" TEXT NOT NULL REFERENCES "word_forge_words"(id) ON DELETE CASCADE,
  "gameId" TEXT NOT NULL,
  "shownAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("familyId", "wordId")
);
CREATE INDEX IF NOT EXISTS idx_wfwh_family_time ON "word_forge_word_history" ("familyId", "shownAt" DESC);

-- ─────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "word_forge_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_games_select_family" ON "word_forge_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "word_forge_games_insert_host" ON "word_forge_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "word_forge_games_update_family" ON "word_forge_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "word_forge_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_players_select_family" ON "word_forge_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "word_forge_games" g WHERE g.id = "word_forge_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "word_forge_players_insert_self_or_host" ON "word_forge_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "word_forge_games" g WHERE g.id = "word_forge_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "word_forge_players_update_self" ON "word_forge_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "word_forge_players_delete_self" ON "word_forge_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Definitions: hidden until reveal. RLS exposes only the caller's own row.
ALTER TABLE "word_forge_definitions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_definitions_select_own" ON "word_forge_definitions" FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "word_forge_definitions_insert_own" ON "word_forge_definitions" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "word_forge_definitions_update_own" ON "word_forge_definitions" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "word_forge_definitions_delete_own" ON "word_forge_definitions" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Votes: hidden until reveal. RLS exposes only the caller's own row.
ALTER TABLE "word_forge_votes" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_votes_select_own" ON "word_forge_votes" FOR SELECT TO authenticated USING ("voterUserId" = auth.uid()::text);
CREATE POLICY "word_forge_votes_insert_own" ON "word_forge_votes" FOR INSERT TO authenticated WITH CHECK ("voterUserId" = auth.uid()::text);
CREATE POLICY "word_forge_votes_update_own" ON "word_forge_votes" FOR UPDATE TO authenticated USING ("voterUserId" = auth.uid()::text);
CREATE POLICY "word_forge_votes_delete_own" ON "word_forge_votes" FOR DELETE TO authenticated USING ("voterUserId" = auth.uid()::text);

ALTER TABLE "word_forge_words" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_words_select_all" ON "word_forge_words" FOR SELECT TO authenticated USING (active = true);

ALTER TABLE "word_forge_word_history" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "word_forge_word_history_select_family" ON "word_forge_word_history" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "word_forge_word_history_insert_family" ON "word_forge_word_history" FOR INSERT TO authenticated WITH CHECK (public.fn_user_is_family_member("familyId"));

ALTER PUBLICATION supabase_realtime ADD TABLE "word_forge_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "word_forge_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "word_forge_definitions";
ALTER PUBLICATION supabase_realtime ADD TABLE "word_forge_votes";
ALTER TABLE "word_forge_games" REPLICA IDENTITY FULL;
ALTER TABLE "word_forge_players" REPLICA IDENTITY FULL;
ALTER TABLE "word_forge_definitions" REPLICA IDENTITY FULL;
ALTER TABLE "word_forge_votes" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_pick_word — pick an unseen word for the family.
-- Prioritizes words not shown in the last 365 days. Falls back to
-- least-recently-shown if all have been seen.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_pick_word(
  p_family_id text,
  p_game_id text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_word_id text;
BEGIN
  -- Try to find a word NOT in the family's history (last 365 days)
  SELECT w.id INTO v_word_id FROM "word_forge_words" w
   WHERE w.active = true
     AND w.id NOT IN (
       SELECT h."wordId" FROM "word_forge_word_history" h
       WHERE h."familyId" = p_family_id
         AND h."shownAt" > now() - interval '365 days'
     )
   ORDER BY random()
   LIMIT 1;

  -- If all words have been seen, fall back to least-recently-shown
  IF v_word_id IS NULL THEN
    SELECT w.id INTO v_word_id FROM "word_forge_words" w
     WHERE w.active = true
     ORDER BY (
       SELECT COALESCE(MAX(h."shownAt"), '1970-01-01'::timestamptz)
         FROM "word_forge_word_history" h
        WHERE h."familyId" = p_family_id AND h."wordId" = w.id
     ) ASC, random()
     LIMIT 1;
  END IF;

  -- Record the word as shown for this family
  IF v_word_id IS NOT NULL THEN
    INSERT INTO "word_forge_word_history" ("familyId", "wordId", "gameId")
    VALUES (p_family_id, v_word_id, p_game_id)
    ON CONFLICT ("familyId", "wordId") DO UPDATE SET "shownAt" = now(), "gameId" = p_game_id;
  END IF;

  RETURN v_word_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_pick_word(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_start — host starts the match.
-- Initializes boardState with N players and round 1 (writing phase).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_start(p_game_id text) RETURNS jsonb
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
  v_word_id text;
  v_word record;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "word_forge_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 3 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
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
      'foolCount', 0,
      'correctGuesses', 0
    );
  END LOOP;
  v_answer_seconds := v_game."answerSeconds";
  -- Pick first word
  v_word_id := public.fn_wordforge_pick_word(v_game."familyId", p_game_id);
  IF v_word_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_words_available');
  END IF;
  SELECT * INTO v_word FROM "word_forge_words" WHERE id = v_word_id;
  v_board := jsonb_build_object(
    'playerCount', v_count,
    'totalRounds', v_game."totalRounds",
    'answerSeconds', v_answer_seconds,
    'currentRound', 1,
    'rounds', jsonb_build_array(jsonb_build_object(
      'roundNumber', 1,
      'phase', 'writing',
      'word', v_word.word,
      'realDefinition', v_word."realDefinition",
      'category', v_word.category,
      'definitions', '[]'::jsonb,
      'pointsAwarded', '[]'::jsonb,
      'voteCount', 0,
      'submittedCount', 0
    )),
    'players', v_players_arr,
    'status', 'in_progress',
    'winner', -1
  );
  UPDATE "word_forge_games" SET
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
GRANT EXECUTE ON FUNCTION public.fn_wordforge_start(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_submit_definition — a player submits their fake definition.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_submit_definition(
  p_game_id text,
  p_definition text
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
  v_submitted_count int;
  v_trimmed text;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'writing' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_writing_phase'); END IF;

  v_trimmed := btrim(p_definition);
  IF v_trimmed = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'empty_definition'); END IF;
  IF length(v_trimmed) > 200 THEN RETURN jsonb_build_object('ok', false, 'reason', 'definition_too_long'); END IF;

  -- Insert or update (player can change their definition during writing phase)
  SELECT * INTO v_existing FROM "word_forge_definitions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current AND "isReal" = false LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "word_forge_definitions" ("gameId","userId","roundNumber","definition","isReal")
    VALUES (p_game_id, auth.uid()::text, v_current, v_trimmed, false);
  ELSE
    UPDATE "word_forge_definitions" SET "definition" = v_trimmed, "submittedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  -- Count non-real definitions submitted this round
  SELECT count(*) INTO v_submitted_count FROM "word_forge_definitions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "isReal" = false;

  v_round := jsonb_set(v_round, '{submittedCount}', v_submitted_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  v_player_count := (v_board->>'playerCount')::int;
  v_answer_seconds := (v_board->>'answerSeconds')::int;

  -- Auto-resolve when all players have submitted. We persist the
  -- submittedCount update first so resolve_definitions sees the latest
  -- state, then call resolve_definitions which sets phase=revealing +
  -- builds the shuffled definitions array.
  IF v_submitted_count >= v_player_count THEN
    UPDATE "word_forge_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_wordforge_resolve_definitions(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "word_forge_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_submit_definition(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_resolve_definitions — shuffle all definitions + the real
-- one into boardState.rounds[current].definitions[]. Each definition gets
-- a displayIndex (1-based). Vote counts start at 0.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_resolve_definitions(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_definitions jsonb := '[]'::jsonb;
  v_def_obj jsonb;
  v_def_rec record;
  v_player_idx int;
  v_player_name text;
  v_display_idx int := 1;
  v_combined jsonb;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_round := v_board->'rounds'->(v_current - 1);

  -- Build a combined set of all fake defs + the real def, in random order.
  -- We use a CTE to assign displayIndex by random order.
  WITH all_defs AS (
    SELECT
      d."userId" AS user_id,
      COALESCE((SELECT p->>'name' FROM jsonb_array_elements(v_board->'players') WITH ORDINALITY AS t(p, i)
                 WHERE (p->>'idx')::int = (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS o(uid, idx) WHERE uid = d."userId")), 'Dictionary') AS user_name,
      d."definition" AS definition,
      false AS is_real
    FROM "word_forge_definitions" d
    WHERE d."gameId" = p_game_id AND d."roundNumber" = v_current AND d."isReal" = false
    UNION ALL
    SELECT
      '' AS user_id,
      'Dictionary' AS user_name,
      v_round->>'realDefinition' AS definition,
      true AS is_real
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'userId', ad.user_id,
      'userName', ad.user_name,
      'definition', ad.definition,
      'isReal', ad.is_real,
      'voteCount', 0,
      'displayIndex', ROW_NUMBER() OVER (ORDER BY random())
    )
  )
  INTO v_definitions
  FROM all_defs ad;

  IF v_definitions IS NULL THEN
    v_definitions := '[]'::jsonb;
  END IF;

  -- Update round: phase = revealing, definitions populated
  v_round := jsonb_set(v_round, '{phase}', '"revealing"');
  v_round := jsonb_set(v_round, '{definitions}', v_definitions);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  UPDATE "word_forge_games" SET "boardState" = v_board, "turnEndsAt" = NULL, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_resolve_definitions(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_vote — a player votes for a definition.
-- p_voted_for_user_id: '' = voting for the real definition,
--                      otherwise the userId of the fake def's author.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_vote(
  p_game_id text,
  p_voted_for_user_id text
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
  v_vote_count int;
  v_definitions jsonb;
  v_def_idx int;
  v_def_obj jsonb;
  v_target_user_id text;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'voting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_voting_phase'); END IF;

  -- Can't vote for your own fake definition
  IF p_voted_for_user_id = auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'cannot_vote_for_own');
  END IF;

  -- Insert or update vote
  SELECT * INTO v_existing FROM "word_forge_votes"
    WHERE "gameId" = p_game_id AND "voterUserId" = auth.uid()::text AND "roundNumber" = v_current LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "word_forge_votes" ("gameId","voterUserId","roundNumber","votedForUserId")
    VALUES (p_game_id, auth.uid()::text, v_current, p_voted_for_user_id);
  ELSE
    UPDATE "word_forge_votes" SET "votedForUserId" = p_voted_for_user_id, "votedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  -- Count votes this round
  SELECT count(*) INTO v_vote_count FROM "word_forge_votes"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current;

  v_round := jsonb_set(v_round, '{voteCount}', v_vote_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  v_player_count := (v_board->>'playerCount')::int;

  -- Auto-resolve when all players have voted. Persist the vote count
  -- update first so resolve_votes sees the latest state, then call
  -- resolve_votes which sets phase=results + awards points.
  IF v_vote_count >= v_player_count THEN
    UPDATE "word_forge_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_wordforge_resolve_votes(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "word_forge_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_vote(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_resolve_votes — count votes per definition, award points.
-- Scoring:
--   • Guess real definition: +10
--   • Each vote your fake def gets: +5 per vote
--   • Close-match bonus: +15 if your definition shares 3+ significant
--     keywords (>= 4 chars, excluding stopwords) with the real one
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_resolve_votes(p_game_id text) RETURNS jsonb
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
  v_definitions jsonb;
  v_def_idx int;
  v_def_obj jsonb;
  v_vote_rec record;
  v_points_arr jsonb := '[]'::jsonb;
  v_points int;
  v_player_idx int;
  v_player_score int;
  v_player_fool int;
  v_player_correct int;
  v_i int;
  v_voted_for text;
  v_voted_real boolean;
  v_fool_count int;
  v_close_bonus boolean;
  v_real_def text;
  v_my_def text;
  v_real_words text[];
  v_my_words text[];
  v_shared int;
  v_word text;
  v_new_round jsonb;
  v_new_word_id text;
  v_new_word record;
  v_max_score int;
  v_winner_idx int;
  v_tie boolean;
  v_s int;
  v_real_def_idx int;
  v_def_user_id text;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_players := v_board->'players';
  v_answer_seconds := (v_board->>'answerSeconds')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  v_definitions := v_round->'definitions';
  v_real_def := v_round->>'realDefinition';

  -- ── Step 1: Count votes per definition ──
  -- For each vote, find the matching definition and increment voteCount.
  IF v_definitions IS NULL THEN
    v_definitions := '[]'::jsonb;
  END IF;

  FOR v_def_idx IN 0..jsonb_array_length(v_definitions) - 1 LOOP
    v_def_obj := v_definitions->v_def_idx;
    v_def_user_id := v_def_obj->>'userId';
    -- Count votes for this definition
    IF (v_def_obj->>'isReal')::boolean THEN
      -- Real definition: votes with empty votedForUserId
      SELECT count(*) INTO v_fool_count FROM "word_forge_votes"
        WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "votedForUserId" = '';
    ELSE
      -- Fake definition: votes with votedForUserId = author's userId
      SELECT count(*) INTO v_fool_count FROM "word_forge_votes"
        WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "votedForUserId" = v_def_user_id;
    END IF;
    v_def_obj := jsonb_set(v_def_obj, '{voteCount}', v_fool_count::text::jsonb);
    v_definitions := jsonb_set(v_definitions, ARRAY[v_def_idx::text], v_def_obj);
  END LOOP;

  -- ── Step 2: Award points to each player ──
  v_points_arr := '[]'::jsonb;
  -- Pre-compute significant words in the real definition (lowercase, >= 4 chars, not stopwords)
  v_real_words := ARRAY(
    SELECT lower(w) FROM regexp_split_to_table(lower(v_real_def), '[^a-zA-Z]+') AS w
     WHERE length(w) >= 4
       AND w NOT IN ('that','this','with','from','have','your','their','there','what','which','when','where','will','they','them','then','than','were','been','being','have','has','had','does','done','some','such','very','more','most','also','only','just','like','into','upon','about','above','below','under','other','after','before')
  );

  FOR v_i IN 0..v_player_count - 1 LOOP
    v_points := 0;
    v_fool_count := 0;
    v_close_bonus := false;
    v_voted_for := '';
    v_voted_real := false;

    -- Find this player's vote
    SELECT "votedForUserId" INTO v_voted_for FROM "word_forge_votes"
      WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "voterUserId" = v_game."playerOrder"->>v_i::text
      LIMIT 1;

    IF v_voted_for IS NOT NULL THEN
      IF v_voted_for = '' THEN
        -- Voted for the real definition
        v_points := v_points + 10;
        v_voted_real := true;
      END IF;
    END IF;

    -- Find this player's fake definition and count its votes
    SELECT count(*) INTO v_fool_count FROM "word_forge_votes" v
      WHERE v."gameId" = p_game_id AND v."roundNumber" = v_current
        AND v."votedForUserId" = v_game."playerOrder"->>v_i::text;
    v_points := v_points + v_fool_count * 5;

    -- Close-match bonus: does this player's definition share 3+ significant words with the real?
    SELECT "definition" INTO v_my_def FROM "word_forge_definitions"
      WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "userId" = v_game."playerOrder"->>v_i::text AND "isReal" = false
      LIMIT 1;
    IF v_my_def IS NOT NULL THEN
      v_my_words := ARRAY(
        SELECT lower(w) FROM regexp_split_to_table(lower(v_my_def), '[^a-zA-Z]+') AS w
         WHERE length(w) >= 4
           AND w NOT IN ('that','this','with','from','have','your','their','there','what','which','when','where','will','they','them','then','than','were','been','being','have','has','had','does','done','some','such','very','more','most','also','only','just','like','into','upon','about','above','below','under','other','after','before')
      );
      SELECT count(*) INTO v_shared FROM unnest(v_real_words) AS r
       WHERE r = ANY(v_my_words);
      IF v_shared >= 3 THEN
        v_close_bonus := true;
        v_points := v_points + 15;
      END IF;
    END IF;

    -- Update player score + counters
    v_player_score := (v_players->v_i->>'score')::int + v_points;
    v_player_fool := (v_players->v_i->>'foolCount')::int + v_fool_count;
    v_player_correct := (v_players->v_i->>'correctGuesses')::int + (CASE WHEN v_voted_real THEN 1 ELSE 0 END);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'score'], v_player_score::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'lastRoundPoints'], v_points::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'foolCount'], v_player_fool::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'correctGuesses'], v_player_correct::text::jsonb);

    v_points_arr := v_points_arr || jsonb_build_object(
      'playerIndex', v_i,
      'points', v_points,
      'guessedReal', v_voted_real,
      'foolCount', v_fool_count,
      'closeBonus', v_close_bonus,
      'votedForUserId', COALESCE(v_voted_for, ''),
      'votedForReal', v_voted_real
    );
  END LOOP;

  -- ── Step 3: Update round with resolved state ──
  v_round := jsonb_set(v_round, '{phase}', '"results"');
  v_round := jsonb_set(v_round, '{definitions}', v_definitions);
  v_round := jsonb_set(v_round, '{pointsAwarded}', v_points_arr);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  v_board := jsonb_set(v_board, '{players}', v_players);

  UPDATE "word_forge_games" SET "boardState" = v_board, "turnEndsAt" = NULL, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_resolve_votes(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_advance — advance phase.
--   writing -> revealing (auto via submit; or via timer)
--   revealing -> voting (host triggers; sets new timer)
--   voting -> results (auto via vote; or via timer)
--   results -> next round (writing) OR finish
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_advance(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb;
  v_current int; v_player_count int; v_total_rounds int; v_answer_seconds int;
  v_new_word_id text; v_new_word record; v_new_round jsonb;
  v_max_score int; v_winner_idx int; v_tie boolean; v_s int; v_i int;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_answer_seconds := (v_board->>'answerSeconds')::int;
  v_round := v_board->'rounds'->(v_current - 1);

  IF v_round->>'phase' = 'writing' THEN
    -- Timer expired during writing — resolve with whoever has submitted,
    -- then enter revealing phase. Host will start voting when ready.
    PERFORM public.fn_wordforge_resolve_definitions(p_game_id);
    -- resolve_definitions sets phase = revealing; clear the timer so
    -- the watchdog doesn't keep firing.
    UPDATE "word_forge_games" SET "turnEndsAt" = NULL, "lastActivityAt" = now()
     WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'auto_resolved', true);
  ELSIF v_round->>'phase' = 'revealing' THEN
    -- Host triggers voting phase
    v_round := jsonb_set(v_round, '{phase}', '"voting"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "word_forge_games" SET "boardState" = v_board,
      "turnEndsAt" = now() + (v_answer_seconds || ' seconds')::interval,
      "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true);
  ELSIF v_round->>'phase' = 'voting' THEN
    -- Timer expired during voting — auto-resolve with whoever has voted
    PERFORM public.fn_wordforge_resolve_votes(p_game_id);
    RETURN jsonb_build_object('ok', true, 'auto_resolved', true);
  ELSIF v_round->>'phase' = 'results' THEN
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
      UPDATE "word_forge_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN NOT v_tie AND v_winner_idx >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_idx::text) ELSE '[]'::jsonb END,
        "endReason" = 'most_points', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    ELSE
      -- Pick next word
      v_new_word_id := public.fn_wordforge_pick_word(v_game."familyId", p_game_id);
      IF v_new_word_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_words_available');
      END IF;
      SELECT * INTO v_new_word FROM "word_forge_words" WHERE id = v_new_word_id;
      v_new_round := jsonb_build_object(
        'roundNumber', v_current + 1,
        'phase', 'writing',
        'word', v_new_word.word,
        'realDefinition', v_new_word."realDefinition",
        'category', v_new_word.category,
        'definitions', '[]'::jsonb,
        'pointsAwarded', '[]'::jsonb,
        'voteCount', 0,
        'submittedCount', 0
      );
      v_rounds := v_board->'rounds' || v_new_round;
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      v_board := jsonb_set(v_board, '{currentRound}', (v_current + 1)::text::jsonb);
      UPDATE "word_forge_games" SET "boardState" = v_board,
        "turnEndsAt" = now() + (v_answer_seconds || ' seconds')::interval,
        "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true);
    END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_advance(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_tick — 2s watchdog. Auto-advances on timer expiry.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "word_forge_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN
    PERFORM public.fn_wordforge_advance(p_game_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_wordforge_leave
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_wordforge_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "word_forge_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "word_forge_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "word_forge_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 3 AND v_game.status = 'in_progress' THEN
    UPDATE "word_forge_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "word_forge_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_wordforge_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__wordforge_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('word_forge_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'wordforge archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_wordforge_archive ON "word_forge_games";
CREATE TRIGGER trg_wordforge_archive AFTER UPDATE ON "word_forge_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__wordforge_on_complete();

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
    'flick_arena_games','secret_heist_games','mind_match_games','word_forge_games'
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
    'mind_match_games', jsonb_build_object('id','mind-match','name','Mind Match','icon','🧠','accent','#F472B6'),
    'word_forge_games', jsonb_build_object('id','word-forge','name','Word Forge','icon','📖','accent','#8B5CF6')
  );
$$;

-- Achievement — Wordsmith
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'wordsmith','Wordsmith','वर्डस्मिथ','Win 5 Word Forge games','📖','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Seed the word pool — 100+ obscure real words with definitions.
-- All words are real English words; definitions sourced from dictionaries.
-- ─────────────────────────────────────────────────────────────────
INSERT INTO "word_forge_words" (word, "realDefinition", category) VALUES
  -- ── Long / unusual words ──
  ('floccinaucinihilipilification', 'The act or habit of estimating something as worthless.', 'long'),
  ('antidisestablishmentarianism', 'Opposition to the disestablishment of the Church of England.', 'long'),
  ('pseudopseudohypoparathyroidism', 'A mild form of hypoparathyroidism that mimics the symptoms but without the biochemical abnormalities.', 'long'),
  ('supercalifragilisticexpialidocious', 'Extraordinarily good; wonderful.', 'long'),
  ('incomprehensibilities', 'Things that are impossible to understand.', 'long'),
  ('honorificabilitudinitatibus', 'The state of being able to receive honors.', 'long'),
  ('thyroparathyroidectomized', 'Having had the thyroid and parathyroid glands removed.', 'long'),
  ('dichlorodifluoromethane', 'A colorless gas used as a refrigerant and aerosol propellant.', 'long'),
  ('electroencephalographically', 'Pertaining to the recording of electrical activity of the brain.', 'long'),
  ('psychoneuroendocrinological', 'Pertaining to the study of the interactions between psychological, neurological, and endocrine processes.', 'long'),

  -- ── Quirky / specific words ──
  ('defenestration', 'The act of throwing someone out of a window.', 'quirky'),
  ('petrichor', 'The pleasant, earthy smell that follows rain on dry soil.', 'quirky'),
  ('sesquipedalian', 'Characterized by long words; given to using long words.', 'quirky'),
  ('borborygmus', 'A rumbling or gurgling noise made by the movement of fluid and gas in the intestines.', 'quirky'),
  ('snollygoster', 'A shrewd, unprincipled person, especially a politician.', 'quirky'),
  ('collywobbles', 'Stomach pain or a feeling of butterflies in the stomach from anxiety.', 'quirky'),
  ('bumfuzzle', 'To confuse or fluster someone.', 'quirky'),
  ('cattywampus', 'Askew, awry, or positioned diagonally.', 'quirky'),
  ('gardyloo', 'A warning cry formerly used to alert passersby of slops being thrown from windows.', 'quirky'),
  ('taradiddle', 'A petty lie or a pretentious but empty statement.', 'quirky'),
  ('flibbertigibbet', 'A frivolous, flighty, or excessively talkative person.', 'quirky'),
  ('malarkey', 'Meaningless talk; nonsense or foolishness.', 'quirky'),
  ('pandiculation', 'The act of stretching and yawning, especially upon waking.', 'quirky'),
  ('widdershins', 'In a direction contrary to the sun''s course; counterclockwise.', 'quirky'),
  ('snickersnee', 'A large knife.', 'quirky'),
  ('gobbledygook', 'Language that is meaningless or made unintelligible by excessive use of abstruse technical terms.', 'quirky'),
  ('bumbershoot', 'An umbrella.', 'quirky'),
  ('nudiustertian', 'Of or relating to the day before yesterday.', 'quirky'),
  ('quockerwodger', 'A wooden puppet on a string; a person who is easily controlled by others.', 'quirky'),
  ('snoutband', 'A person who continually interrupts a conversation to correct or contradict.', 'quirky'),

  -- ── Obscure nouns ──
  ('aglet', 'The plastic or metal sheath at the end of a shoelace.', 'noun'),
  ('grommet', 'A ring or eyelet of metal, plastic, or rope used to reinforce a hole.', 'noun'),
  ('tittle', 'A tiny dot or stroke used in writing, especially the dot over the letters i and j.', 'noun'),
  ('punt', 'The indentation at the bottom of a wine bottle.', 'noun'),
  ('glabella', 'The smooth area of the forehead between the eyebrows.', 'noun'),
  ('philtrum', 'The vertical groove between the base of the nose and the border of the upper lip.', 'noun'),
  ('lunula', 'The crescent-shaped white area at the base of a fingernail.', 'noun'),
  ('fossette', 'A small dimple or depression, especially on the cheek.', 'noun'),
  ('napron', 'A cloth covering for the front of the body, formerly used for an apron.', 'noun'),
  ('ferrule', 'A metal ring or cap placed around the end of a handle or tube to prevent splitting.', 'noun'),
  ('muntin', 'A vertical strip separating panes of glass in a window.', 'noun'),
  ('ophthalmophone', 'An instrument for recording the sounds of the eye.', 'noun'),
  ('purlicue', 'The space between the thumb and forefinger when extended.', 'noun'),
  ('guttle', 'To eat or drink greedily or voraciously.', 'verb'),
  ('feague', 'To give a better appearance to a horse for sale by inserting ginger into its anus.', 'verb'),

  -- ── Verbs ──
  ('obnubilate', 'To obscure or becloud, as with a literal or figurative mist.', 'verb'),
  ('deflagrate', 'To burn or cause to burn rapidly, with a sudden combustion.', 'verb'),
  ('exsanguinate', 'To drain of blood; to bleed to death.', 'verb'),
  ('perorate', 'To speak at length, especially in a pompous or grandiloquent manner.', 'verb'),
  ('tergiversate', 'To make conflicting or evasive statements; to equivocate.', 'verb'),
  ('absquatulate', 'To abscond or flee hurriedly.', 'verb'),
  ('cockalorum', 'A self-important little man; a boastful person.', 'noun'),
  ('circumlocute', 'To use many words where fewer would do, especially to avoid being direct.', 'verb'),
  ('confabulate', 'To talk informally; to chat, or to fabricate memories without conscious intention to deceive.', 'verb'),
  ('lollygag', 'To spend time aimlessly; to dawdle or loaf.', 'verb'),
  ('discombobulate', 'To disconcert or confuse someone.', 'verb'),
  ('gongoozle', 'To stare idly at a canal or waterway and observe passing boats.', 'verb'),
  ('snirtle', 'To laugh in a suppressed or derisive manner; to snicker.', 'verb'),
  ('fudgel', 'To pretend to work without actually accomplishing anything.', 'verb'),
  ('grubstake', 'To provide with funds or supplies in exchange for a share in the profits.', 'verb'),

  -- ── Adjectives ──
  ('pulchritudinous', 'Physically beautiful or attractive.', 'adjective'),
  ('callipygian', 'Having shapely buttocks.', 'adjective'),
  ('mellifluous', 'Sweet or musical; flowing like honey.', 'adjective'),
  ('obstreperous', 'Noisy and difficult to control, often in an aggressive manner.', 'adjective'),
  ('perspicacious', 'Having a ready insight into and understanding of things.', 'adjective'),
  ('pellucid', 'Translucently clear; easily understood.', 'adjective'),
  ('lugubrious', 'Looking or sounding sad and dismal.', 'adjective'),
  ('salubrious', 'Health-giving; healthy or pleasant.', 'adjective'),
  ('insouciant', 'Showing a casual lack of concern; indifferent.', 'adjective'),
  ('obfuscate', 'To render obscure, unclear, or unintelligible.', 'verb'),
  ('pulverulent', 'Reduced to powder; dusty or powdery in nature.', 'adjective'),
  ('rigmarole', 'A lengthy and complicated procedure; a long, rambling story or statement.', 'noun'),
  ('recalcitrant', 'Having an obstinately uncooperative attitude toward authority.', 'adjective'),
  ('loquacious', 'Tending to talk a great deal; talkative.', 'adjective'),

  -- ── Phobia / -ism words ──
  ('hippopotomonstrosesquippedaliophobia', 'The fear of long words.', 'phobia'),
  ('trichotillomania', 'The compulsion to pull out one''s own hair.', 'mania'),
  ('pogonotrophy', 'The act of cultivating or growing a beard.', 'noun'),
  ('logolepsy', 'An obsession with words.', 'noun'),
  ('onomatomania', 'A preoccupation with words or names.', 'noun'),
  ('verbomania', 'A craze for words; an intense enthusiasm for vocabulary.', 'noun'),
  ('lexicomania', 'An obsession with reading dictionaries.', 'noun'),

  -- ── Nature / science ──
  ('pareidolia', 'The tendency to perceive a specific, often meaningful image in a random or ambiguous visual pattern.', 'science'),
  ('apophenia', 'The tendency to perceive meaningful connections between unrelated things.', 'science'),
  ('proprioception', 'The sense of the position and movement of the body and its parts.', 'science'),
  ('noctilucent', 'Shining by night; describing luminous clouds seen in summer twilight.', 'science'),
  ('crepuscular', 'Relating to twilight; active at dusk or dawn.', 'adjective'),
  ('frutescent', 'Resembling a shrub; growing in the form of a shrub.', 'adjective'),
  ('indumentum', 'A covering of fine hairs on the leaves or stems of plants.', 'noun'),
  ('farinaceous', 'Containing or resembling starch or meal; mealy.', 'adjective'),
  ('ramose', 'Having many branches; branching.', 'adjective'),
  ('glabrescent', 'Becoming hairless or smooth, especially with age.', 'adjective'),

  -- ── Old / archaic ──
  ('loimic', 'Relating to or caused by a plague or pestilence.', 'archaic'),
  ('grobble', 'To stare at someone in a sullen or angry manner.', 'archaic'),
  ('twattle', 'To talk much and idly; to chatter or prate.', 'archaic'),
  ('jargogle', 'To confuse or perplex someone with jargon.', 'archaic'),
  ('snudge', 'To walk or move in a stooped or slouching manner.', 'archaic'),
  ('quagswagging', 'Shaking or wobbling, as if in a bog.', 'archaic'),
  ('chork', 'To make a sucking sound with the feet when walking in wet shoes.', 'archaic'),
  ('kench', 'To laugh loudly and inappropriately.', 'archaic'),
  ('bletcherous', 'Disgusting or gross; aesthetically unpleasing.', 'archaic'),
  ('jerryjig', 'To cheat or trick someone in a sly or cunning manner.', 'archaic'),

  -- ── Body / anatomical ──
  ('canthus', 'The angle at either end of the eye between the eyelids.', 'anatomy'),
  ('raphé', 'A ridge or seam in tissue, especially in the male reproductive system.', 'anatomy'),
  ('gnathion', 'The lowest point of the midline of the lower jaw.', 'anatomy'),
  ('gustation', 'The act or sense of tasting.', 'anatomy'),
  ('palpebral', 'Relating to the eyelids.', 'anatomy'),
  ('nasalala', 'A deformation of the nasal passages causing difficulty in breathing.', 'anatomy'),

  -- ── Miscellaneous ──
  ('gongoozler', 'An idle spectator; someone who stares at canals or waterways.', 'noun'),
  ('kakistocracy', 'Government by the worst or least qualified citizens.', 'noun'),
  ('chrysalism', 'The amniotic tranquility of being indoors during a thunderstorm.', 'noun'),
  ('monopsis', 'The tendency to judge others by the standards of one''s own group.', 'noun'),
  ('sillage', 'The trail of scent left behind by a perfume.', 'noun'),
  ('querencia', 'A place where one feels safe; a refuge or haven.', 'noun'),
  ('sphallolalia', 'Irresponsible or deceptive flirtatious talk.', 'noun'),
  ('apricity', 'The warmth of the sun in winter.', 'noun'),
  ('psithurism', 'The sound of wind rustling through trees.', 'noun'),
  ('eigengrau', 'The intrinsic color of darkness seen by the eyes when closed.', 'noun'),
  ('lalochezia', 'The emotional relief gained from using profanity.', 'noun'),
  ('chanking', 'Food that has been chewed and spat out.', 'noun'),
  ('snackmouth', 'The constant desire to snack or eat small amounts of food.', 'noun'),
  ('latibule', 'A hiding place; a cozy retreat or refuge.', 'noun'),
  ('glaucous', 'Of a pale grayish-green or blue color, like the bloom on a plum.', 'adjective')
ON CONFLICT (word) DO NOTHING;
