// test/core/features/feature_push_filter_test.dart
//
// Phase 5 unit test — exercises the push-type → feature map and the
// `shouldShowPush` filter helper in push_notification_service.dart.
//
// Verifies:
//   • Daily-use push types (birthday_reminder, new_family_member,
//     family_event, chat_message, chat_message_batch) are NOT gated
//     and always show, even when their features are OFF (Phase 4
//     lean defaults).
//   • Gated push types (game_invite, re_engagement, chat_mention,
//     scheduled_message) are dropped when their gating feature is OFF
//     (Phase 4 default state).
//   • Unknown push types are not gated (always show).
//   • Debug override to flip a gated feature ON causes the matching
//     push type to show.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:kinrel/core/features/feature_registry.dart';
import 'package:kinrel/core/services/push_notification_service.dart';

/// Builds a [RemoteMessage] with the given FCM data map. The
/// platform-interface RemoteMessage constructor is verbose, so this
/// helper centralizes it for the test below.
RemoteMessage _msg(String type, [Map<String, dynamic>? extra]) {
  return RemoteMessage(
    messageId: 'test-$type',
    data: {'type': type, ...?extra},
  );
}

void main() {
  setUp(() async {
    // Clear any debug overrides from prior tests.
    for (final f in AppFeature.values) {
      if (Features.hasDebugOverride(f)) {
        await Features.clearDebugOverride(f);
      }
    }
  });

  group('Phase 5 — pushTypeToFeature map', () {
    test('game_invite maps to AppFeature.pushGameInvite', () {
      expect(pushTypeToFeature('game_invite'), AppFeature.pushGameInvite);
    });

    test('game_invite_push maps to AppFeature.pushGameInvite', () {
      expect(
        pushTypeToFeature('game_invite_push'),
        AppFeature.pushGameInvite,
      );
    });

    test('re_engagement maps to AppFeature.pushReEngagement', () {
      expect(
        pushTypeToFeature('re_engagement'),
        AppFeature.pushReEngagement,
      );
    });

    test('chat_mention + mention both map to AppFeature.pushMention', () {
      expect(pushTypeToFeature('chat_mention'), AppFeature.pushMention);
      expect(pushTypeToFeature('mention'), AppFeature.pushMention);
    });

    test('scheduled_message maps to AppFeature.pushScheduledMessage', () {
      expect(
        pushTypeToFeature('scheduled_message'),
        AppFeature.pushScheduledMessage,
      );
    });

    test('daily-use types return null (not gated)', () {
      // These are core retention surfaces — never gated by feature
      // flags. The Phase 4 lean defaults must NOT suppress them.
      expect(pushTypeToFeature('birthday_reminder'), isNull);
      expect(pushTypeToFeature('new_family_member'), isNull);
      expect(pushTypeToFeature('family_event'), isNull);
      expect(pushTypeToFeature('chat_message'), isNull);
      expect(pushTypeToFeature('chat_message_batch'), isNull);
    });

    test('unknown types return null (not gated)', () {
      expect(pushTypeToFeature('totally_unknown_type'), isNull);
      expect(pushTypeToFeature(null), isNull);
      expect(pushTypeToFeature(''), isNull);
    });
  });

  group('Phase 5 — shouldShowPush under Phase 4 lean defaults', () {
    // Phase 4 lean defaults: pushGameInvite, pushReEngagement,
    // pushMention, pushScheduledMessage are all OFF. Daily-use
    // types are not gated so they show regardless.

    test('gated push types are DROPPED (feature is OFF in lean defaults)', () {
      expect(shouldShowPush(_msg('game_invite')), isFalse,
          reason: 'pushGameInvite is OFF in Phase 4 lean defaults');
      expect(shouldShowPush(_msg('game_invite_push')), isFalse);
      expect(shouldShowPush(_msg('re_engagement')), isFalse,
          reason: 'pushReEngagement is OFF in Phase 4 lean defaults');
      expect(shouldShowPush(_msg('chat_mention')), isFalse,
          reason: 'pushMention is OFF in Phase 4 lean defaults');
      expect(shouldShowPush(_msg('mention')), isFalse);
      expect(shouldShowPush(_msg('scheduled_message')), isFalse,
          reason: 'pushScheduledMessage is OFF in Phase 4 lean defaults');
    });

    test('daily-use push types are SHOWN (not gated)', () {
      expect(shouldShowPush(_msg('birthday_reminder')), isTrue);
      expect(shouldShowPush(_msg('new_family_member')), isTrue);
      expect(shouldShowPush(_msg('family_event')), isTrue);
      expect(shouldShowPush(_msg('chat_message')), isTrue);
      expect(shouldShowPush(_msg('chat_message_batch')), isTrue);
    });

    test('unknown push types are SHOWN (not gated)', () {
      expect(shouldShowPush(_msg('totally_unknown_type')), isTrue);
      // Empty-string type → not gated → show.
      expect(shouldShowPush(_msg('')), isTrue);
    });
  }, skip: kReleaseMode ? 'release builds have empty debug overrides' : null);

  group('Phase 5 — debug override flips behavior', () {
    test('flipping pushGameInvite ON re-enables game_invite pushes', () {
      if (!kDebugMode) return;
      // Baseline: gated OFF.
      expect(shouldShowPush(_msg('game_invite')), isFalse);

      // Flip ON via debug override.
      Features.setDebugOverride(AppFeature.pushGameInvite, true);
      expect(shouldShowPush(_msg('game_invite')), isTrue);

      // Restore.
      Features.clearDebugOverride(AppFeature.pushGameInvite);
      expect(shouldShowPush(_msg('game_invite')), isFalse);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('flipping pushReEngagement ON re-enables re_engagement pushes', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.pushReEngagement, true);
      expect(shouldShowPush(_msg('re_engagement')), isTrue);
      Features.clearDebugOverride(AppFeature.pushReEngagement);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('flipping pushMention ON re-enables chat_mention pushes', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.pushMention, true);
      expect(shouldShowPush(_msg('chat_mention')), isTrue);
      expect(shouldShowPush(_msg('mention')), isTrue);
      Features.clearDebugOverride(AppFeature.pushMention);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('flipping pushScheduledMessage ON re-enables scheduled_message', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.pushScheduledMessage, true);
      expect(shouldShowPush(_msg('scheduled_message')), isTrue);
      Features.clearDebugOverride(AppFeature.pushScheduledMessage);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });

  group('Phase 5 — defensive behavior', () {
    test('shouldShowPush never throws on malformed data', () {
      // Defensive: even if `data.type` is not a string, the helper
      // must not throw — it must return true (allow) so the push
      // surface is fail-open, not fail-closed.
      final weird = const RemoteMessage(
        messageId: 'test-weird',
        data: {'type': 12345}, // wrong type — int, not String
      );
      expect(shouldShowPush(weird), isTrue);
    });
  });
}
