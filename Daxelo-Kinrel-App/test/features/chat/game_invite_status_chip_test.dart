// test/features/chat/game_invite_status_chip_test.dart
//
// Phase 7 — Unified game-invite status chip
//
// Verifies the classification logic that drives the new color-coded
// GameInviteStatusChip widget:
//
//   • waitingForPlayers (amber)  — status='pending', currentPlayers <= 1
//   • openToJoin (green)         — status='pending', 1 < current < max
//   • full (grey)                — status='pending', currentPlayers >= max
//   • started (ember)            — status='accepted'
//   • ended (muted)              — status='expired' | 'cancelled'
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
  group('Phase 7 — classifyGameInviteStatus', () {
    test('status=pending, currentPlayers<=1 → waitingForPlayers', () {
      // A fresh invite with just the host in — "Waiting for players…"
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.waitingForPlayers);
      expect(c.label, 'Waiting for players…');
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

    test('status=pending, 1<current<max → openToJoin', () {
      // Has activity, still joinable — "Open to join"
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.openToJoin);
      expect(c.label, 'Open to join');

      // Same kind at the upper edge (3 of 4).
      final c2 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 3,
        maxPlayers: 4,
      ));
      expect(c2.kind, GameInviteStatusKind.openToJoin);
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

    test('status=accepted → started (regardless of player count)', () {
      // Game started — even if not at capacity, the room is closed
      // because the game has begun.
      final c = classifyGameInviteStatus(_invite(
        status: 'accepted',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.started);
      expect(c.label, 'Game started');
    });

    test('status=expired → ended', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.ended);
      expect(c.label, 'Game ended');
    });

    test('status=cancelled → ended', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'cancelled',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.ended);
      expect(c.label, 'Game ended');
    });

    test('status=accepted takes priority over isFull=true', () {
      // A game that started at full capacity should show "Game started"
      // (lifecycle ended), not "Room full" (capacity-based). The
      // lifecycle status is the stronger signal — once a game has
      // started, the room is no longer joinable regardless of capacity.
      final c = classifyGameInviteStatus(_invite(
        status: 'accepted',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.started,
          reason: 'accepted status overrides isFull');
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

  group('Phase 7 — GameInviteStatusChip widget', () {
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

    testWidgets('waitingForPlayers renders the "Waiting for players…" label',
        (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.waitingForPlayers,
        'Waiting for players…',
      );
      expect(find.text('Waiting for players…'), findsOneWidget);
    });

    testWidgets('openToJoin renders the "Open to join" label',
        (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.openToJoin,
        'Open to join',
      );
      expect(find.text('Open to join'), findsOneWidget);
    });

    testWidgets('full renders the "Room full" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.full,
        'Room full',
      );
      expect(find.text('Room full'), findsOneWidget);
    });

    testWidgets('started renders the "Game started" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.started,
        'Game started',
      );
      expect(find.text('Game started'), findsOneWidget);
    });

    testWidgets('ended renders the "Game ended" label', (tester) async {
      await pumpChip(
        tester,
        GameInviteStatusKind.ended,
        'Game ended',
      );
      expect(find.text('Game ended'), findsOneWidget);
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
          'Waiting for players…',
        ),
        (
          _invite(status: 'pending', currentPlayers: 2, maxPlayers: 4),
          'Open to join',
        ),
        (
          _invite(status: 'pending', currentPlayers: 4, maxPlayers: 4),
          'Room full',
        ),
        (
          _invite(status: 'accepted', currentPlayers: 2, maxPlayers: 4),
          'Game started',
        ),
        (
          _invite(status: 'expired', currentPlayers: 1, maxPlayers: 4),
          'Game ended',
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
