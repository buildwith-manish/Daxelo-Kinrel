-- 20260919100000_tugofwar_auto_teams.sql
--
-- Tug of War — AUTOMATIC team assignment on join (lobby UX overhaul).
--
-- Directive: remove manual team selection entirely. Players are assigned
-- alternately between Team A (Ember, red) and Team B (Azure, blue) in
-- TRUE JOIN ORDER as they join:
--
--   Player 1 → Team A (Ember)     Player 2 → Team B (Azure)
--   Player 3 → Team A (Ember)     Player 4 → Team B (Azure)  …
--
-- Teams therefore stay balanced (|A| - |B| <= 1) with zero taps, and the
-- assignment is visible the moment a player lands in the lobby.
--
-- Implementation: an AFTER INSERT trigger on tugofwar_players assigns
-- the joining player to the SMALLER team (join order breaks ties), which
-- from an empty room produces exact alternation. Server-authoritative —
-- works for hosts and joiners alike, no client RPC needed.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Trigger function: assign team on join
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_tugofwar_assign_team_on_join()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_n_a int;
  v_n_b int;
  v_team text;
BEGIN
  -- Only waiting rooms auto-assign; in-flight matches keep their rosters.
  SELECT status INTO v_status FROM "tugofwar_games" WHERE "id" = NEW."gameId";
  IF v_status IS NULL OR v_status <> 'waiting' THEN
    RETURN NEW;
  END IF;

  -- Already assigned (e.g. rematch copying rosters)? Keep it.
  IF NEW.team IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Smaller team wins; join order breaks ties → exact alternation
  -- (P1 → A, P2 → B, P3 → A, P4 → B …).
  SELECT COUNT(*) INTO v_n_a FROM "tugofwar_players"
   WHERE "gameId" = NEW."gameId" AND team = 'A';
  SELECT COUNT(*) INTO v_n_b FROM "tugofwar_players"
   WHERE "gameId" = NEW."gameId" AND team = 'B';

  v_team := CASE WHEN v_n_a <= v_n_b THEN 'A' ELSE 'B' END;

  UPDATE "tugofwar_players"
     SET team = v_team
   WHERE "id" = NEW."id";

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tugofwar_assign_team_on_join ON "tugofwar_players";
CREATE TRIGGER trg_tugofwar_assign_team_on_join
AFTER INSERT ON "tugofwar_players"
FOR EACH ROW
EXECUTE FUNCTION fn_tugofwar_assign_team_on_join();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) fn_tugofwar_assign_teams: open to ANY room member (host OR joiner)
--
-- The Flutter joinGame flow previously called this RPC after inserting a
-- player, but it was host-only — joiners' calls silently failed with
-- 'not_host'. The on-join trigger above now covers assignment, and this
-- relaxes the guard so any participant can rebalance unassigned players
-- without the host online (harmless: 'auto' mode only fills NULL teams
-- using the same smaller-team rule).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_tugofwar_assign_teams(p_game_id text, p_mode text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g record;
  v_n_a int; v_n_b int;
  r record;
  v_team text;
  v_i int := 0;
BEGIN
  SELECT status, "familyId" INTO g FROM "tugofwar_games" WHERE "id" = p_game_id;
  IF g.status IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  -- Any member of the family may rebalance (was host-only).
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember" fm
     WHERE fm."familyId" = g."familyId"
       AND fm."userId" = auth.uid()::text
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_family_member');
  END IF;
  IF g.status <> 'waiting' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_started');
  END IF;
  IF p_mode NOT IN ('auto','random') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_mode');
  END IF;

  IF p_mode = 'auto' THEN
    -- Unassigned players → the smaller team (join order breaks ties).
    FOR r IN
      SELECT id FROM "tugofwar_players"
       WHERE "gameId" = p_game_id AND team IS NULL
       ORDER BY "joinedAt" ASC, id ASC
    LOOP
      SELECT COUNT(*) INTO v_n_a FROM "tugofwar_players"
       WHERE "gameId" = p_game_id AND team = 'A';
      SELECT COUNT(*) INTO v_n_b FROM "tugofwar_players"
       WHERE "gameId" = p_game_id AND team = 'B';
      v_team := CASE WHEN v_n_a <= v_n_b THEN 'A' ELSE 'B' END;
      UPDATE "tugofwar_players" SET team = v_team WHERE id = r.id;
    END LOOP;
  ELSE
    -- Random: shuffle everyone, deal alternately → even halves.
    FOR r IN
      SELECT id FROM "tugofwar_players"
       WHERE "gameId" = p_game_id
       ORDER BY random()
    LOOP
      v_team := CASE WHEN v_i % 2 = 0 THEN 'A' ELSE 'B' END;
      UPDATE "tugofwar_players" SET team = v_team WHERE id = r.id;
      v_i := v_i + 1;
    END LOOP;
  END IF;

  SELECT COUNT(*) FILTER (WHERE team = 'A'), COUNT(*) FILTER (WHERE team = 'B')
    INTO v_n_a, v_n_b
    FROM "tugofwar_players" WHERE "gameId" = p_game_id;

  RETURN jsonb_build_object('ok', true, 'teamA', v_n_a, 'teamB', v_n_b);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_tugofwar_assign_teams(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Backfill: waiting rooms with unassigned players get balanced now
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  r record;
  v_n_a int;
  v_n_b int;
  v_team text;
  p record;
BEGIN
  FOR r IN
    SELECT DISTINCT "gameId" FROM "tugofwar_players"
     WHERE team IS NULL
       AND "gameId" IN (SELECT "id" FROM "tugofwar_games" WHERE status = 'waiting')
  LOOP
    FOR p IN
      SELECT id FROM "tugofwar_players"
       WHERE "gameId" = r."gameId" AND team IS NULL
       ORDER BY "joinedAt" ASC, id ASC
    LOOP
      SELECT COUNT(*) INTO v_n_a FROM "tugofwar_players"
       WHERE "gameId" = r."gameId" AND team = 'A';
      SELECT COUNT(*) INTO v_n_b FROM "tugofwar_players"
       WHERE "gameId" = r."gameId" AND team = 'B';
      v_team := CASE WHEN v_n_a <= v_n_b THEN 'A' ELSE 'B' END;
      UPDATE "tugofwar_players" SET team = v_team WHERE id = p.id;
    END LOOP;
  END LOOP;
END;
$$;
