// test/features/chat/dm_game_invite_adapter_test.dart
//
// Pin-to-pin parity tests for the DIRECT MESSAGE game-invite card.
//
// The DM invite card renders through the SAME shared widget as the group
// chat card (MessageBubble._buildGameInviteCard ← ChatMessageList). The
// DirectMessage → ChatMessage adapter (direct_message_adapter.dart) maps
// the DM's JSON payload into the ChatMessage fields that widget reads.
// Since migration 20261007000000 the payload JSON is kept live by the
// SAME server-side state machine that maintains the group chat's
// ChatMessage columns (fn_sync_game_invite_status →
// fn_sync_dm_game_invites: triggers + expiry sweep + orphan cleanup), so
// the DM card and the group card must always classify into the same
// lifecycle state from the same server-written values.
//
// These tests codify that contract:
//   • Payload fields (status / currentPlayers / winnerName / completedAt /
//     spectatorsEnabled) map onto the exact ChatMessage fields the shared
//     card reads.
//   • Legacy payloads without a status key default to 'pending' — the same
//     insert default the group ChatMessage row gets.
//   • The shared classifier (classifyGameInviteStatus) treats a DM-derived
//     status identically to a group-derived status for every lifecycle
//     state, including the "room closed → expired" case.
//   • Invite copy: the DM payload's fallback message matches the group
//     card's default phrasing ("X wants to play Y with you").

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/data/direct_message_adapter.dart';
import 'package:kinrel/features/chat/data/direct_message_provider.dart';
import 'package:kinrel/features/chat/presentation/widgets/game_invite_status_chip.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

DirectMessage _inviteDm(Map<String, dynamic> payload) {
  return DirectMessage(
    id: 'dm_test_${payload['gameId'] ?? 'x'}',
    senderId: 'user_peer',
    receiverId: 'user_me',
    content: jsonEncode(payload),
    messageType: 'gameInvite',
    isRead: false,
    createdAt: DateTime.parse('2026-10-06T12:00:00Z'),
  );
}

const _basePayload = <String, dynamic>{
  'inviteId': 'inv_123',
  'gameType': 'sos',
  'gameId': '11111111-2222-3333-4444-555555555555',
  'roomCode': '798C99',
  'familyId': 'fam_1',
  'fromUserId': 'user_peer',
  'fromName': 'Account 2',
  'maxPlayers': 2,
  'currentPlayers': 1,
  'message': 'Account 2 wants to play SOS with you',
};

ChatMessage _convert(DirectMessage dm) {
  return directMessageToChatMessage(
    dm,
    myUserId: 'user_me',
    myName: 'Account 1',
    peerName: 'Account 2',
  );
}

