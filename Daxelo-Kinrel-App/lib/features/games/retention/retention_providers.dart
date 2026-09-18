// lib/features/games/retention/retention_providers.dart
//
// Riverpod providers for all 4 retention systems:
//   • coinBalanceProvider — fetches user's coin balance
//   • rewardsProvider — fetches unlockable rewards catalog
//   • unlockedRewardsProvider — fetches user's unlocked reward IDs
//   • customContentProvider — fetches family-authored game content
//   • activeThemeProvider — fetches the current seasonal theme
//   • livePresenceProvider — fetches family last-seen/online status

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import 'coin_models.dart';

// ─────────────────────────────────────────────────────────────────────────
// System 1: Coin balance + rewards
// ─────────────────────────────────────────────────────────────────────────

final coinBalanceProvider = FutureProvider.autoDispose
    .family<CoinBalance, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const CoinBalance();
  final myId = client.auth.currentUser?.id;
  if (myId == null) return const CoinBalance();
  try {
    final raw = await client.rpc('get_coin_balance', params: {
      'p_user_id': myId,
      'p_family_id': familyId,
    });
    if (raw is Map) {
      return CoinBalance.fromJson(Map<String, dynamic>.from(raw));
    }
    return const CoinBalance();
  } catch (e) {
    debugPrint('[Retention] coinBalance error: $e');
    return const CoinBalance();
  }
});

final rewardsProvider = FutureProvider.autoDispose
    .family<List<UnlockableReward>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const [];
  try {
    final raw = await client
        .from('unlockable_rewards')
        .select()
        .eq('isActive', true)
        .order('cost');
    final myId = client.auth.currentUser?.id;
    Set<String> unlockedIds = {};
    if (myId != null) {
      final unlocked = await client
          .from('user_unlocked_rewards')
          .select('rewardId')
          .eq('userId', myId)
          .eq('familyId', familyId);
      unlockedIds = unlocked
          .map((r) => r['rewardId'] as String?)
          .whereType<String>()
          .toSet();
    }
    return raw
        .map((r) => UnlockableReward.fromJson(r).copyWith(
              isUnlocked: unlockedIds.contains(r['id']),
            ))
        .toList();
  } catch (e) {
    debugPrint('[Retention] rewards error: $e');
    return const [];
  }
});

/// Award coins for a match completion. Called from game providers after
/// fn__archive_family_match fires. Safe to call from any game's completion
/// path — the RPC is idempotent (inserts a ledger entry; the trigger
/// updates the balance).
Future<void> awardCoinsForMatch({
  required WidgetRef ref,
  required String userId,
  required String familyId,
  required String reason, // 'match_complete' | 'win_streak' | etc.
  String? referenceId,
  int amount = 10,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return;
  try {
    await client.rpc('award_coins', params: {
      'p_user_id': userId,
      'p_family_id': familyId,
      'p_amount': amount,
      'p_reason': reason,
      'p_reference_id': referenceId,
    });
  } catch (e) {
    debugPrint('[Retention] award_coins error: $e');
  }
}

/// Redeem a reward. Returns true on success, false on failure.
Future<bool> redeemReward({
  required WidgetRef ref,
  required String familyId,
  required String rewardId,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return false;
  final myId = client.auth.currentUser?.id;
  if (myId == null) return false;
  try {
    final raw = await client.rpc('redeem_reward', params: {
      'p_user_id': myId,
      'p_family_id': familyId,
      'p_reward_id': rewardId,
    });
    if (raw is Map) {
      return raw['ok'] == true;
    }
    return false;
  } catch (e) {
    debugPrint('[Retention] redeem error: $e');
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// System 2: Custom content
// ─────────────────────────────────────────────────────────────────────────

final customContentProvider = FutureProvider.autoDispose
    .family<List<CustomContent>, ({String familyId, String gameType})>(
        (ref, key) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const [];
  try {
    final raw = await client.rpc('get_game_content', params: {
      'p_family_id': key.familyId,
      'p_game_type': key.gameType,
    });
    if (raw is Map) {
      final list = raw['customContent'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) =>
                CustomContent.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    return const [];
  } catch (e) {
    debugPrint('[Retention] customContent error: $e');
    return const [];
  }
});

/// Submit custom content for a game. Returns true on success.
Future<bool> submitCustomContent({
  required WidgetRef ref,
  required String familyId,
  required String gameType,
  required Map<String, dynamic> contentJson,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return false;
  final myId = client.auth.currentUser?.id;
  if (myId == null) return false;
  try {
    await client.from('family_custom_content').insert({
      'familyId': familyId,
      'gameType': gameType,
      'contentJson': contentJson,
      'createdBy': myId,
    });
    return true;
  } catch (e) {
    debugPrint('[Retention] submitCustomContent error: $e');
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// System 3: Live presence
// ─────────────────────────────────────────────────────────────────────────

class FamilyPresenceMember {
  const FamilyPresenceMember({
    required this.userId,
    required this.userName,
    required this.isOnline,
    this.lastSeenAt,
  });

  final String userId;
  final String userName;
  final bool isOnline;
  final DateTime? lastSeenAt;

  factory FamilyPresenceMember.fromJson(Map<String, dynamic> json) {
    return FamilyPresenceMember(
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Family Member') as String,
      isOnline: (json['isOnline'] as bool?) ?? false,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'] as String)
          : null,
    );
  }
}

final livePresenceProvider = FutureProvider.autoDispose
    .family<List<FamilyPresenceMember>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const [];
  try {
    final raw = await client.rpc('get_family_last_seen', params: {
      'p_family_id': familyId,
    });
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => FamilyPresenceMember.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  } catch (e) {
    debugPrint('[Retention] livePresence error: $e');
    return const [];
  }
});

// ─────────────────────────────────────────────────────────────────────────
// System 4: Seasonal themes
// ─────────────────────────────────────────────────────────────────────────

final activeThemeProvider = FutureProvider.autoDispose<SeasonalTheme?>((ref) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return null;
  try {
    final raw = await client.rpc('get_active_seasonal_theme');
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) {
        return SeasonalTheme.fromJson(Map<String, dynamic>.from(first));
      }
    }
    return null;
  } catch (e) {
    debugPrint('[Retention] activeTheme error: $e');
    return null;
  }
});
