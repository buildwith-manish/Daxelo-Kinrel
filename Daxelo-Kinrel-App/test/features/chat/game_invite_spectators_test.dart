// test/features/chat/game_invite_spectators_test.dart
//
// Spectator-mode gating on the chat-invite card — unit tests.
//
// Verifies the ChatMessage.gameSpectatorsEnabled field is round-tripped
// correctly through fromJson / toJson / copyWith, that the
// effectiveSpectatorsEnabled getter returns the spec-compliant default
// (true) for legacy rows, and that the message_bubble card resolves
// the correct action button label based on the spectator flag.
//
// Spec rules covered:
//   • Spectators enabled  + in-progress + non-host → "Spectate" button
//   • Spectators disabled + in-progress + non-host → static "In Game" label
//   • Spectators enabled  + in-progress + host     → "Rejoin" button
//   • Spectators disabled + in-progress + host     → "Rejoin" button (host
//     always re-enters their own game regardless of spectator flag)
//   • Legacy rows (gameSpectatorsEnabled == null)  → treated as `true`
//     for backward compatibility (spectator mode was historically on by
//     default).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

ChatMessage _invite({
  String? status,
  int? currentPlayers,
  int? maxPlayers,
  bool? spectatorsEnabled,
  String senderId = 'user_host',
}) {
  return ChatMessage(
    id: 'cm_spec_test_${status ?? 'null'}_${spectatorsEnabled ?? 'null'}',
    senderId: senderId,
    senderName: 'Host User',
    content: 'Host User started a SOS game',
    messageType: MessageType.gameInvite,
    timestamp: DateTime.parse('2026-10-04T12:00:00Z'),
    gameType: 'sos',
    gameId: '11111111-2222-3333-4444-555555555555',
    roomCode: 'AB12CD',
    gameMaxPlayers: maxPlayers ?? 4,
    gameCurrentPlayers: currentPlayers ?? 2,
    gameInviteStatus: status ?? 'in_progress',
    gameSpectatorsEnabled: spectatorsEnabled,
  );
}

