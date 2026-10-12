// test/features/chat/game_invite_action_test.dart
//
// DAXELO KINREL — v143/Step 10 — Unit tests for resolveInviteAction.
//
// Covers every state in Step 4 with spectators on and off and with
// the viewer as player and non-player.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/widgets/game_invite_action.dart';

void main() {
  group('resolveInviteAction — pending (pre-game)', () {
    test('Waiting + joinable, received invite → Join (enabled)', () {
      final a = resolveInviteAction(
        status: InviteStatus.pending,
        isMe: false,
        isFull: false,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, 'Join');
      expect(a.enabled, isTrue);
      expect(a.urgent, isFalse);
    });

    test('Own waiting invite → no button', () {
      final a = resolveInviteAction(
        status: InviteStatus.pending,
        isMe: true,
        isFull: false,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, isNull);
      expect(a.hasButton, isFalse);
    });

    test('Full + spectators on → Spectate (enabled)', () {
      final a = resolveInviteAction(
        status: InviteStatus.pending,
        isMe: false,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, 'Spectate');
      expect(a.enabled, isTrue);
    });

    test('Full + spectators off → Full (disabled)', () {
      final a = resolveInviteAction(
        status: InviteStatus.pending,
        isMe: false,
        isFull: true,
        spectatorsEnabled: false,
        isViewerPlayer: false,
      );
      expect(a.label, 'Full');
      expect(a.enabled, isFalse);
    });
  });

  group('resolveInviteAction — in-progress', () {
    test('Viewer is player → Rejoin (enabled, urgent)', () {
      final a = resolveInviteAction(
        status: InviteStatus.inProgress,
        isMe: false,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: true,
      );
      expect(a.label, 'Rejoin');
      expect(a.enabled, isTrue);
      expect(a.urgent, isTrue);
    });

    test('Host (isMe) → Rejoin (enabled, urgent)', () {
      final a = resolveInviteAction(
        status: InviteStatus.inProgress,
        isMe: true,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, 'Rejoin');
      expect(a.enabled, isTrue);
      expect(a.urgent, isTrue);
    });

    test('Not player + spectators on → Spectate (enabled, urgent)', () {
      final a = resolveInviteAction(
        status: InviteStatus.inProgress,
        isMe: false,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, 'Spectate');
      expect(a.enabled, isTrue);
      expect(a.urgent, isTrue);
    });

    test('Not player + spectators off → In Game (disabled)', () {
      final a = resolveInviteAction(
        status: InviteStatus.inProgress,
        isMe: false,
        isFull: true,
        spectatorsEnabled: false,
        isViewerPlayer: false,
      );
      expect(a.label, 'In Game');
      expect(a.enabled, isFalse);
    });
  });

  group('resolveInviteAction — terminal states', () {
    test('Completed + winner → no button (result card is shown)', () {
      final a = resolveInviteAction(
        status: InviteStatus.completed,
        isMe: false,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: false,
        hasWinner: true,
      );
      expect(a.label, isNull);
      expect(a.hasButton, isFalse);
    });

    test('Completed no winner → no button (one-line row)', () {
      final a = resolveInviteAction(
        status: InviteStatus.completed,
        isMe: false,
        isFull: true,
        spectatorsEnabled: true,
        isViewerPlayer: false,
        hasWinner: false,
      );
      expect(a.label, isNull);
    });

    test('Expired → no button', () {
      final a = resolveInviteAction(
        status: InviteStatus.expired,
        isMe: false,
        isFull: false,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, isNull);
    });

    test('Cancelled → no button', () {
      final a = resolveInviteAction(
        status: InviteStatus.cancelled,
        isMe: false,
        isFull: false,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, isNull);
    });

    test('Unknown → no button', () {
      final a = resolveInviteAction(
        status: InviteStatus.unknown,
        isMe: false,
        isFull: false,
        spectatorsEnabled: true,
        isViewerPlayer: false,
      );
      expect(a.label, isNull);
    });
  });
}
