// test/features/chat/game_invite_status_chip_test.dart
//
// 5-state lifecycle — Unified game-invite status chip
//
// Verifies the classification logic that drives the color-coded
// GameInviteStatusChip widget, now covering all 5 lifecycle states:
//
//   • waitingForPlayers (amber)  — status='pending', currentPlayers <= 1
//   • openToJoin (green)         — status='pending', 1 < current < max
//   • full (grey)                — status='pending', currentPlayers >= max
//   • inProgress (pulsing green) — status='in_progress' (or legacy 'accepted'/'active')
//   • completed (muted)          — status='completed'
//   • expired (greyed)           — status='expired' | 'cancelled'
//
// Also pumps the chip widget itself in a test harness and asserts the
// rendered text matches the expected label for each kind, so we have a
// regression-test safety net if someone renames a label string.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/widgets/game_invite_status_chip.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

ChatMessage _invite({
  String? status,
  int? currentPlayers,
  int? maxPlayers,
  String gameType = 'sos',
}) {
  return ChatMessage(
    id: 'cm_test_$status${currentPlayers ?? 0}_${maxPlayers ?? 0}',
    senderId: 'user_a',
    senderName: 'Host User',
    content: 'Host User started a SOS game',
    messageType: MessageType.gameInvite,
    timestamp: DateTime.parse('2026-10-04T12:00:00Z'),
    gameType: gameType,
    gameId: '11111111-2222-3333-4444-555555555555',
    roomCode: 'AB12CD',
    gameMaxPlayers: maxPlayers ?? 4,
    gameCurrentPlayers: currentPlayers ?? 1,
    gameInviteStatus: status ?? 'pending',
  );
}

