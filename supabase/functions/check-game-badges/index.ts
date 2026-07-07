// supabase/functions/check-game-badges/index.ts
//
// Edge Function: evaluates game-related badge thresholds for a given user
// and awards newly-earned badges by inserting rows into UserBadge.
//
// Triggered by:
//   - POST from a Flutter board screen when it detects status='completed'
//     (body: { userId, familyId })
//   - Or by a future pg_cron job for periodic sweeps
//
// Badges evaluated:
//   - played-5-games-week: COUNT(game_participants WHERE userId=? AND
//     joinedAt >= now()-7d) >= 5
//   - win-streak-3: most recent 3 completed games for this user have
//     result='win'
//   - first-game-win: COUNT(result='win') >= 1 (only awards once)
//   - family-game-night-regular: COUNT(scheduled_game_nights WHERE
//     status='started' AND invitedUserIds contains userId) >= 4

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const { userId, familyId } = await req.json();
  if (!userId || !familyId) {
    return new Response(
      JSON.stringify({ ok: false, error: "userId and familyId required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const newlyEarned: { slug: string; name: string }[] = [];

  // Fetch already-earned badge IDs so we don't double-award
  const { data: earned } = await supabase
    .from("UserBadge")
    .select("badgeId")
    .eq("userId", userId)
    .eq("familyId", familyId);
  const earnedIds = new Set((earned || []).map((e) => e.badgeId));

  // Fetch all game badges
  const { data: gameBadges } = await supabase
    .from("Badge")
    .select("*")
    .eq("category", "games");
  if (!gameBadges || gameBadges.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, newlyEarned: [] }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  for (const badge of gameBadges) {
    if (earnedIds.has(badge.id)) continue;
    const qualifies = await checkQualification(badge.slug, userId, familyId);
    if (qualifies) {
      const { error } = await supabase
        .from("UserBadge")
        .insert({
          userId,
          badgeId: badge.id,
          familyId,
        });
      if (!error) {
        newlyEarned.push({ slug: badge.slug, name: badge.name });
      }
    }
  }

  return new Response(
    JSON.stringify({ ok: true, newlyEarned }),
    { headers: { "Content-Type": "application/json" } },
  );
});

async function checkQualification(
  slug: string,
  userId: string,
  familyId: string,
): Promise<boolean> {
  switch (slug) {
    case "played-5-games-week": {
      const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
        .toISOString();
      const { count } = await supabase
        .from("game_participants")
        .select("*", { count: "exact", head: true })
        .eq("userId", userId)
        .eq("familyId", familyId)
        .eq("role", "player")
        .gte("joinedAt", since);
      return (count ?? 0) >= 5;
    }
    case "win-streak-3": {
      // Get the user's 3 most recent completed games, check all 3 are wins
      const { data } = await supabase
        .from("game_participants")
        .select("result")
        .eq("userId", userId)
        .eq("familyId", familyId)
        .not("result", "is", null)
        .order("completedAt", { ascending: false })
        .limit(3);
      return (data ?? []).length === 3 &&
        data!.every((r) => r.result === "win");
    }
    case "first-game-win": {
      const { count } = await supabase
        .from("game_participants")
        .select("*", { count: "exact", head: true })
        .eq("userId", userId)
        .eq("familyId", familyId)
        .eq("result", "win");
      return (count ?? 0) >= 1;
    }
    case "family-game-night-regular": {
      // Count scheduled_game_nights where this user was invited AND it started
      // Postgres array contains: invitedUserIds @> ARRAY[userId]
      const { count } = await supabase
        .from("scheduled_game_nights")
        .select("*", { count: "exact", head: true })
        .eq("familyId", familyId)
        .eq("status", "started")
        .contains("invitedUserIds", [userId]);
      return (count ?? 0) >= 4;
    }
    default:
      return false;
  }
}
