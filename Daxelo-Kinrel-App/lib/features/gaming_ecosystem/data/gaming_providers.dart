// lib/features/gaming_ecosystem/data/gaming_providers.dart
//
// Riverpod providers for the Family Gaming Ecosystem. Every provider calls
// one ecosystem Supabase RPC and maps the jsonb into the typed models from
// gaming_models.dart.
//
// Providers:
//   • gamingDashboardProvider(familyId)      → fn_get_gaming_dashboard
//   • gamingLeaderboardProvider(key)         → fn_get_family_leaderboard_v2
//   • gamingChallengesProvider(key)          → fn_get_family_challenges
//   • gamingMatchHistoryProvider(key)        → fn_get_match_history
//   • gamingActivityProvider(key)            → fn_get_family_gaming_activity
//   • gamingPlayerProfileProvider(key)       → fn_get_player_gaming_profile
//   • gamingSeasonProvider(key)              → fn_get_gaming_dashboard
//   • gamingMilestonesProvider(familyId)     → fn_get_family_gaming_milestones
//   • matchEcosystemProvider(key)            → fn_get_match_ecosystem
//   • sendSportsmanship(...)                 → fn_send_sportsmanship
//
// All providers are autoDispose + keepAlive-off except the dashboard, which
// is kept alive briefly so hub → detail navigation doesn't refetch.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import 'gaming_models.dart';

Map<String, dynamic> _asMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const {};

List<Map<String, dynamic>> _asList(Object? raw) => raw is List
    ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

// ─────────────────────────────────────────────────────────────────────────
// Dashboard (hub)
// ─────────────────────────────────────────────────────────────────────────

final gamingDashboardProvider = FutureProvider.autoDispose
    .family<GamingDashboard, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) throw StateError('Supabase not ready');
  final myId = client.auth.currentUser?.id;
  if (myId == null) throw StateError('Not signed in');
  final raw = await client.rpc('fn_get_gaming_dashboard', params: {
    'p_family_id': familyId,
    'p_user_id': myId,
  });
  return GamingDashboard.fromJson(_asMap(raw));
});

// ─────────────────────────────────────────────────────────────────────────
// Leaderboards (weekly / monthly / all-time / per-game)
// ─────────────────────────────────────────────────────────────────────────

class LeaderboardKey {
  const LeaderboardKey({
    required this.familyId,
    this.period = 'all_time',
    this.gameTable,
  });
  final String familyId;
  final String period; // weekly | monthly | all_time
  final String? gameTable;

  @override
  bool operator ==(Object other) =>
      other is LeaderboardKey &&
      other.familyId == familyId &&
      other.period == period &&
      other.gameTable == gameTable;

  @override
  int get hashCode => Object.hash(familyId, period, gameTable);
}

final gamingLeaderboardProvider = FutureProvider.autoDispose
    .family<List<LeaderboardEntry>, LeaderboardKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <LeaderboardEntry>[];
  final myId = client.auth.currentUser?.id;
  // Pass the requester id so the RPC can strip wins/losses/winRate for
  // non-self rows and only expose streakCurrent for the viewer's own row.
  // If the user is somehow not signed in, fall back to NULL — the RPC will
  // then strip ALL rows defensively.
  final raw = await client.rpc('fn_get_family_leaderboard_v2', params: {
    'p_family_id': key.familyId,
    'p_period': key.period,
    'p_game_table': key.gameTable,
    'p_limit': 100,
    'p_requesting_user_id': myId,
  });
  final map = _asMap(raw);
  return _asList(map['entries'])
      .map(LeaderboardEntry.fromJson)
      .toList();
});

// ─────────────────────────────────────────────────────────────────────────
// Participation-based leaderboard (v3) — orders by games_played DESC,
// splits into ranked + notYetPlayed. Used by the home preview + the full
// leaderboard screen. The old points-based v2 is kept for backward
// compatibility (Family Cup still uses points internally).
// ─────────────────────────────────────────────────────────────────────────

