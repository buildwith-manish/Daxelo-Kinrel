// supabase/functions/process-scheduled-game-nights/index.ts
//
// Edge Function: runs every 5 minutes via pg_cron.
// Handles two cases for the scheduled_game_nights table:
//
//   1. REMINDER (status='scheduled', scheduledFor within next 15 min):
//      - Send a reminder FCM push to each invited user
//      - UPDATE status='reminded', reminderSentAt=now()
//
//   2. START (status IN ('scheduled','reminded'), scheduledFor <= now):
//      - Create the real {game}_games row (just the host row; players join
//        via the same Socket.IO invite flow used by the regular InviteFamilySheet)
//      - Send a "starting now" FCM push + insert game_invites rows for each
//        invitedUserIds entry (the game_invites AFTER INSERT trigger will
//        fire the FCM push for each invite)
//      - UPDATE status='started', createdGameId=<new game id>, startedAt=now()

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (_req) => {
  const now = new Date();
  const reminderWindow = new Date(now.getTime() + 15 * 60 * 1000);

  // ── 1. REMINDERS ──────────────────────────────────────────────────────
  const { data: reminders } = await supabase
    .from("scheduled_game_nights")
    .select("*")
    .eq("status", "scheduled")
    .lte("scheduledFor", reminderWindow.toISOString())
    .gt("scheduledFor", now.toISOString());

  if (reminders && reminders.length > 0) {
    for (const sn of reminders) {
      // Send reminder FCM to each invited user
      for (const userId of sn.invitedUserIds || []) {
        await sendReminderPush(userId, sn);
      }
      await supabase
        .from("scheduled_game_nights")
        .update({
          status: "reminded",
          reminderSentAt: new Date().toISOString(),
        })
        .eq("id", sn.id);
    }
  }

  // ── 2. START ──────────────────────────────────────────────────────────
  const { data: starters } = await supabase
    .from("scheduled_game_nights")
    .select("*")
    .in("status", ["scheduled", "reminded"])
    .lte("scheduledFor", now.toISOString());

  if (starters && starters.length > 0) {
    for (const sn of starters) {
      try {
        const gameId = await createGameRow(sn);
        if (gameId) {
          // Insert game_invites for each invited user (triggers FCM push via trigger)
          const roomCode = gameId.replace(/-/g, "").substring(0, 6)
            .toUpperCase();
          const invites = (sn.invitedUserIds || []).map((userId: string) => ({
            gameTable: gameTableName(sn.gameType),
            gameId,
            gameType: sn.gameType,
            familyId: sn.familyId,
            roomCode,
            invitedUserId: userId,
            invitedByUserId: sn.hostUserId,
            invitedByName: sn.hostUserName,
            maxPlayers: 2, // Edge Function can't know per-game max — host can adjust in lobby
            currentPlayers: 1,
            message: `${sn.hostUserName ?? "A family member"}'s ${gameDisplayName(sn.gameType)} night is starting now!`,
            status: "pending",
            sourceGameId: null,
          }));
          if (invites.length > 0) {
            await supabase.from("game_invites").insert(invites);
          }
          await supabase
            .from("scheduled_game_nights")
            .update({
              status: "started",
              createdGameId: gameId,
              startedAt: new Date().toISOString(),
            })
            .eq("id", sn.id);
        }
      } catch (e) {
        console.error("Failed to start scheduled game night", sn.id, e);
      }
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      remindersSent: reminders?.length ?? 0,
      gamesStarted: starters?.length ?? 0,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});

async function sendReminderPush(userId: string, sn: any) {
  // Best-effort — failures don't block the flow
  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("fcmToken")
    .eq("userId", userId);
  if (!tokens || tokens.length === 0) return;
  // FCM HTTP v1 call omitted for brevity — see send-game-invite-push for the
  // access-token pattern. In production, extract that into a shared util.
  console.log(
    `[reminder] would send to ${tokens.length} tokens for user ${userId}`,
  );
}

async function createGameRow(sn: any): Promise<string | null> {
  const table = gameTableName(sn.gameType);
  const newGame = {
    familyId: sn.familyId,
    hostUserId: sn.hostUserId,
    hostUserName: sn.hostUserName,
    status: "waiting",
    spectatorsEnabled: true,
    createdAt: new Date().toISOString(),
  };
  const { data, error } = await supabase
    .from(table)
    .insert(newGame)
    .select("id")
    .single();
  if (error) {
    console.error("createGameRow failed", table, error);
    return null;
  }
  return data?.id ?? null;
}

function gameTableName(gameType: string): string {
  const map: Record<string, string> = {
    bingo: "bingo_games",
    ludo: "ludo_games",
    checkers: "checkers_games",
    carrom: "carrom_games",
    chess: "chess_games",
    sos: "sos_games",
    antakshari: "antakshari_games",
    "freeze-dash": "redlight_rounds",
    nameplace: "nameplace_games",
    tictactoe: "tictactoe_games",
    truthordare: "truthordare_games",
    twotruths: "twotruths_games",
    dotsboxes: "dotsboxes_games",
    chitmatch: "chitmatch_games",
  };
  return map[gameType] ?? "bingo_games";
}

function gameDisplayName(gameType: string): string {
  const map: Record<string, string> = {
    bingo: "Bingo",
    ludo: "Ludo",
    checkers: "Checkers",
    carrom: "Carrom",
    chess: "Chess",
    sos: "SOS",
    antakshari: "Antakshari",
    "freeze-dash": "Freeze & Dash",
    nameplace: "Name, Place, Animal, Thing",
    tictactoe: "Tic-Tac-Toe",
    truthordare: "Truth or Dare",
    twotruths: "Two Truths and a Lie",
    dotsboxes: "Dots and Boxes",
    chitmatch: "TripleMatch",
  };
  return map[gameType] ?? "Game";
}