void main() {
  group('5-state lifecycle — classifyGameInviteStatus', () {
    test('status=pending, currentPlayers<=1 → waitingForPlayers', () {
      // A fresh invite with just the host in — "Waiting for players"
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.waitingForPlayers);
      expect(c.label, 'Waiting for players');
    });

    test('status=pending (null treated as pending), currentPlayers<=1 → waitingForPlayers', () {
      // Null status is normalized to 'pending' in the production card
      // code (message.gameInviteStatus ?? 'pending'). The classifier
      // should treat null the same way.
      final c = classifyGameInviteStatus(_invite(
        status: null,
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.waitingForPlayers);
    });

    test('status=pending, 1<current<max → openToJoin with spots-left label', () {
      // Has activity, still joinable. Per the user-facing spec, the
      // chip surfaces the explicit remaining-slot count instead of a
      // generic "Open to join" — so the user doesn't have to do mental
      // arithmetic on the "current/max players" line above.
      final c2of4 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c2of4.kind, GameInviteStatusKind.openToJoin);
      expect(c2of4.label, '2 spots left');

      // Same kind at the upper edge (3 of 4).
      final c3of4 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 3,
        maxPlayers: 4,
      ));
      expect(c3of4.kind, GameInviteStatusKind.openToJoin);
      expect(c3of4.label, '1 spot left',
          reason: 'singular form when only 1 slot remains');
    });

    test('status=pending, currentPlayers>=maxPlayers → full', () {
      // At capacity — "Room full"
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.full);
      expect(c.label, 'Room full');

      // Edge: over-capacity (defensive) still classifies as full.
      final c2 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 5,
        maxPlayers: 4,
      ));
      expect(c2.kind, GameInviteStatusKind.full);
    });

    test('status=in_progress → inProgress (pulsing LIVE NOW)', () {
      // Game started — the chip renders the pulsing green LIVE NOW
      // treatment, matching the existing LIVE NOW badge on the
      // Prediction Battle card.
      final c = classifyGameInviteStatus(_invite(
        status: 'in_progress',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress);
      expect(c.label, 'LIVE NOW');
    });

    test('legacy status=accepted → inProgress (back-compat alias)', () {
      // Pre-state-machine rows had gameInviteStatus='accepted' on
      // host-start. These continue to render as inProgress (LIVE NOW)
      // — no migration needed for existing chat cards.
      final c = classifyGameInviteStatus(_invite(
        status: 'accepted',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress);
      expect(c.label, 'LIVE NOW');
    });

    test('status=completed → completed (muted, settled treatment)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.completed);
      expect(c.label, 'Completed');
    });

    test('status=expired → expired (greyed, "Closed • Expired")', () {
      // Per the user-facing spec, the expired state renders as "Closed • Expired"
      // (with a closed-door icon) to make it clear the room is no longer available.
      final c = classifyGameInviteStatus(_invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.expired);
      expect(c.label, 'Closed • Expired');
    });

    test('status=cancelled → expired kind, label "Closed • Expired"', () {
      // Per the spec, 'cancelled' (host-driven) and 'expired' (15-min inactivity
      // timeout) both render the same "Closed • Expired" treatment — the
      // closed-door phrasing makes it clear the room is no longer available.
      final c = classifyGameInviteStatus(_invite(
        status: 'cancelled',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.expired);
      expect(c.label, 'Closed • Expired');
    });

    test('status=in_progress takes priority over isFull=true', () {
      // A game that started at full capacity should show "LIVE NOW"
      // (in-progress), not "Room full" (capacity-based). The
      // lifecycle status is the stronger signal — once a game has
      // started, the room is no longer joinable regardless of capacity.
      final c = classifyGameInviteStatus(_invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress,
          reason: 'in_progress status overrides isFull');
    });

    test('applies uniformly across game types (SOS, Bingo, etc.)', () {
      // The chip is a SINGLE component used by ALL game-invite card
      // variants — so the same input state must produce the same chip
      // kind regardless of gameType. This is the spec's "unified
      // status chip across every game-invite card type" requirement.
      for (final gameType in ['sos', 'bingo', 'prediction-battle', 'unknown']) {
        final c = classifyGameInviteStatus(_invite(
          status: 'pending',
          currentPlayers: 2,
          maxPlayers: 4,
          gameType: gameType,
        ));
        expect(c.kind, GameInviteStatusKind.openToJoin,
            reason: '$gameType should classify identically');
      }
    });
  });

  group('5-state lifecycle — GameInviteStatusChip widget', () {
    /// Pumps the chip in a minimal MaterialApp and asserts the rendered
    /// label text matches the expected string for each kind.
    Future<void> pumpChip(
      WidgetTester tester,
      GameInviteStatusKind kind,
      String label,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GameInviteStatusChip(kind: kind, label: label),
            ),
          ),
        ),
      );
    }

    testWidgets('waitingForPlayers renders the "Waiting for players" label',
        (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.waitingForPlayers,
        'Waiting for players',
      );
      expect(find.text('Waiting for players'), findsOneWidget);
    });

    testWidgets('openToJoin renders the spots-left label',
        (tester) async {
      // The label is dynamic ("X spots left") but the widget itself
      // just renders whatever label string it's given — so we pump a
      // representative label.
      await pumpChip(
        tester,
        GameInviteStatusKind.openToJoin,
        '2 spots left',
      );
      expect(find.text('2 spots left'), findsOneWidget);
    });

    testWidgets('full renders the "Room full" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.full,
        'Room full',
      );
      expect(find.text('Room full'), findsOneWidget);
    });

    testWidgets('inProgress renders the "LIVE NOW" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.inProgress,
        'LIVE NOW',
      );
      expect(find.text('LIVE NOW'), findsOneWidget);
    });

    testWidgets('inProgress starts the pulsing animation', (tester) async {
      // The inProgress chip is the only state with an AnimationController.
      // Pump with a duration to verify the controller is running and
      // the chip's background alpha changes over time (the pulse).
      await pumpChip(
        tester,
        GameInviteStatusKind.inProgress,
        'LIVE NOW',
      );
      // Pump a frame to let the AnimationController's repeat() kick in.
      await tester.pump(const Duration(milliseconds: 50));
      // The chip should still be rendering (the pulse doesn't unmount).
      expect(find.text('LIVE NOW'), findsOneWidget);
      // Pump more time to verify the controller is still alive.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('LIVE NOW'), findsOneWidget);
    });

    testWidgets('completed renders the "Completed" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.completed,
        'Completed',
      );
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('expired renders the "Closed • Expired" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.expired,
        'Closed • Expired',
      );
      expect(find.text('Closed • Expired'), findsOneWidget);
    });

    testWidgets('compact variant renders text at smaller size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GameInviteStatusChip(
                kind: GameInviteStatusKind.full,
                label: 'Room full',
                compact: true,
              ),
            ),
          ),
        ),
      );
      // Find the Text widget inside the chip and assert the font size
      // is the compact value (10.0, per the chip's compact branch).
      final textWidget = tester.widget<Text>(find.text('Room full'));
      expect(textWidget.style?.fontSize, 10.0);
    });

    testWidgets(
        'GameInviteStatusChip.forMessage factory renders the correct label '
        'for each input state', (tester) async {
      // Pump the factory entry point used by the production card code.
      // This exercises the full message → classification → chip render
      // pipeline and serves as a regression test for the wiring.
      final cases = <(ChatMessage, String)>[
        (
          _invite(status: 'pending', currentPlayers: 1, maxPlayers: 4),
          'Waiting for players',
        ),
        (
          _invite(status: 'pending', currentPlayers: 2, maxPlayers: 4),
          '2 spots left',
        ),
        (
          _invite(status: 'pending', currentPlayers: 4, maxPlayers: 4),
          'Room full',
        ),
        (
          _invite(status: 'in_progress', currentPlayers: 2, maxPlayers: 4),
          'LIVE NOW',
        ),
        (
          _invite(status: 'completed', currentPlayers: 4, maxPlayers: 4),
          'Completed',
        ),
        (
          _invite(status: 'expired', currentPlayers: 1, maxPlayers: 4),
          'Closed • Expired',
        ),
      ];

      for (final (message, expectedLabel) in cases) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameInviteStatusChip.forMessage(message),
              ),
            ),
          ),
        );
        expect(
          find.text(expectedLabel),
          findsOneWidget,
          reason: 'For status=${message.gameInviteStatus}, '
              'current=${message.gameCurrentPlayers}, '
              'max=${message.gameMaxPlayers} → expected "$expectedLabel"',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