void main() {
  group('DM invite payload → ChatMessage field mapping', () {
    test('identity fields map onto the shared card fields', () {
      final msg = _convert(_inviteDm(_basePayload));

      expect(msg.messageType, MessageType.gameInvite);
      expect(msg.gameType, 'sos');
      expect(msg.gameId, '11111111-2222-3333-4444-555555555555');
      expect(msg.roomCode, '798C99');
      expect(msg.gameMaxPlayers, 2);
      expect(msg.gameCurrentPlayers, 1);
      // The clean invite sentence is used — never the raw JSON blob.
      expect(msg.content, 'Account 2 wants to play SOS with you');
      expect(msg.content.startsWith('{'), isFalse);
    });

    test('live payload fields map onto the shared card fields', () {
      final msg = _convert(_inviteDm({
        ..._basePayload,
        'status': 'completed',
        'currentPlayers': 2,
        'winnerName': 'Account 2',
        'completedAt': '2026-10-06T12:05:30.123456+00:00',
        'spectatorsEnabled': false,
      }));

      expect(msg.gameInviteStatus, 'completed');
      expect(msg.gameCurrentPlayers, 2);
      expect(msg.gameWinnerName, 'Account 2');
      expect(msg.gameCompletedAt, isNotNull);
      expect(msg.gameCompletedAt!.toUtc(), DateTime.parse('2026-10-06T12:05:30.123456Z').toUtc());
      expect(msg.gameSpectatorsEnabled, false);
    });

    test('legacy payload without status defaults to pending (group insert default)', () {
      final msg = _convert(_inviteDm(_basePayload));
      expect(msg.gameInviteStatus, 'pending');
    });

    test('empty winnerName / invalid completedAt degrade to null', () {
      final msg = _convert(_inviteDm({
        ..._basePayload,
        'status': 'completed',
        'winnerName': '',
        'completedAt': 'not-a-date',
      }));

      expect(msg.gameWinnerName, isNull);
      expect(msg.gameCompletedAt, isNull);
    });

    test('missing message falls back to the group card phrasing', () {
      final legacyPayload = Map<String, dynamic>.from(_basePayload)
        ..remove('message');
      final msg = _convert(_inviteDm(legacyPayload));

      // Legacy rows with no `message` key read exactly like a group card
      // default: "<fromName> wants to play <game> with you".
      expect(msg.content, 'Account 2 wants to play SOS with you');
    });
  });

  group('DM and group cards classify identically (same logic)', () {
    // Every server-written unified status, including legacy aliases.
    const statuses = <String>[
      'pending',
      'in_progress',
      'accepted', // legacy alias → inProgress
      'active', // legacy alias → inProgress
      'completed',
      'expired',
      'cancelled', // legacy alias → expired
    ];

    ChatMessage groupCard(String status) => ChatMessage(
          id: 'cm_group_1',
          senderId: 'user_peer',
          senderName: 'Account 2',
          content: 'Account 2 wants to play SOS with you',
          messageType: MessageType.gameInvite,
          timestamp: DateTime.parse('2026-10-06T12:00:00Z'),
          gameType: 'sos',
          gameId: '11111111-2222-3333-4444-555555555555',
          roomCode: '798C99',
          gameMaxPlayers: 2,
          gameCurrentPlayers: 1,
          gameInviteStatus: status,
        );

    for (final status in statuses) {
      test('status "$status" → same classification in DM and group cards', () {
        final dmMsg = _convert(_inviteDm({..._basePayload, 'status': status}));
        final groupMsg = groupCard(status);

        final dmKind = classifyGameInviteStatus(dmMsg).kind;
        final groupKind = classifyGameInviteStatus(groupMsg).kind;
        expect(
          dmKind,
          groupKind,
          reason: 'DM card and group card must classify "$status" identically',
        );
        expect(
          classifyGameInviteStatus(dmMsg).label,
          classifyGameInviteStatus(groupMsg).label,
          reason: 'DM card and group card must show the same status label',
        );

        // The lifecycle getters the shared card's action-button matrix
        // uses must also agree.
        expect(dmMsg.isGameFull, groupMsg.isGameFull);
        expect(dmMsg.isGameInviteClosed, groupMsg.isGameInviteClosed);
        expect(dmMsg.isGameInProgress, groupMsg.isGameInProgress);
        expect(dmMsg.isGameCompleted, groupMsg.isGameCompleted);
        expect(dmMsg.isGameExpired, groupMsg.isGameExpired);
      });
    }

    test('room closed / hard-deleted → payload "expired" renders as Expired', () {
      // The orphan cleanup (fn_cleanup_orphaned_chat_invites) writes
      // 'expired' into the payload when the game row is hard-deleted.
      final msg = _convert(_inviteDm({..._basePayload, 'status': 'expired'}));

      expect(classifyGameInviteStatus(msg).kind, GameInviteStatusKind.expired);
      expect(msg.isGameInviteClosed, isTrue);
      expect(msg.isGameExpired, isTrue);
      expect(msg.isGameJoinable, isFalse);
    });
  });

  group('spectators parity', () {
    test('absent spectators flag → null → shared card legacy default (true)', () {
      final msg = _convert(_inviteDm(_basePayload));
      expect(msg.gameSpectatorsEnabled, isNull);
      expect(msg.effectiveSpectatorsEnabled, isTrue);
    });

    test('payload spectators flag false is honored', () {
      final msg = _convert(_inviteDm({..._basePayload, 'spectatorsEnabled': false}));
      expect(msg.effectiveSpectatorsEnabled, isFalse);
    });
  });
}

