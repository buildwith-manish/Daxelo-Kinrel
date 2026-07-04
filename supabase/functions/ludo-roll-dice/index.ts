// supabase/functions/ludo-roll-dice/index.ts
//
// Edge Function: generates a server-authoritative dice roll (1-6) for
// a Ludo game. The result is stored in ludo_games.lastDiceRoll so all
// players see the identical roll via Realtime.
//
// Flow:
//   1. Receive { gameId, playerId } from the client
//   2. Verify it's the player's turn
//   3. Generate a random 1-6 using crypto-safe random
//   4. Update ludo_games.lastDiceRoll + consecutiveSixes counter
//   5. Return { diceValue, consecutiveSixes, extraTurnPending }
//
// The client NEVER generates dice values — this prevents manipulation.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

interface RollRequest {
  gameId: string;
  playerId: string;
}

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, content-type, x-client-info, apikey',
      },
    });
  }

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json',
  };

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: corsHeaders },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'Server not configured' }),
      { status: 500, headers: corsHeaders },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: RollRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: 'Invalid JSON body' }),
      { status: 400, headers: corsHeaders },
    );
  }

  const { gameId, playerId } = body;
  if (!gameId || !playerId) {
    return new Response(
      JSON.stringify({ error: 'Missing gameId or playerId' }),
      { status: 400, headers: corsHeaders },
    );
  }

  // 1. Fetch the game
  const { data: game, error: gameError } = await supabase
    .from('ludo_games')
    .select('id, status, "currentTurnPlayerId", "lastDiceRoll", "consecutiveSixes"')
    .eq('id', gameId)
    .single();

  if (gameError || !game) {
    return new Response(
      JSON.stringify({ error: 'Game not found' }),
      { status: 404, headers: corsHeaders },
    );
  }

  if (game.status !== 'in_progress') {
    return new Response(
      JSON.stringify({ error: 'Game is not in progress' }),
      { status: 400, headers: corsHeaders },
    );
  }

  // 2. Verify it's the player's turn
  if (game.currentTurnPlayerId !== playerId) {
    return new Response(
      JSON.stringify({ error: "It's not your turn" }),
      { status: 403, headers: corsHeaders },
    );
  }

  // Check if dice was already rolled (lastDiceRoll is not null and not yet consumed)
  if (game.lastDiceRoll !== null) {
    return new Response(
      JSON.stringify({
        error: 'Dice already rolled — move a token first',
        diceValue: game.lastDiceRoll,
      }),
      { status: 400, headers: corsHeaders },
    );
  }

  // 3. Generate a crypto-safe random 1-6
  const randomBytes = new Uint8Array(1);
  crypto.getRandomValues(randomBytes);
  const diceValue = (randomBytes[0] % 6) + 1;

  // 4. Update consecutive sixes counter
  let newConsecutiveSixes = diceValue === 6 ? (game.consecutiveSixes || 0) + 1 : 0;

  // Three consecutive sixes = forfeit turn
  let forfeited = false;
  let nextTurnPlayerId = game.currentTurnPlayerId;
  let extraTurnPending = false;

  if (newConsecutiveSixes >= 3) {
    // Forfeit — reset counter, pass turn to next player, clear dice
    forfeited = true;
    newConsecutiveSixes = 0;

    // Fetch all players to find next turn
    const { data: players } = await supabase
      .from('ludo_players')
      .select('userId, "turnOrder"')
      .eq('gameId', gameId)
      .order('turnOrder', { ascending: true });

    if (players && players.length > 0) {
      const currentIdx = players.findIndex((p: any) => p.userId === game.currentTurnPlayerId);
      const nextIdx = (currentIdx + 1) % players.length;
      nextTurnPlayerId = players[nextIdx].userId;
    }

    // Update game — clear dice roll, reset sixes, pass turn
    await supabase
      .from('ludo_games')
      .update({
        lastDiceRoll: null,
        consecutiveSixes: 0,
        extraTurnPending: false,
        currentTurnPlayerId: nextTurnPlayerId,
      })
      .eq('id', gameId);
  } else {
    // Normal roll — store the value
    extraTurnPending = diceValue === 6;

    await supabase
      .from('ludo_games')
      .update({
        lastDiceRoll: diceValue,
        consecutiveSixes: newConsecutiveSixes,
        extraTurnPending: extraTurnPending,
      })
      .eq('id', gameId);
  }

  return new Response(
    JSON.stringify({
      diceValue,
      consecutiveSixes: newConsecutiveSixes,
      extraTurnPending,
      forfeited,
      nextTurnPlayerId: forfeited ? nextTurnPlayerId : undefined,
    }),
    { status: 200, headers: corsHeaders },
  );
});
