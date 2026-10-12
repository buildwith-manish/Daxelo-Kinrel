// test/features/chat/game_invite_grouping_test.dart
//
// DAXELO KINREL — v143/Step 10 — Unit tests for groupChatItems.
//
// Covers: exactly 3 consecutive collapses, 2 do not, a text message
// splits a run, a live invite splits a run, mixed expired and
// completed uses the "finished" wording, and 5 consecutive collapses
// into one run of 5.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/widgets/game_invite_grouping.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

/// Helper: create a text ChatMessage.
ChatMessage _textMsg(String id) => ChatMessage(
      id: id,
      senderId: 'user1',
      senderName: 'User',
      content: 'Hello $id',
      messageType: MessageType.text,
      timestamp: DateTime(2026, 1, 1),
    );

/// Helper: create a game-invite ChatMessage with a given status.
ChatMessage _gameMsg(String id, String status, {String? winner}) {
  final isCompleted = status == 'completed';
  final hasWinner = winner != null && winner.isNotEmpty;
  return ChatMessage(
    id: id,
    senderId: 'user1',
    senderName: 'User',
    content: '',
    messageType: MessageType.gameInvite,
    timestamp: DateTime(2026, 1, 1),
    gameType: 'tictactoe',
    gameId: 'game_$id',
    gameInviteStatus: status,
    gameWinnerName: isCompleted && hasWinner ? winner : null,
  );
}

void main() {
  group('groupChatItems — collapse rule', () {
    test('3 consecutive expired invites collapse into 1 run', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'expired'),
        _gameMsg('g3', 'expired'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 1);
      expect(items[0], isA<CollapsedInviteRun>());
      final run = items[0] as CollapsedInviteRun;
      expect(run.messages.length, 3);
      expect(run.allExpired, isTrue);
    });

    test('2 consecutive expired invites do NOT collapse', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'expired'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 2);
      expect(items[0], isA<TerminalInvite>());
      expect(items[1], isA<TerminalInvite>());
    });

    test('A text message splits a run', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'expired'),
        _textMsg('t1'),
        _gameMsg('g3', 'expired'),
        _gameMsg('g4', 'expired'),
      ];
      final items = groupChatItems(msgs);
      // g1, g2 are 2 (no collapse) + t1 + g3, g4 are 2 (no collapse)
      expect(items.length, 5);
      expect(items[0], isA<TerminalInvite>());
      expect(items[1], isA<TerminalInvite>());
      expect(items[2], isA<RegularMessage>());
      expect(items[3], isA<TerminalInvite>());
      expect(items[4], isA<TerminalInvite>());
    });

    test('A live invite splits a run', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'expired'),
        _gameMsg('g3', 'pending'), // live invite
        _gameMsg('g4', 'expired'),
        _gameMsg('g5', 'expired'),
      ];
      final items = groupChatItems(msgs);
      // g1, g2 = 2 terminal (no collapse) + g3 = active + g4, g5 = 2 terminal
      expect(items.length, 5);
      expect(items[0], isA<TerminalInvite>());
      expect(items[1], isA<TerminalInvite>());
      expect(items[2], isA<ActiveInvite>());
      expect(items[3], isA<TerminalInvite>());
      expect(items[4], isA<TerminalInvite>());
    });

    test('Mixed expired + completed uses "finished" wording', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'completed'), // no winner → terminal
        _gameMsg('g3', 'expired'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 1);
      expect(items[0], isA<CollapsedInviteRun>());
      final run = items[0] as CollapsedInviteRun;
      expect(run.allExpired, isFalse); // mixed → false → "finished"
    });

    test('All expired uses "expired" wording', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'cancelled'), // cancelled = expired equivalent
        _gameMsg('g3', 'expired'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 1);
      final run = items[0] as CollapsedInviteRun;
      expect(run.allExpired, isTrue); // all expired/cancelled → "expired"
    });

    test('5 consecutive expired invites collapse into one run of 5', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'expired'),
        _gameMsg('g3', 'expired'),
        _gameMsg('g4', 'expired'),
        _gameMsg('g5', 'expired'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 1);
      expect(items[0], isA<CollapsedInviteRun>());
      final run = items[0] as CollapsedInviteRun;
      expect(run.messages.length, 5);
    });

    test('Result cards (completed + winner) never join a collapsed run', () {
      final msgs = [
        _gameMsg('g1', 'expired'),
        _gameMsg('g2', 'completed', winner: 'Papa'), // result card
        _gameMsg('g3', 'expired'),
      ];
      final items = groupChatItems(msgs);
      // g1 = 1 terminal + g2 = result card + g3 = 1 terminal
      expect(items.length, 3);
      expect(items[0], isA<TerminalInvite>());
      expect(items[1], isA<ResultCard>());
      expect(items[2], isA<TerminalInvite>());
    });

    test('Active invite (pending) is not collapsed', () {
      final msgs = [
        _gameMsg('g1', 'pending'),
        _gameMsg('g2', 'pending'),
        _gameMsg('g3', 'pending'),
      ];
      final items = groupChatItems(msgs);
      expect(items.length, 3);
      for (final item in items) {
        expect(item, isA<ActiveInvite>());
      }
    });

    test('Empty list returns empty items', () {
      expect(groupChatItems([]), isEmpty);
    });

    test('Single regular message passes through', () {
      final items = groupChatItems([_textMsg('t1')]);
      expect(items.length, 1);
      expect(items[0], isA<RegularMessage>());
    });
  });
}
