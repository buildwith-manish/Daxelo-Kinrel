// supabase/functions/bingo-caller/index.ts
//
// Edge Function: advances the number-calling sequence for all in-progress
// Bingo games. Designed to be triggered by a Supabase Cron Schedule every
// 5 seconds (or the minimum call interval configured globally).
//
// For each in_progress game:
//   1. Check if enough time has passed since lastCallAt (callIntervalSeconds)
//   2. If yes, pick a random unclaimed number from 1-75
//   3. Append to numbersCalled, update lastCallAt
//   4. Realtime broadcasts the update to all players automatically
//
// The function is idempotent — if called multiple times within the
// interval, only the first call advances the sequence.
//
// Auth: invoked via Supabase's cron system with the service role key.
// No client auth needed.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

interface GameRow {
  id: string;
  familyId: string;
  callIntervalSeconds: number;
  numbersCalled: number[];
  lastCallAt: string | null;
}

Deno.serve(async (_req: Request) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'Missing env vars' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Fetch all in_progress bingo games
  const { data: games, error: fetchError } = await supabase
    .from('bingo_games')
    .select('id, "familyId", "callIntervalSeconds", "numbersCalled", "lastCallAt"')
    .eq('status', 'in_progress');

  if (fetchError) {
    return new Response(
      JSON.stringify({ error: 'Failed to fetch games', details: fetchError.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  if (!games || games.length === 0) {
    return new Response(
      JSON.stringify({ called: 0, message: 'No in-progress games' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const now = Date.now();
  const calledNumbers: Array<{ gameId: string; number: number | null }> = [];

  for (const game of games as GameRow[]) {
    // Check if enough time has passed since the last call
    const intervalMs = (game.callIntervalSeconds || 5) * 1000;
    if (game.lastCallAt) {
      const lastCallTime = new Date(game.lastCallAt).getTime();
      if (now - lastCallTime < intervalMs) {
        // Too soon — skip this game
        calledNumbers.push({ gameId: game.id, number: null });
        continue;
      }
    }

    // Compute available numbers (1-75 minus already-called)
    const calledSet = new Set(game.numbersCalled || []);
    const available: number[] = [];
    for (let i = 1; i <= 75; i++) {
      if (!calledSet.has(i)) available.push(i);
    }

    if (available.length === 0) {
      // All numbers called — no more to call
      calledNumbers.push({ gameId: game.id, number: null });
      continue;
    }

    // Pick a random available number
    const nextNumber = available[Math.floor(Math.random() * available.length)];

    // Append to numbersCalled and update lastCallAt
    const newNumbersCalled = [...(game.numbersCalled || []), nextNumber];
    const { error: updateError } = await supabase
      .from('bingo_games')
      .update({
        numbersCalled: newNumbersCalled,
        lastCallAt: new Date().toISOString(),
      })
      .eq('id', game.id);

    if (updateError) {
      console.error(`[bingo-caller] Failed to update game ${game.id}:`, updateError.message);
      calledNumbers.push({ gameId: game.id, number: null });
    } else {
      calledNumbers.push({ gameId: game.id, number: nextNumber });
    }
  }

  return new Response(
    JSON.stringify({
      called: calledNumbers.filter((c) => c.number !== null).length,
      skipped: calledNumbers.filter((c) => c.number === null).length,
      details: calledNumbers,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
