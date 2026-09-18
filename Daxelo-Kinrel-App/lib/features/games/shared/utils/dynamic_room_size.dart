// lib/features/games/shared/utils/dynamic_room_size.dart
//
// DynamicRoomSize — auto-scales the maxPlayers cap for a new room based on
// the family's size. Per the spec:
//
//   small family  (1-10 members)  → 8 players
//   medium family (11-25 members) → 16 players
//   large family  (26-50 members) → 25 players
//   very large    (51+ members)    → 32 players
//
// Rooms should feel active, not empty. The cap is a SOFT CAP — hosts can
// still override it in Advanced Settings. The actual maxPlayers for any
// given game is still bounded by that game's RoomConfig.maxPlayers.
//
// Usage:
//   final recommended = await ref.read(dynamicRoomSizeProvider(familyId).future);
//   final effective = min(recommended, RoomConfig.sos.maxPlayers);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';

/// Recommended maxPlayers for a new room in this family.
final dynamicRoomSizeProvider =
    FutureProvider.autoDispose.family<int, String>(
  (ref, familyId) async {
    final client = ref.watch(supabaseProvider);
    if (client == null) return 8; // sensible default
    try {
      final result = await client.rpc(
        'fn_compute_dynamic_room_size',
        params: {'p_family_id': familyId},
      );
      if (result is int) return result;
      if (result is num) return result.toInt();
      return 8;
    } catch (_) {
      return 8;
    }
  },
);

/// Pure-Dart helper for callers that already know the family member
/// count and want the recommendation without an RPC round-trip.
int recommendedRoomSizeForMemberCount(int memberCount) {
  if (memberCount <= 10) return 8;
  if (memberCount <= 25) return 16;
  if (memberCount <= 50) return 25;
  return 32;
}

/// Human-readable label for a family-size bucket.
String familySizeLabel(int memberCount) {
  if (memberCount <= 10) return 'Small Family';
  if (memberCount <= 25) return 'Medium Family';
  if (memberCount <= 50) return 'Large Family';
  return 'Very Large Family';
}