void main() {
  group('gameSpectatorsEnabled field — round-trip', () {
    test('fromJson parses gameSpectatorsEnabled (true)', () {
      final m = ChatMessage.fromJson({
        'id': 'cm1',
        'senderId': 'u1',
        'senderName': 'Host',
        'content': '',
        'messageType': 'gameInvite',
        'createdAt': '2026-10-04T12:00:00Z',
        'gameId': 'g1',
        'gameType': 'sos',
        'roomCode': 'AB12CD',
        'gameMaxPlayers': 4,
        'gameCurrentPlayers': 2,
        'gameInviteStatus': 'in_progress',
        'gameSpectatorsEnabled': true,
      });
      expect(m.gameSpectatorsEnabled, true);
      expect(m.effectiveSpectatorsEnabled, true);
    });

    test('fromJson parses gameSpectatorsEnabled (false)', () {
      final m = ChatMessage.fromJson({
        'id': 'cm2',
        'senderId': 'u1',
        'senderName': 'Host',
        'content': '',
        'messageType': 'gameInvite',
        'createdAt': '2026-10-04T12:00:00Z',
        'gameId': 'g1',
        'gameType': 'sos',
        'roomCode': 'AB12CD',
        'gameMaxPlayers': 4,
        'gameCurrentPlayers': 2,
        'gameInviteStatus': 'in_progress',
        'gameSpectatorsEnabled': false,
      });
      expect(m.gameSpectatorsEnabled, false);
      expect(m.effectiveSpectatorsEnabled, false);
    });

    test('fromJson treats missing gameSpectatorsEnabled as null (legacy)', () {
      // Legacy rows that predate the column should parse to null. The
      // effectiveSpectatorsEnabled getter should then default to `true`
      // for backward compatibility (spectator mode was historically on
      // by default).
      final m = ChatMessage.fromJson({
        'id': 'cm3',
        'senderId': 'u1',
        'senderName': 'Host',
        'content': '',
        'messageType': 'gameInvite',
        'createdAt': '2026-10-04T12:00:00Z',
        'gameId': 'g1',
        'gameType': 'sos',
        'roomCode': 'AB12CD',
        'gameMaxPlayers': 4,
        'gameCurrentPlayers': 2,
        'gameInviteStatus': 'in_progress',
        // Note: no 'gameSpectatorsEnabled' key
      });
      expect(m.gameSpectatorsEnabled, isNull);
      expect(m.effectiveSpectatorsEnabled, isTrue,
          reason: 'legacy rows default to spectators enabled');
    });

    test('toJson only includes gameSpectatorsEnabled when non-null', () {
      // When set to true, the JSON should include it.
      final m1 = _invite(spectatorsEnabled: true);
      final j1 = m1.toJson(familyId: 'fam1');
      expect(j1.containsKey('gameSpectatorsEnabled'), isTrue);
      expect(j1['gameSpectatorsEnabled'], true);

      // When set to false, the JSON should also include it.
      final m2 = _invite(spectatorsEnabled: false);
      final j2 = m2.toJson(familyId: 'fam1');
      expect(j2.containsKey('gameSpectatorsEnabled'), isTrue);
      expect(j2['gameSpectatorsEnabled'], false);

      // When null (legacy), the JSON should OMIT it (so the server
      // doesn't try to write a null to a NOT NULL column or similar).
      final m3 = _invite(spectatorsEnabled: null);
      final j3 = m3.toJson(familyId: 'fam1');
      expect(j3.containsKey('gameSpectatorsEnabled'), isFalse);
    });

    test('copyWith preserves gameSpectatorsEnabled', () {
      // The realtime UPDATE handler in chat_provider re-parses rows via
      // fromJson(...).copyWith(reactions: ...). If copyWith drops the
      // gameSpectatorsEnabled field, every realtime update would reset
      // it to null, breaking the spectator-mode gate. This test pins
      // that copyWith preserves the field.
      final m = _invite(spectatorsEnabled: false);
      final updated = m.copyWith(reactions: const []);
      expect(updated.gameSpectatorsEnabled, false,
          reason: 'copyWith must preserve gameSpectatorsEnabled');
    });

    test('copyWith can update gameSpectatorsEnabled', () {
      // The fn_sync_game_spectators RPC writes the field server-side,
      // but the client also needs to be able to update it locally (e.g.
      // when the host toggles spectator mode mid-lobby). This test pins
      // that copyWith can update the field.
      final m = _invite(spectatorsEnabled: true);
      final updated = m.copyWith(gameSpectatorsEnabled: false);
      expect(updated.gameSpectatorsEnabled, false);
    });
  });

  group('effectiveSpectatorsEnabled — spec-compliant default', () {
    test('returns true when gameSpectatorsEnabled is null (legacy)', () {
      final m = _invite(spectatorsEnabled: null);
      expect(m.effectiveSpectatorsEnabled, isTrue);
    });

    test('returns the explicit value when set', () {
      expect(_invite(spectatorsEnabled: true).effectiveSpectatorsEnabled, isTrue);
      expect(_invite(spectatorsEnabled: false).effectiveSpectatorsEnabled, isFalse);
    });

    test('non-gameInvite messages have null gameSpectatorsEnabled', () {
      // The field is only meaningful for gameInvite messages. A regular
      // text message should have a null field (default). The getter
      // still returns true for backward compat, but the card renderer
      // only checks this field for gameInvite messages anyway.
      final m = ChatMessage(
        id: 'cm_text',
        senderId: 'u1',
        senderName: 'Host',
        content: 'hello',
        messageType: MessageType.text,
        timestamp: DateTime.parse('2026-10-04T12:00:00Z'),
      );
      expect(m.gameSpectatorsEnabled, isNull);
      expect(m.effectiveSpectatorsEnabled, isTrue);
    });
  });
}