/// A v3 leaderboard result: ranked rows + members who haven't played yet.
class ParticipationLeaderboard {
  const ParticipationLeaderboard({
    this.ranked = const [],
    this.notYetPlayed = const [],
  });
  final List<LeaderboardEntry> ranked;
  final List<NotYetPlayedMember> notYetPlayed;
}

class NotYetPlayedMember {
  const NotYetPlayedMember({
    required this.userId,
    required this.userName,
    this.avatarUrl,
  });
  final String userId;
  final String userName;
  final String? avatarUrl;

  factory NotYetPlayedMember.fromJson(Map<String, dynamic> json) {
    return NotYetPlayedMember(
      userId: (json['userId'] as String?) ?? '',
      userName: (json['userName'] as String?) ?? 'Family Member',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

final participationLeaderboardProvider = FutureProvider.autoDispose
    .family<ParticipationLeaderboard, LeaderboardKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const ParticipationLeaderboard();
  final myId = client.auth.currentUser?.id;
  try {
    final raw = await client.rpc('fn_get_family_leaderboard_v3', params: {
      'p_family_id': key.familyId,
      'p_period': key.period,
      'p_game_table': key.gameTable,
      'p_limit': 100,
      'p_requesting_user_id': myId,
    });
    final map = _asMap(raw);
    final ranked = _asList(map['ranked'])
        .map(LeaderboardEntry.fromJson)
        .toList();
    final notYetPlayed = _asList(map['notYetPlayed'])
        .map(NotYetPlayedMember.fromJson)
        .where((m) => m.userId.isNotEmpty)
        .toList();
    return ParticipationLeaderboard(ranked: ranked, notYetPlayed: notYetPlayed);
  } catch (_) {
    return const ParticipationLeaderboard();
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Challenges
// ─────────────────────────────────────────────────────────────────────────

final gamingChallengesProvider = FutureProvider.autoDispose
    .family<List<ChallengeInfo>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <ChallengeInfo>[];
  final myId = client.auth.currentUser?.id;
  if (myId == null) return const <ChallengeInfo>[];
  final raw = await client.rpc('fn_get_family_challenges', params: {
    'p_family_id': familyId,
    'p_user_id': myId,
  });
  return _asList(_asMap(raw)['challenges'])
      .map(ChallengeInfo.fromJson)
      .toList();
});

// ─────────────────────────────────────────────────────────────────────────
// Match history
// ─────────────────────────────────────────────────────────────────────────

class MatchHistoryKey {
  const MatchHistoryKey({required this.familyId, this.limit = 25});
  final String familyId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is MatchHistoryKey &&
      other.familyId == familyId &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(familyId, limit);
}

final gamingMatchHistoryProvider = FutureProvider.autoDispose
    .family<List<MatchHistoryEntry>, MatchHistoryKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <MatchHistoryEntry>[];
  final myId = client.auth.currentUser?.id;
  if (myId == null) return const <MatchHistoryEntry>[];
  // fn_get_match_history is now auth-gated server-side: it only returns
  // matches in which the requesting user (auth.uid()) participated. The
  // p_user_id parameter is preserved for backward compatibility but is
  // effectively ignored — a family member can no longer enumerate another
  // member's match history.
  final raw = await client.rpc('fn_get_match_history', params: {
    'p_user_id': myId,
    'p_family_id': key.familyId,
    'p_limit': key.limit,
    'p_offset': 0,
  });
  return _asList(_asMap(raw)['matches'])
      .map(MatchHistoryEntry.fromJson)
      .toList();
});

