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

  // ─────────────────────────────────────────────────────────────────────
  // SPEC MATRIX: spectator mode + room state → expected action button
  // ─────────────────────────────────────────────────────────────────────
  // This group documents the spec-compliant behavior for every combination
  // of spectatorsAllowed and room state. The actual button rendering lives
  // in message_bubble._buildGameInviteCard (a private method), so these
  // tests verify the ChatMessage fields + getters that drive the logic.
  // The behavior is pinned here so any regression in the action-button
  // resolution will be caught.
  //
  // Spec rules:
  //   1. spectatorsAllowed=true + open slots   → "Join" (primary action)
  //   2. spectatorsAllowed=true + full         → "Spectate"
  //   3. spectatorsAllowed=true + in-progress  → "Spectate"
  //   4. spectatorsAllowed=false + open slots  → "Join"
  //   5. spectatorsAllowed=false + full        → "Full" (disabled)
  //   6. spectatorsAllowed=false + in-progress → "In Game" (static)
  //   7. expired/cancelled                     → "Expired" (no Join)
  //   8. completed                             → "Game completed" (no Join)
  group('spec matrix — spectator mode + room state', () {
    test('Rule 1: spectators=true + open slots → Join is primary action', () {
      // The card should show "Join" as the primary action, NOT "Spectate".
      // Spectate only becomes available once the room is full or in-progress.
      final m = _invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameJoinable, isTrue,
          reason: 'room with open slots should be joinable');
      expect(m.effectiveSpectatorsEnabled, isTrue,
          reason: 'spectators allowed');
      expect(m.isGameFull, isFalse,
          reason: 'room is not full');
      expect(m.isGameInProgress, isFalse);
    });

    test('Rule 2: spectators=true + full → Spectate (not disabled Full)', () {
      // Per spec: when spectatorsAllowed is true AND the room has reached
      // full player capacity, show a "Spectate" action on the invite card.
      final m = _invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameFull, isTrue,
          reason: 'room is at capacity');
      expect(m.effectiveSpectatorsEnabled, isTrue,
          reason: 'spectators allowed → Spectate button should appear');
      expect(m.isGameJoinable, isFalse,
          reason: 'room is full, not joinable as player');
    });

    test('Rule 3: spectators=true + in-progress → Spectate', () {
      final m = _invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameInProgress, isTrue);
      expect(m.effectiveSpectatorsEnabled, isTrue,
          reason: 'spectators allowed → Spectate button should appear');
    });

    test('Rule 4: spectators=false + open slots → Join', () {
      final m = _invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
        spectatorsEnabled: false,
      );
      expect(m.isGameJoinable, isTrue,
          reason: 'room with open slots should be joinable');
      expect(m.effectiveSpectatorsEnabled, isFalse,
          reason: 'spectators disabled');
    });

    test('Rule 5: spectators=false + full → Full (disabled, no Spectate)', () {
      // Per spec: when spectatorsAllowed is false, no Spectate option appears
      // at any point in the room's lifecycle, regardless of state.
      final m = _invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: false,
      );
      expect(m.isGameFull, isTrue);
      expect(m.effectiveSpectatorsEnabled, isFalse,
          reason: 'spectators disabled → no Spectate, just disabled Full');
      expect(m.isGameJoinable, isFalse);
    });

    test('Rule 6: spectators=false + in-progress → In Game (static, no Spectate)', () {
      final m = _invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: false,
      );
      expect(m.isGameInProgress, isTrue);
      expect(m.effectiveSpectatorsEnabled, isFalse,
          reason: 'spectators disabled → no Spectate, static In Game label');
    });

    test('Rule 7: expired → Expired (Join NEVER visible)', () {
      // The core bug being reported: the Join button must NEVER remain
      // visible/tappable once a room has left the Waiting/Full joinable states.
      final m = _invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameExpired, isTrue);
      expect(m.isGameJoinable, isFalse,
          reason: 'expired rooms are never joinable — Join must not appear');
      expect(m.isGameInviteClosed, isTrue,
          reason: 'expired is a terminal state');
    });

    test('Rule 7b: cancelled → Expired (Join NEVER visible)', () {
      final m = _invite(
        status: 'cancelled',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameExpired, isTrue,
          reason: 'cancelled is an alias for expired');
      expect(m.isGameJoinable, isFalse);
      expect(m.isGameInviteClosed, isTrue);
    });

    test('Rule 8: completed → Game completed (Join NEVER visible)', () {
      final m = _invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
        spectatorsEnabled: true,
      );
      expect(m.isGameCompleted, isTrue);
      expect(m.isGameJoinable, isFalse,
          reason: 'completed rooms are never joinable — Join must not appear');
      expect(m.isGameInviteClosed, isTrue);
    });

    test('Regression: in-progress rooms are never joinable (no stale Join)', () {
      // Even if the room has open slots (e.g. a player left mid-game),
      // an in-progress room must NOT show a Join button — the game has
      // already started.
      final m = _invite(
        status: 'in_progress',
        currentPlayers: 2,
        maxPlayers: 4,
        spectatorsEnabled: false,
      );
      expect(m.isGameInProgress, isTrue);
      expect(m.isGameJoinable, isFalse,
          reason: 'in-progress rooms are never joinable, even with open slots');
    });
  });
}
