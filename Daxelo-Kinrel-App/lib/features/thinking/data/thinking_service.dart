// lib/features/thinking/data/thinking_service.dart
//
// "Thinking of You" — Supabase RPC client for the tap feature.
//
// v109.5: Replaced the NestJS backend (Dio /api/v1/thinking/tap) with a
// Supabase SECURITY DEFINER RPC (fn_send_thinking_of_you) that:
//   1. Creates a personalized notification for the receiver
//   2. Enforces a 12-hour cooldown per sender→receiver pair
//   3. Stores an analytics event for engagement insights
//   4. Returns a random warm message (❤️ / 🌟 / 💭 / 🫶)
//
// The old NestJS endpoint required a running backend server and used
// a different auth scheme (ES256/HS256 mismatch). The Supabase RPC
// uses the same auth session the Flutter app already has — no extra
// auth configuration needed.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class ThinkingResult {
  const ThinkingResult({
    required this.success,
    this.message,
    this.error,
    this.cooldownHours,
  });

  final bool success;
  final String? message;
  final String? error;
  final int? cooldownHours;
}

class ThinkingService {
  ThinkingService(this._ref);
  final Ref _ref;

  /// Sends a "Thinking of You" notification to [receiverId] in the
  /// context of [familyId]. The RPC creates a personalized notification
  /// with a random warm message, enforces a 12-hour cooldown, and
  /// stores an analytics event.
  ///
  /// Returns a [ThinkingResult] indicating success/failure. If the
  /// cooldown is active, [ThinkingResult.error] is 'cooldown' and
  /// [ThinkingResult.cooldownHours] is 12.
  Future<ThinkingResult> sendTap({
    required String receiverId,
    required String familyId,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        return const ThinkingResult(success: false, error: 'Supabase not ready');
      }

      final response = await client.rpc(
        'fn_send_thinking_of_you',
        params: {
          'p_receiver_id': receiverId,
          'p_family_id': familyId,
        },
      ).timeout(const Duration(seconds: 8));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;

      if (success) {
        return ThinkingResult(
          success: true,
          message: result?['message'] as String?,
        );
      } else {
        return ThinkingResult(
          success: false,
          error: result?['error'] as String?,
          message: result?['message'] as String?,
          cooldownHours: result?['cooldownHours'] as int?,
        );
      }
    } catch (e) {
      debugPrint('⚠️ ThinkingService.sendTap error: $e');
      return const ThinkingResult(success: false, error: 'network_error');
    }
  }
}

final thinkingServiceProvider = Provider<ThinkingService>((ref) {
  return ThinkingService(ref);
});
