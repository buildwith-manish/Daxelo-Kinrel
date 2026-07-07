// supabase/functions/get-active-family-games/index.ts
//
// Edge Function: returns all in-progress or waiting games for a given
// family, unioned across all 14 game tables. Used by the family detail
// screen's "Active Games" section (which is also the spectator entry point).
//
// Query param: ?familyId=<uuid>
// Returns: [{ gameTable, gameId, gameType, hostUserName, status,
//             playersCount, spectatorsEnabled, createdAt, ... }]
//
// The union logic is intentionally simple — family game volume is low, so
// we just fire 14 parallel SELECTs and merge. For higher-scale apps this
// would be a single SECURITY DEFINER RPC, but at family scale the
// parallelism is faster to ship and easier to maintain.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
);

interface GameTableConfig {
  table: string;
  gameType: string;
  displayName: string;
  activeStatuses: string[];
  // Function to extract player count from the game row (some games have it
  // inline, others need a separate query against the _players table)
  inlinePlayerCountColumn?: string;
  // For games with no inline player count, the _players table to COUNT
  playersTable?: string;
  playersTableFk?: string; // column on playersTable that references the game
}

const TABLES: GameTableConfig[] = [
  {
    table: "bingo_games", gameType: "bingo", displayName: "Bingo",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "bingo_cards", playersTableFk: "gameId",
  },
  {
    table: "ludo_games", gameType: "ludo", displayName: "Ludo",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "ludo_players", playersTableFk: "gameId",
  },
  {
    table: "checkers_games", gameType: "checkers", displayName: "Checkers",
    activeStatuses: ["waiting", "in_progress"],
    inlinePlayerCountColumn: null, // always 2
  },
  {
    table: "carrom_games", gameType: "carrom", displayName: "Carrom",
    activeStatuses: ["waiting", "in_progress"],
  },
  {
    table: "chess_games", gameType: "chess", displayName: "Chess",
    activeStatuses: ["waiting", "in_progress"],
  },
  {
    table: "sos_games", gameType: "sos", displayName: "SOS",
    activeStatuses: ["lobby", "active"],
    playersTable: "sos_players", playersTableFk: "gameId",
  },
  {
    table: "antakshari_games", gameType: "antakshari", displayName: "Antakshari",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "antakshari_players", playersTableFk: "gameId",
  },
  {
    table: "tictactoe_games", gameType: "tictactoe", displayName: "Tic-Tac-Toe",
    activeStatuses: ["waiting", "in_progress"],
  },
  {
    table: "truthordare_games", gameType: "truthordare", displayName: "Truth or Dare",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "truthordare_players", playersTableFk: "gameId",
  },
  {
    table: "twotruths_games", gameType: "twotruths", displayName: "Two Truths and a Lie",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "twotruths_players", playersTableFk: "gameId",
  },
  {
    table: "dotsboxes_games", gameType: "dotsboxes", displayName: "Dots and Boxes",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "dotsboxes_players", playersTableFk: "gameId",
  },
  {
    table: "nameplace_games", gameType: "nameplace", displayName: "Name, Place, Animal, Thing",
    activeStatuses: ["waiting", "in_progress"],
    playersTable: "nameplace_players", playersTableFk: "gameId",
  },
  {
    table: "chitmatch_games", gameType: "chitmatch", displayName: "TripleMatch",
    activeStatuses: ["waiting", "setup", "in_progress"],
    playersTable: "chitmatch_players", playersTableFk: "gameId",
  },
  {
    table: "redlight_rounds", gameType: "freeze-dash", displayName: "Freeze & Dash",
    activeStatuses: ["lobby", "countdown", "active"],
    playersTable: "redlight_players", playersTableFk: "roundId",
  },
];

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const familyId = url.searchParams.get("familyId");
  if (!familyId) {
    return new Response(
      JSON.stringify({ ok: false, error: "familyId required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const results: any[] = [];

  await Promise.all(TABLES.map(async (cfg) => {
    const { data, error } = await supabase
      .from(cfg.table)
      .select("id, familyId, hostUserName, status, spectatorsEnabled, createdAt, startedAt")
      .eq("familyId", familyId)
      .in("status", cfg.activeStatuses)
      .order("createdAt", { ascending: false })
      .limit(20);

    if (error || !data) return;

    for (const row of data) {
      results.push({
        gameTable: cfg.table,
        gameId: row.id,
        gameType: cfg.gameType,
        displayName: cfg.displayName,
        hostUserName: row.hostUserName,
        status: row.status,
        spectatorsEnabled: row.spectatorsEnabled ?? true,
        createdAt: row.createdAt,
        startedAt: row.startedAt,
      });
    }
  }));

  // Sort all results by createdAt desc
  results.sort((a, b) =>
    new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
  );

  return new Response(
    JSON.stringify({ ok: true, games: results.slice(0, 50) }),
    { headers: { "Content-Type": "application/json" } },
  );
});
