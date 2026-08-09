// lib/features/thinking/data/thinking_service.dart
//
// "Thinking of You" — Supabase RPC client for the tap feature.
//
// Phase 20: Updated to support the 6-hour cooldown + countdown display.
// The RPC now returns:
//   - cooldownExpiresAt (ISO 8601 timestamp) on both success AND cooldown
//     so the client can show a live countdown like "Available again in 5h 23m"
//   - cooldownRemainingMinutes (int) on cooldown for client-side display
//   - meaningful error codes:
//       'not_authenticated'    → "You must be signed in..."
//       'cannot_send_to_self'  → "You cannot send a Thinking of You moment to yourself."
//       'receiver_not_in_family' → "Recipient not found in this family."
//       'cooldown'             → "You can send another Thinking of You moment in 6h 0m."
//       'network_error'        → client-side network failure
//
// The RPC also creates a Notification row (in addition to the ChatMessage
// + DirectMessage) so the recipient sees the moment in BOTH their
// Notifications section and their family chat.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class ThinkingResult {
  const ThinkingResult({
    required this.success,
    this.message,
    this.error,
    this.cooldownHours,
    this.cooldownExpiresAt,
    this.cooldownRemainingMinutes,
    this.dmId,
    this.chatMessageId,
    this.senderName,
    this.receiverName,
    this.familyName,
  });

  final bool success;
  final String? message;
  final String? error;
  final int? cooldownHours;
  /// ISO 8601 timestamp (UTC) when the cooldown expires and the user
  /// can send another Thinking of You to the same recipient.
  final String? cooldownExpiresAt;
  /// Remaining minutes until the cooldown expires (convenience for the UI).
  final int? cooldownRemainingMinutes;
  final String? dmId;
  final String? chatMessageId;
  final String? senderName;
  /// Recipient's display name (used for the success message:
  /// "Your Thinking of You moment was sent to Yakshitha").
  final String? receiverName;
  final String? familyName;

  /// Parse the cooldownExpiresAt string into a DateTime (or null if
  /// not set / unparseable).
  DateTime? get cooldownExpiresAtUtc {
    final s = cooldownExpiresAt;
    if (s == null || s.isEmpty) return null;
    // The RPC returns ISO 8601 with 'Z' suffix (UTC).
    // DateTime.parse handles 'Z' and '+00:00' but treats the result as local.
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  /// Convenience: is the cooldown currently active?
  bool get isOnCooldown =>
      error == 'cooldown' && cooldownExpiresAtUtc != null &&
      DateTime.now().toUtc().isBefore(cooldownExpiresAtUtc!);
}

class ThinkingService {
  ThinkingService(this._ref);
  final Ref _ref;

  /// Sends a "Thinking of You" notification to [receiverId] in the
  /// context of [familyId]. The RPC:
  ///   1. Validates the receiver is a member of the family
  ///   2. Enforces a 6-hour cooldown per sender→receiver pair
  ///   3. Inserts a ChatMessage (family group chat — visible delivery)
  ///   4. Inserts a DirectMessage (for future 1:1 chat + analytics)
  ///   5. Creates a Notification for the receiver (Notifications section)
  ///   6. Stores an analytics event
  ///
  /// Returns a [ThinkingResult] indicating success/failure. If the
  /// cooldown is active, [ThinkingResult.error] is 'cooldown' and
  /// [ThinkingResult.cooldownExpiresAt] is set so the UI can show a
  /// countdown.
  Future<ThinkingResult> sendTap({
    required String receiverId,
    required String familyId,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        return const ThinkingResult(
          success: false,
          error: 'network_error',
          message: 'Connection not ready. Please try again.',
        );
      }

      final response = await client.rpc(
        'fn_send_thinking_of_you',
        params: {
          'p_receiver_id': receiverId,
          'p_family_id': familyId,
        },
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;

      if (success) {
        return ThinkingResult(
          success: true,
          message: result?['message'] as String?,
          dmId: result?['dmId'] as String?,
          chatMessageId: result?['chatMessageId'] as String?,
          senderName: result?['senderName'] as String?,
          receiverName: result?['receiverName'] as String?,
          familyName: result?['familyName'] as String?,
          cooldownHours: result?['cooldownHours'] as int?,
          cooldownExpiresAt: result?['cooldownExpiresAt'] as String?,
        );
      } else {
        return ThinkingResult(
          success: false,
          error: result?['error'] as String?,
          message: result?['message'] as String?,
          cooldownHours: result?['cooldownHours'] as int?,
          cooldownExpiresAt: result?['cooldownExpiresAt'] as String?,
          cooldownRemainingMinutes: result?['cooldownRemainingMinutes'] as int?,
        );
      }
    } catch (e) {
      debugPrint('⚠️ ThinkingService.sendTap error: $e');
      return const ThinkingResult(
        success: false,
        error: 'network_error',
        message: 'Network error. Please check your connection and try again.',
      );
    }
  }
}

final thinkingServiceProvider = Provider<ThinkingService>((ref) {
  return ThinkingService(ref);
});
