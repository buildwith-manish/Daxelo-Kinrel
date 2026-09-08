// lib/core/services/notification_reply_handler.dart
//
// DAXELO KINREL — Notification Reply Handler (Tier 2 chat feature)
//
// Wires the LocalNotificationService's static onReply callback to the
// app's chat providers so a reply typed inline from a notification
// shade (Android RemoteInput / iOS UNTextInputNotificationAction) is
// actually sent to the right chat.
//
// The payload format passed to showNotificationWithReplyAction is a
// JSON string:
//   {
//     "familyId": "abc",          // family chat to reply to (required)
//     "dmUserId": null,           // OR: DM recipient userId (if DM)
//     "replyToMessageId": null    // optional: message being replied to
//   }
//
// The handler:
//   1. Parses the payload JSON.
//   2. If familyId is set: calls ChatNotifier(familyId).sendMessage(text)
//      via the family chat provider.
//   3. If dmUserId is set: calls DirectChatNotifier(dmUserId).sendText(text)
//      via the DM provider.
//   4. Surfaces errors via debugPrint (best-effort — the user isn't in
//      the app to see a snackbar).
//
// Usage in main.dart:
//   NotificationReplyHandler.initialize(container);
//   // (after the ProviderContainer is created)
//
// The handler holds a reference to the ProviderContainer so it can
// read providers from any background isolate context (the reply
// callback fires from a system callback, not the widget tree).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notification_service.dart';
import '../../features/chat/providers/chat_provider.dart';
import '../../features/chat/data/direct_message_provider.dart';

class NotificationReplyHandler {
  NotificationReplyHandler._();

  static ProviderContainer? _container;

  /// Wire the onReply callback. Call once from main() after the
  /// ProviderContainer is created (or from the app's initState if
  /// using ProviderScope).
  static void initialize(ProviderContainer container) {
    _container = container;
    LocalNotificationService.onReply = _handleReply;
    debugPrint('💬 NotificationReplyHandler initialized');
  }

  /// Tear down the callback (e.g. on app shutdown).
  static void dispose() {
    LocalNotificationService.onReply = null;
    _container = null;
  }

  static void _handleReply(String payloadJson, String replyText) {
    final container = _container;
    if (container == null) {
      debugPrint('⚠️ NotificationReplyHandler: no container — dropping reply');
      return;
    }

    try {
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final familyId = payload['familyId'] as String?;
      final dmUserId = payload['dmUserId'] as String?;
      final replyToMessageId = payload['replyToMessageId'] as String?;

      if (familyId != null && familyId.isNotEmpty) {
        // Family chat reply
        container
            .read(chatProvider(familyId).notifier)
            .sendMessage(replyText, replyToId: replyToMessageId);
        debugPrint('💬 Reply sent to family chat $familyId: "$replyText"');
      } else if (dmUserId != null && dmUserId.isNotEmpty) {
        // DM reply
        container
            .read(directChatProvider(dmUserId).notifier)
            .sendText(replyText);
        debugPrint('💬 Reply sent to DM $dmUserId: "$replyText"');
      } else {
        debugPrint('⚠️ NotificationReplyHandler: payload missing familyId + dmUserId');
      }
    } catch (e) {
      debugPrint('⚠️ NotificationReplyHandler error: $e');
    }
  }
}
