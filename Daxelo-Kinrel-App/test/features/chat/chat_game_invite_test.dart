// test/features/chat/chat_game_invite_test.dart
//
// Regression tests for the persistent game-invite card in the family chat
// thread (MessageType.gameInvite):
//   • ChatMessage model: JSON round-trip of the game payload fields
//   • Legacy rows without game columns parse to null game fields
//   • copyWith PRESERVES and UPDATES game fields (the realtime UPDATE path
//     re-parses rows and copies reactions — game fields must survive it)
//   • Full / closed card state getters
//   • The lobby join route format the chat card's Join button uses stays
//     byte-identical to GameInvite.joinRoute (GameInviteListener's route).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';
import 'package:kinrel/features/games/shared/models/game_invite.dart';

ChatMessage _gameInviteMessage({
  String? status,
  int? currentPlayers,
}) {
  return ChatMessage(
    id: 'cm_test_1',
    senderId: 'user_a',
    senderName: 'Host User',
    content: 'Host User started a SOS game',
    messageType: MessageType.gameInvite,
    timestamp: DateTime.parse('2026-08-28T12:00:00Z'),
    gameType: 'sos',
    gameId: '11111111-2222-3333-4444-555555555555',
    roomCode: 'AB12CD',
    gameMaxPlayers: 4,
    gameCurrentPlayers: currentPlayers ?? 1,
    gameInviteStatus: status ?? 'pending',
  );
}

void main() {
  group('MessageType.gameInvite serialization', () {
    test('toJson emits messageType gameInvite + all game payload fields', () {
      final json = _gameInviteMessage().toJson(familyId: 'fam_1');

      expect(json['messageType'], 'gameInvite');
      expect(json['gameType'], 'sos');
      expect(json['gameId'], '11111111-2222-3333-4444-555555555555');
      expect(json['roomCode'], 'AB12CD');
      expect(json['gameMaxPlayers'], 4);
      expect(json['gameCurrentPlayers'], 1);
      expect(json['gameInviteStatus'], 'pending');
    });

    test('fromJson parses messageType gameInvite + all game payload fields',
        () {
      final msg = ChatMessage.fromJson(const {
        'id': 'cm_test_2',
        'senderId': 'user_a',
        'senderName': 'Host User',
        'content': 'Host User started a SOS game',
        'messageType': 'gameInvite',
        'createdAt': '2026-08-28T12:00:00.000Z',
        'gameType': 'sos',
        'gameId': '11111111-2222-3333-4444-555555555555',
        'roomCode': 'AB12CD',
        'gameMaxPlayers': 4,
        'gameCurrentPlayers': 2,
        'gameInviteStatus': 'accepted',
      });

      expect(msg.messageType, MessageType.gameInvite);
      expect(msg.gameType, 'sos');
      expect(msg.gameId, '11111111-2222-3333-4444-555555555555');
      expect(msg.roomCode, 'AB12CD');
      expect(msg.gameMaxPlayers, 4);
      expect(msg.gameCurrentPlayers, 2);
      expect(msg.gameInviteStatus, 'accepted');
    });

    test('legacy rows without game columns parse to null game fields', () {
      final msg = ChatMessage.fromJson(const {
        'id': 'cm_test_3',
        'senderId': 'user_b',
        'senderName': 'Other User',
        'content': 'plain text message',
        'messageType': 'text',
        'createdAt': '2026-08-28T12:00:00.000Z',
      });

      expect(msg.messageType, MessageType.text);
      expect(msg.gameType, isNull);
      expect(msg.gameId, isNull);
      expect(msg.roomCode, isNull);
      expect(msg.gameMaxPlayers, isNull);
      expect(msg.gameCurrentPlayers, isNull);
      expect(msg.gameInviteStatus, isNull);
      expect(msg.toJson(familyId: 'fam_1').containsKey('gameId'), isFalse);
    });
  });

  group('copyWith preserves the game payload (realtime UPDATE path)', () {
    // chat_provider._handleMessageUpdate rebuilds a message from the row and
    // then copyWith(reactions: …). If copyWith dropped the game fields the
    // card would lose its payload on every realtime update — pinned here.
    test('unrelated copyWith keeps all game fields', () {
      final original = _gameInviteMessage();
      final copied = original.copyWith(isRead: true);

      expect(copied.messageType, MessageType.gameInvite);
      expect(copied.gameType, 'sos');
      expect(copied.gameId, '11111111-2222-3333-4444-555555555555');
      expect(copied.roomCode, 'AB12CD');
      expect(copied.gameMaxPlayers, 4);
      expect(copied.gameCurrentPlayers, 1);
      expect(copied.gameInviteStatus, 'pending');
    });

    test('copyWith can refresh player count and invite status', () {
      final original = _gameInviteMessage();
      final copied = original.copyWith(
        gameCurrentPlayers: 4,
        gameInviteStatus: 'accepted',
      );

      expect(copied.gameCurrentPlayers, 4);
      expect(copied.gameInviteStatus, 'accepted');
      expect(copied.gameType, 'sos'); // untouched fields survive
    });
  });

  group('game-invite card state getters', () {
    test('isGameFull flips at maxPlayers', () {
      expect(_gameInviteMessage(currentPlayers: 3).isGameFull, isFalse);
      expect(_gameInviteMessage(currentPlayers: 4).isGameFull, isTrue);
      expect(_gameInviteMessage(currentPlayers: 9).isGameFull, isTrue);
    });

    test('isGameInviteClosed is only true for non-pending statuses', () {
      expect(_gameInviteMessage(status: null).isGameInviteClosed, isFalse);
      expect(_gameInviteMessage(status: 'pending').isGameInviteClosed,
          isFalse);
      expect(_gameInviteMessage(status: 'accepted').isGameInviteClosed, isTrue);
      expect(_gameInviteMessage(status: 'expired').isGameInviteClosed, isTrue);
      expect(
          _gameInviteMessage(status: 'cancelled').isGameInviteClosed, isTrue);
    });

    test('non-game messages are never game-full or closed', () {
      final text = ChatMessage(
        id: 'cm_t',
        senderId: 'u',
        senderName: 'U',
        content: 'hi',
        messageType: MessageType.text,
        timestamp: DateTime.now(),
      );
      expect(text.isGameFull, isFalse);
      expect(text.isGameInviteClosed, isFalse);
    });
  });

  group('chat card Join route parity with GameInviteListener', () {
    // The chat card's Join button builds
    // '/family/<familyId>/<gameType>/lobby?join=<gameId>' — this must stay
    // byte-identical to GameInvite.joinRoute, which GameInviteListener's
    // _acceptInvite navigates with. Any drift breaks the join flow.
    test('route format matches GameInvite.joinRoute for every game type', () {
      for (final type in GameType.values) {
        final invite = GameInvite(
          inviteId: 'inv_x',
          gameType: type,
          gameId: 'g1',
          roomCode: 'AB12CD',
          familyId: 'f1',
          fromUserId: 'u1',
          fromName: 'Host',
          maxPlayers: 4,
          currentPlayers: 1,
        );
        expect(
          invite.joinRoute,
          '/family/f1/${type.routeSegment}/lobby?join=g1',
          reason: '${type.routeSegment} join route drifted',
        );
      }
    });

    test('sos segment round-trips through fromRouteSegment', () {
      expect(GameTypeX.fromRouteSegment('sos'), GameType.sos);
      expect(GameTypeX.fromRouteSegment('sos')!.displayName, 'SOS');
      expect(GameTypeX.fromRouteSegment('nope'), isNull);
    });
  });
}
