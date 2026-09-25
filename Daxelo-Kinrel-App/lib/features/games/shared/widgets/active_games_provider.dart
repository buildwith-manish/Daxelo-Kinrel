// lib/features/games/shared/widgets/active_games_provider.dart
//
// Shared provider that fetches the family's active (in-progress / waiting)
// games via the get-active-family-games Edge Function.
//
// Introduced for the psychology-driven UX pass:
//   • Social Proof  — game cards show "👥 N active" / "{Name} is playing"
//     micro-labels derived from this data.
//   • Zeigarnik     — ActiveGamesList shows a pulsing "Your turn" badge on
//     games where it is the current user's move (turn info resolved
//     client-side against the per-game turn columns).
//
// The provider is autoDispose + family(familyId) so every surface that
// watches it (the family hub games row + the active games list) shares a
// single fetch per hub appearance instead of duplicating network calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../models/game_invite.dart';

/// A single active game row returned by the get-active-family-games
/// Edge Function.
class ActiveGameInfo {
  const ActiveGameInfo({
    required this.gameTable,
    required this.gameId,
    required this.gameType,
    required this.displayName,
    required this.hostUserName,
    required this.status,
    required this.spectatorsEnabled,
    required this.createdAt,
  });

  factory ActiveGameInfo.fromJson(Map<String, dynamic> json) {
    return ActiveGameInfo(
      gameTable: (json['gameTable'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      gameType: (json['gameType'] ?? '') as String,
      displayName: (json['displayName'] ?? 'Game') as String,
      hostUserName: (json['hostUserName'] ?? 'Family member') as String,
      status: (json['status'] ?? 'waiting') as String,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String gameTable;
  final String gameId;
  final String gameType;
  final String displayName;
  final String hostUserName;
  final String status;
  final bool spectatorsEnabled;
  final String createdAt;

  bool get isLive =>
      status == 'in_progress' || status == 'active' || status == 'countdown';

  GameType? get typedGameType => GameTypeX.fromRouteSegment(gameType);
}

/// Fetches the active games for a family (union across all game tables).
final familyActiveGamesProvider = FutureProvider.autoDispose
    .family<List<ActiveGameInfo>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <ActiveGameInfo>[];
  try {
    final resp = await client.functions.invoke(
      'get-active-family-games',
      queryParameters: {'familyId': familyId},
    ).timeout(const Duration(seconds: 15));
    final data = resp.data;
    if (data is! Map) return const <ActiveGameInfo>[];
    final games = (data['games'] as List?) ?? [];
    return games
        .whereType<Map>()
        .map((e) => ActiveGameInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return const <ActiveGameInfo>[];
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Turn detection (Zeigarnik effect — "Your turn" badges)
//
// Turn-based games store whose move it is in different columns:
//   • tictactoe / checkers / ludo / carrom / dotsboxes / antakshari:
//       <table>.currentTurnPlayerId (direct userId)
//   • chess: <table>.currentTurnColor ('white' | 'black') — resolved via
//       playerWhiteId / playerBlackId
//   • sos: <table>.currentTurnOrder (rotation index) — resolved via the
//       sos_players table (userId, turnOrder)
//
// All queries are batched per table (one `in` query per game type), and
// the whole pass is capped so a busy family hub never fires more than a
// handful of small selects.
// ═══════════════════════════════════════════════════════════════════════

/// Game tables with a direct `currentTurnPlayerId` column.
const Set<String> _kDirectTurnTables = {
  'tictactoe_games',
  'checkers_games',
  'ludo_games',
  'carrom_games',
  'dotsboxes_games',
  'antakshari_games',
};

/// Resolves which of the family's active games are waiting on the CURRENT
/// user's move. Returns the set of gameIds where it is the viewer's turn.
///
/// Non-turn-based games (Bingo, Freeze & Dash, party games…) are skipped —
/// there is no "your move" state for them.
final myTurnGameIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <String>{};
  final myId = client.auth.currentUser?.id;
  if (myId == null) return const <String>{};

  final games = await ref.watch(familyActiveGamesProvider(familyId).future);
  if (games.isEmpty) return const <String>{};

  final myTurn = <String>{};

  try {
    // ── Direct currentTurnPlayerId tables ───────────────────────────
    for (final table in _kDirectTurnTables) {
      final ids = games
          .where((g) => g.gameTable == table && g.isLive)
          .map((g) => g.gameId)
          .toSet();
      if (ids.isEmpty) continue;
      final rows = await client
          .from(table)
          .select('id, "currentTurnPlayerId"')
          .inFilter('id', ids.toList())
          .timeout(const Duration(seconds: 8));
      for (final row in (rows as List)) {
        final r = row as Map<String, dynamic>;
        if ((r['currentTurnPlayerId'] ?? '') == myId) {
          myTurn.add((r['id'] ?? '') as String);
        }
      }
    }

    // ── Chess: currentTurnColor + playerWhiteId / playerBlackId ─────
    final chessIds = games
        .where((g) => g.gameTable == 'chess_games' && g.isLive)
        .map((g) => g.gameId)
        .toSet();
    if (chessIds.isNotEmpty) {
      final rows = await client
          .from('chess_games')
          .select('id, "playerWhiteId", "playerBlackId", "currentTurnColor"')
          .inFilter('id', chessIds.toList())
          .timeout(const Duration(seconds: 8));
      for (final row in (rows as List)) {
        final r = row as Map<String, dynamic>;
        final isWhite = (r['currentTurnColor'] ?? 'white') == 'white';
        final activeId =
            (isWhite ? r['playerWhiteId'] : r['playerBlackId']) ?? '';
        if (activeId == myId) {
          myTurn.add((r['id'] ?? '') as String);
        }
      }
    }

    // ── SOS: currentTurnOrder resolved via sos_players ───────────────
    final sosIds = games
        .where((g) => g.gameTable == 'sos_games' && g.isLive)
        .map((g) => g.gameId)
        .toSet();
    if (sosIds.isNotEmpty) {
      final rows = await client
          .from('sos_games')
          .select('id, "currentTurnOrder"')
          .inFilter('id', sosIds.toList())
          .timeout(const Duration(seconds: 8));
      final players = await client
          .from('sos_players')
          .select('"gameId", "userId", "turnOrder"')
          .inFilter('gameId', sosIds.toList())
          .timeout(const Duration(seconds: 8));
      // Map gameId -> { turnOrder -> userId }
      final rotation = <String, Map<int, String>>{};
      for (final p in (players as List)) {
        final r = p as Map<String, dynamic>;
        final gid = (r['gameId'] ?? '') as String;
        final uid = (r['userId'] ?? '') as String;
        final order = (r['turnOrder'] as num?)?.toInt() ?? 0;
        rotation.putIfAbsent(gid, () => {})[order] = uid;
      }
      for (final row in (rows as List)) {
        final r = row as Map<String, dynamic>;
        final gid = (r['id'] ?? '') as String;
        final order = (r['currentTurnOrder'] as num?)?.toInt() ?? 0;
        if (rotation[gid]?[order] == myId) {
          myTurn.add(gid);
        }
      }
    }
  } catch (_) {
    // Turn resolution is best-effort — never break the hub over it.
  }

  return myTurn;
});
