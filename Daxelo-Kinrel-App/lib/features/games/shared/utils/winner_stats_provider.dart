// lib/features/games/shared/utils/winner_stats_provider.dart
//
// WinnerStatsProvider — fetches per-user win statistics for the
// WinCelebration screen via the fn_get_user_win_stats RPC.
//
// Returned shape (from the RPC):
//   {
//     "totalWins": 17,
//     "monthlyWins": 8,
//     "familyWins": 23,
//     "familyWinNumber": 23,
//     "totalGames": 42,
//     "currentStreak": 3
//   }
//
// Usage in a game's results screen:
//   final statsAsync = ref.watch(winnerStatsProvider((
//     userId: winnerId, familyId: familyId)));
//   statsAsync.when(
//     data: (stats) => WinCelebration(
//       config: WinCelebrationConfig(
//         winnerNames: [winnerName],
//         reactions: [...],
//         gameName: 'Bingo',
//         winnerStats: stats,
//       ),
//       ...
//     ),
//     loading: () => WinCelebration(...stats: null...),
//     error: (_, __) => WinCelebration(...stats: null...),
//   );

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../widgets/win_celebration.dart';

/// Composite key for the winnerStatsProvider family.
class WinnerStatsKey {
  const WinnerStatsKey({required this.userId, required this.familyId});
  final String userId;
  final String familyId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WinnerStatsKey &&
          other.userId == userId &&
          other.familyId == familyId);

  @override
  int get hashCode => Object.hash(userId, familyId);
}

/// Fetches [WinnerStats] for a given (userId, familyId).
final winnerStatsProvider =
    FutureProvider.autoDispose.family<WinnerStats, WinnerStatsKey>(
  (ref, key) async {
    final client = ref.watch(supabaseProvider);
    if (client == null) return const WinnerStats();
    try {
      final result = await client.rpc(
        'fn_get_user_win_stats',
        params: {
          'p_user_id': key.userId,
          'p_family_id': key.familyId,
        },
      );
      if (result is! Map) return const WinnerStats();
      final json = Map<String, dynamic>.from(result);
      return WinnerStats(
        familyWinNumber: _asInt(json['familyWinNumber']),
        monthlyWins: _asInt(json['monthlyWins']),
        totalWins: _asInt(json['totalWins']),
        currentStreak: _asInt(json['currentStreak']),
      );
    } catch (_) {
      return const WinnerStats();
    }
  },
);

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
