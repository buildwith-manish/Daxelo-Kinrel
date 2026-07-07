// supabase/functions/bingo-verify-claim/index.ts
//
// Edge Function: verifies a BINGO claim server-side before accepting the win.
// Invoked by the player's client when they tap "BINGO!".
//
// Flow:
//   1. Receive { gameId, playerId } from the client
//   2. Call the bingo_verify_claim RPC (SECURITY DEFINER) to check the
//      player's marked numbers against the called numbers + win pattern
//   3. Insert a bingo_claims row with isValid=true/false
//   4. If valid, update the bingo_games row with the winner + status=completed
//   5. Return { valid: bool, reason?: string, winner?: {...} }
//
// This is server-authoritative — the client NEVER decides if a claim is valid.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

interface VerifyRequest {
  gameId: string;
  playerId: string;
}

Deno.serve(async (req: Request) => {
  // CORS preflight
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

  let body: VerifyRequest;
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

  // 1. Fetch the game and card to get player name
  const { data: game, error: gameError } = await supabase
    .from('bingo_games')
    .select('id, status, "winnerPlayerId"')
    .eq('id', gameId)
    .single();

  if (gameError || !game) {
    return new Response(
      JSON.stringify({ valid: false, reason: 'Game not found' }),
      { status: 404, headers: corsHeaders },
    );
  }

  if (game.status !== 'in_progress') {
    return new Response(
      JSON.stringify({ valid: false, reason: 'Game is not in progress' }),
      { status: 400, headers: corsHeaders },
    );
  }

  // If there's already a winner, reject this claim
  if (game.winnerPlayerId) {
    return new Response(
      JSON.stringify({ valid: false, reason: 'A winner has already been declared' }),
      { status: 400, headers: corsHeaders },
    );
  }

  // Fetch card to get player name
  const { data: card } = await supabase
    .from('bingo_cards')
    .select('"playerName"')
    .eq('gameId', gameId)
    .eq('playerId', playerId)
    .single();

  const playerName = card?.playerName || 'Player';

  // 2. Call the verify RPC
  const { data: verifyResult, error: rpcError } = await supabase
    .rpc('bingo_verify_claim', {
      claim_game_id: gameId,
      claim_player_id: playerId,
    });

  if (rpcError) {
    return new Response(
      JSON.stringify({ valid: false, reason: `Verification failed: ${rpcError.message}` }),
      { status: 500, headers: corsHeaders },
    );
  }

  const isValid = verifyResult?.valid === true;
  const reason = verifyResult?.reason;

  // 3. Insert the claim row (audit trail)
  await supabase.from('bingo_claims').insert({
    gameId,
    playerId,
    playerName,
    isValid,
    invalidReason: isValid ? null : reason,
    verifiedAt: new Date().toISOString(),
  });

  // 4. If valid, mark the player as the winner and complete the game
  if (isValid) {
    const { error: updateError } = await supabase
      .from('bingo_games')
      .update({
        status: 'completed',
        winnerPlayerId: playerId,
        winnerPlayerName: playerName,
        completedAt: new Date().toISOString(),
      })
      .eq('id', gameId);

    if (updateError) {
      console.error('[bingo-verify-claim] Failed to update game:', updateError.message);
      return new Response(
        JSON.stringify({ valid: false, reason: 'Failed to record win' }),
        { status: 500, headers: corsHeaders },
      );
    }

    // Also mark the card as claimed
    await supabase
      .from('bingo_cards')
      .update({ hasClaimed: true })
      .eq('gameId', gameId)
      .eq('playerId', playerId);

    return new Response(
      JSON.stringify({
        valid: true,
        winner: { playerId, playerName },
      }),
      { status: 200, headers: corsHeaders },
    );
  }

  // 5. Invalid claim
  return new Response(
    JSON.stringify({ valid: false, reason: reason || 'Claim is not valid' }),
    { status: 200, headers: corsHeaders },
  );
});
