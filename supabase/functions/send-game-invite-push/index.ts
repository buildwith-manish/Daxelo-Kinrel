// supabase/functions/send-game-invite-push/index.ts
//
// Edge Function: sends an FCM push notification for a game invite.
// Triggered by an AFTER INSERT trigger on the game_invites table
// (see migration 20260705181000_game_invites_and_push.sql).
//
// Payload (POST body):
//   { inviteId, gameType, gameId, roomCode, familyId, invitedUserId,
//     invitedByName, message, maxPlayers, currentPlayers }
//
// Behavior:
//   1. Look up the invited user's device_tokens from the device_tokens table.
//   2. Build the FCM payload (notification title/body + data deep link).
//   3. Call FCM HTTP v1 API using the service account.
//   4. If the user has no device tokens, silently succeed (in-app realtime
//      will still surface the invite if they're online).
//
// Foreground suppression: handled client-side — the Flutter app's
// PushNotificationService checks if the in-app GameInviteListener dialog
// is already showing and skips displaying the system notification.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const FCM_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FCM_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FCM_PRIVATE_KEY = (Deno.env.get("FIREBASE_PRIVATE_KEY") || "")
  .replace(/\\n/g, "\n");

interface InvitePayload {
  inviteId: string;
  gameType: string;
  gameId: string;
  roomCode?: string;
  familyId: string;
  invitedUserId: string;
  invitedByName?: string;
  message?: string;
  maxPlayers?: number;
  currentPlayers?: number;
}

async function getAccessToken(): Promise<string> {
  // Use google-auth-library to mint an OAuth2 access token for the FCM scope.
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const enc = (s: object) =>
    btoa(JSON.stringify(s)).replace(/=/g, "").replace(/\+/g, "-").replace(
      /\//g,
      "_",
    );
  const unsigned = `${enc(header)}.${enc(payload)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    await strToAb(FCM_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const t = await r.json();
  return t.access_token;
}

function strToAb(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  if (!FCM_PROJECT_ID || !FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
    return new Response(
      JSON.stringify({ ok: true, skipped: "FCM not configured" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  const p: InvitePayload = await req.json();

  // Look up the invited user's device tokens
  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("fcmToken, platform")
    .eq("userId", p.invitedUserId);

  if (error) {
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!tokens || tokens.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, skipped: "no device tokens" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  const gameName = gameDisplayName(p.gameType);
  const title = `${gameName} invite`;
  const body = p.message ??
    `${p.invitedByName ?? "A family member"} invited you to ${gameName}`;

  // Deep link: opens the app directly into the host's lobby with join code
  const deepLink =
    `daxelo-kinrel://game-invite?gameType=${p.gameType}&gameId=${p.gameId}` +
    `&familyId=${p.familyId}&roomCode=${p.roomCode ?? ""}`;

  const accessToken = await getAccessToken();
  const fcmUrl =
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`;

  let sent = 0;
  let failed = 0;
  for (const t of tokens) {
    const message = {
      token: t.fcmToken,
      notification: { title, body },
      data: {
        type: "game_invite",
        inviteId: p.inviteId,
        gameType: p.gameType,
        gameId: p.gameId,
        familyId: p.familyId,
        roomCode: p.roomCode ?? "",
        deepLink,
      },
      android: {
        priority: "high" as const,
        notification: { channelId: "game_invites", tag: p.inviteId },
      },
      apns: {
        payload: {
          aps: { badge: 1, sound: "default" },
        },
      },
    };

    try {
      const r = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ message }),
      });
      if (r.ok) sent++;
      else {
        failed++;
        // If token is invalid, remove it
        const err = await r.json();
        if (
          err.error?.details?.[0]?.reason ===
            "INVALID_ARGUMENT" ||
          err.error?.message?.includes("registration-token")
        ) {
          await supabase
            .from("device_tokens")
            .delete()
            .eq("fcmToken", t.fcmToken);
        }
      }
    } catch (_) {
      failed++;
    }
  }

  return new Response(
    JSON.stringify({ ok: true, sent, failed }),
    { headers: { "Content-Type": "application/json" } },
  );
});

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