// ─────────────────────────────────────────────────────────────────────────
// Single-match detail (participant-gated)
// ─────────────────────────────────────────────────────────────────────────
//
// Wraps the new `match_history_for_participant` RPC. Returns the full match
// detail (winner, score, per-player results) ONLY if the requesting user
// was a participant. Returns null otherwise — the UI must NOT render any
// placeholder row when this returns null, so the match's existence is not
// confirmed to non-participants.
//
// Usage:
//   final detail = await ref.read(matchDetailProvider(MatchDetailKey(
//     familyId: familyId, matchId: matchId)).future);
//   if (detail == null) return SizedBox.shrink(); // not a participant
class MatchDetailKey {
  const MatchDetailKey({required this.familyId, required this.matchId});
  final String familyId;
  final String matchId;

  @override
  bool operator ==(Object other) =>
      other is MatchDetailKey &&
      other.familyId == familyId &&
      other.matchId == matchId;

  @override
  int get hashCode => Object.hash(familyId, matchId);
}

final matchDetailProvider = FutureProvider.autoDispose
    .family<MatchDetail?, MatchDetailKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return null;
  final myId = client.auth.currentUser?.id;
  if (myId == null) return null;
  final raw = await client.rpc('match_history_for_participant', params: {
    'p_match_id': key.matchId,
    'p_requesting_user_id': myId,
  });
  final map = _asMap(raw);
  if (map.isEmpty || map['matchId'] == null) return null;
  return MatchDetail.fromJson(map);
});

// ─────────────────────────────────────────────────────────────────────────
// Activity feed
// ─────────────────────────────────────────────────────────────────────────

class ActivityKey {
  const ActivityKey({required this.familyId, this.limit = 40});
  final String familyId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is ActivityKey &&
      other.familyId == familyId &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(familyId, limit);
}

final gamingActivityProvider = FutureProvider.autoDispose
    .family<List<ActivityEntry>, ActivityKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <ActivityEntry>[];
  final raw = await client.rpc('fn_get_family_gaming_activity', params: {
    'p_family_id': key.familyId,
    'p_limit': key.limit,
    'p_offset': 0,
  });
  return _asList(raw).map(ActivityEntry.fromJson).toList();
});

// ─────────────────────────────────────────────────────────────────────────
// Player profile
// ─────────────────────────────────────────────────────────────────────────

class PlayerProfileKey {
  const PlayerProfileKey({required this.familyId, required this.userId});
  final String familyId;
  final String userId;

  @override
  bool operator ==(Object other) =>
      other is PlayerProfileKey &&
      other.familyId == familyId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(familyId, userId);
}

final gamingPlayerProfileProvider = FutureProvider.autoDispose
    .family<PlayerGamingProfile, PlayerProfileKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) throw StateError('Supabase not ready');
  final raw = await client.rpc('fn_get_player_gaming_profile', params: {
    'p_user_id': key.userId,
    'p_family_id': key.familyId,
  });
  return PlayerGamingProfile.fromJson(_asMap(raw));
});

// ─────────────────────────────────────────────────────────────────────────
// Milestones
// ─────────────────────────────────────────────────────────────────────────

class GamingMilestones {
  const GamingMilestones({
    this.totalMatches = 0,
    this.distinctGames = 0,
    this.lastMatchAt,
    this.milestones = const [],
  });
  final int totalMatches;
  final int distinctGames;
  final DateTime? lastMatchAt;
  final List<MilestoneInfo> milestones;
}

final gamingMilestonesProvider = FutureProvider.autoDispose
    .family<GamingMilestones, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) {
    return const GamingMilestones();
  }
  final raw = await client.rpc('fn_get_family_gaming_milestones', params: {
    'p_family_id': familyId,
  });
  final map = _asMap(raw);
  return GamingMilestones(
    totalMatches: (map['totalMatches'] as num?)?.toInt() ?? 0,
    distinctGames: (map['distinctGames'] as num?)?.toInt() ?? 0,
    lastMatchAt: map['lastMatchAt'] == null
        ? null
        : DateTime.tryParse(map['lastMatchAt'].toString()),
    milestones: _asList(map['milestones'])
        .map(MilestoneInfo.fromJson)
        .toList(),
  );
});

// ─────────────────────────────────────────────────────────────────────────
// Match ecosystem (post-match rewards)
// ─────────────────────────────────────────────────────────────────────────

class MatchEcosystemKey {
  const MatchEcosystemKey({required this.gameTable, required this.gameId});
  final String gameTable;
  final String gameId;

  @override
  bool operator ==(Object other) =>
      other is MatchEcosystemKey &&
      other.gameTable == gameTable &&
      other.gameId == gameId;

  @override
  int get hashCode => Object.hash(gameTable, gameId);
}

final matchEcosystemProvider = FutureProvider.autoDispose
    .family<MatchEcosystemResult?, MatchEcosystemKey>((ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return null;
  Future<Object?> call() => client.rpc('fn_get_match_ecosystem', params: {
        'p_game_table': key.gameTable,
        'p_game_id': key.gameId,
      });
  try {
    var raw = await call();
    if (raw == null) {
      // The results screen can render in the same tick the winning move's
      // UPDATE commits — give the row a moment and try once more.
      await Future.delayed(const Duration(milliseconds: 2500));
      raw = await call();
    }
    if (raw == null) return null;
    return MatchEcosystemResult.fromJson(_asMap(raw));
  } catch (e) {
    debugPrint('[GamingEcosystem] matchEcosystem error: $e');
    return null;
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Family play streak ("Family Game Night" ritual)
// ─────────────────────────────────────────────────────────────────────────

final familyPlayStreakProvider = FutureProvider.autoDispose
    .family<FamilyPlayStreak, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const FamilyPlayStreak();
  try {
    final raw = await client.rpc('fn_get_family_play_streak', params: {
      'p_family_id': familyId,
    });
    if (raw == null) return const FamilyPlayStreak();
    return FamilyPlayStreak.fromJson(_asMap(raw));
  } catch (e) {
    debugPrint('[GamingEcosystem] play streak error: $e');
    return const FamilyPlayStreak();
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Sportsmanship
// ─────────────────────────────────────────────────────────────────────────

/// Sends a post-match sportsmanship note via fn_send_sportsmanship.
/// Returns the newly earned badges (if any) so the caller can celebrate.
Future<List<BadgeInfo>> sendSportsmanship({
  required WidgetRef ref,
  required String matchId,
  required String gameTable,
  required String familyId,
  required String toUserId,
  String? toName,
  String kind = 'gg',
  String? message,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return const <BadgeInfo>[];
  try {
    final raw = await client.rpc('fn_send_sportsmanship', params: {
      'p_match_id': matchId,
      'p_game_table': gameTable,
      'p_family_id': familyId,
      'p_to_user_id': toUserId,
      'p_to_name': toName,
      'p_kind': kind,
      'p_message': message,
    });
    return _asList(_asMap(raw)['newBadges']).map(BadgeInfo.fromJson).toList();
  } catch (e) {
    debugPrint('[GamingEcosystem] sportsmanship error: $e');
    return const <BadgeInfo>[];
  }
}

/// Refreshes every ecosystem provider (called after a match is archived so
/// the hub / leaderboard / challenges reflect the new data immediately).
void invalidateGamingProviders(Ref ref) {
  ref.invalidate(gamingDashboardProvider);
  ref.invalidate(gamingChallengesProvider);
  ref.invalidate(gamingLeaderboardProvider);
  ref.invalidate(gamingMatchHistoryProvider);
  ref.invalidate(gamingActivityProvider);
  // ── QA fix 2026-09-21: these providers were missing — the hub showed
  // stale leaderboard / milestones / streak data until the user pulled
  // to refresh after finishing a match.
  ref.invalidate(participationLeaderboardProvider);
  ref.invalidate(gamingMilestonesProvider);
  ref.invalidate(familyPlayStreakProvider);
}
