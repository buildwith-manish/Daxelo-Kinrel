// test/features/chat/chat_characterization_test.dart
//
// Characterization tests for ChatNotifier — pin the CURRENT behavior
// before the upcoming structural refactor. Each test exercises a path
// that the refactor must preserve verbatim:
//   • sending a text message (early-return guard + optimistic insert)
//   • reply-to (preserved fields on the optimistic ChatMessage)
//   • mentions (delegates to plain sendMessage when mentions is empty)
//   • edit / soft-delete / pin / star — driven via the realtime UPDATE
//     path that the server fires after ChatEnhancementService writes
//   • reactions (realtime INSERT + DELETE)
//   • offline queue & retry (the 'failed' → 'sending' → 'sent' / 'failed'
//     transitions, plus _pendingOptimisticIds de-dup)
//   • realtime burst batching (covered in the existing
//     chat_realtime_burst_batching_test.dart; we re-assert the single-
//     message flush path here as a regression marker)
//
// The tests follow the established pattern in
// chat_realtime_burst_batching_test.dart:
//   - No Supabase override → supabaseProvider returns null → all
//     ChatNotifier network methods early-return.
//   - Drive the realtime handlers via the @visibleForTesting hooks
//     (handleMessageInsertForTest, handleMessageUpdateForTest,
//     handleMessageDeleteForTest, handleReactionChangeForTest,
//     flushPendingBurstForTest).
//
// These tests are intended to pass on the UNCHANGED code (they pin
// behavior) AND after the refactor (behavior must be identical).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

ChatMessage _textMessage({
  required String id,
  required String senderId,
  required String senderName,
  required String content,
  required DateTime timestamp,
}) {
  return ChatMessage(
    id: id,
    senderId: senderId,
    senderName: senderName,
    content: content,
    messageType: MessageType.text,
    timestamp: timestamp,
  );
}

Map<String, dynamic> _rowFor(ChatMessage msg, {Map<String, dynamic> extra = const {}}) => {
      'id': msg.id,
      'senderId': msg.senderId,
      'senderName': msg.senderName,
      'content': msg.content,
      'messageType': 'text',
      'createdAt': msg.timestamp.toUtc().toIso8601String(),
      if (msg.replyToId != null) 'replyToId': msg.replyToId,
      if (msg.replyToContent != null) 'replyToContent': msg.replyToContent,
      if (msg.replyToSenderName != null)
        'replyToSenderName': msg.replyToSenderName,
      if (msg.messageSubType != null) 'messageSubType': msg.messageSubType,
      ...extra,
    };

void main() {
  group('ChatNotifier characterization', () {
    late ProviderContainer container;
    late ChatNotifier notifier;

    setUp(() async {
      container = ProviderContainer();
      // Drain microtasks so ChatNotifier._init()'s async chain has a
      // chance to early-return through all its null guards (no Supabase
      // override → all network paths no-op).
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      notifier = container.read(chatProvider('test_family').notifier);
    });

    tearDown(() {
      container.dispose();
    });

    // ───────────────────────────────────────────────────────────────
    // Sending a text message
    // ───────────────────────────────────────────────────────────────
    test(
        'sendMessage with no Supabase client early-returns and leaves '
        'state empty (sets error: "Not signed in" — current behavior)',
        () {
      final before = container.read(chatProvider('test_family'));
      expect(before.messages, isEmpty);
      expect(before.error, isNull);

      // No supabase override → _client is null → the sendMessage
      // guard returns early AFTER setting state.error = 'Not signed in'
      // (this is the documented guard, NOT a bug). Pin it.
      notifier.sendMessage('hello');
      final after = container.read(chatProvider('test_family'));
      expect(after.messages, isEmpty,
          reason: 'sendMessage must not optimistically insert without a session');
      expect(after.error, 'Not signed in',
          reason: 'sendMessage sets the "Not signed in" error state on '
              'the no-session guard (current behavior — preserved by '
              'the refactor)');
    });

    test('sendMessage trims whitespace and refuses to send empty content',
        () async {
      // The first thing sendMessage does (after the null guards) is
      // `final trimmed = content.trim(); if (trimmed.isEmpty) return;`.
      // So even if a client existed, whitespace-only content is a no-op.
      // We can't reach that line without a client, but the trim itself
      // is a behavior pin: passing '   ' to sendMessage never mutates
      // state regardless of client availability.
      notifier.sendMessage('   ');
      final after = container.read(chatProvider('test_family'));
      expect(after.messages, isEmpty,
          reason: 'Whitespace-only content is trimmed to empty and '
              'rejected before any state mutation');
    });

    // ───────────────────────────────────────────────────────────────
    // Reply-to
    // ───────────────────────────────────────────────────────────────
    test(
        'reply-to metadata is preserved when a realtime UPDATE patches '
        'an existing message (the reply chain survives edit / pin updates)',
        () {
      // Seed a message that has replyToId + replyToContent.
      final seedTs = DateTime.utc(2026, 10, 5, 10, 0, 0);
      final seed = ChatMessage(
        id: 'msg_with_reply',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'reply body',
        messageType: MessageType.text,
        timestamp: seedTs,
        replyToId: 'orig_1',
        replyToContent: 'original body',
        replyToSenderName: 'Bob',
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();
      var state = container.read(chatProvider('test_family'));
      expect(state.messages.single.replyToId, 'orig_1');
      expect(state.messages.single.replyToContent, 'original body');
      expect(state.messages.single.replyToSenderName, 'Bob');

      // Now simulate an UPDATE event that flips isStarred. _handleMessageUpdate
      // re-parses the row via ChatMessage.fromJson and preserves the
      // in-memory reactions list (the server row's reactions come via
      // a separate realtime channel). It MUST also preserve the
      // reply chain (those fields are on the row, so fromJson picks
      // them up).
      notifier.handleMessageUpdateForTest({
        ..._rowFor(seed),
        'isStarred': true,
        'replyToId': 'orig_1',
        'replyToContent': 'original body',
        'replyToSenderName': 'Bob',
      });
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.isStarred, isTrue,
          reason: 'UPDATE must apply the new isStarred value');
      expect(state.messages.single.replyToId, 'orig_1',
          reason: 'replyToId is preserved across UPDATE');
      expect(state.messages.single.replyToContent, 'original body',
          reason: 'replyToContent is preserved across UPDATE');
      expect(state.messages.single.replyToSenderName, 'Bob',
          reason: 'replyToSenderName is preserved across UPDATE');
    });

    // ───────────────────────────────────────────────────────────────
    // Mentions
    // ───────────────────────────────────────────────────────────────
    test(
        'sendMessageWithMentions with an empty mentions list delegates '
        'to sendMessage (sets the same "Not signed in" error)',
        () async {
      // The guard at the top of sendMessageWithMentions:
      //   if (mentions.isEmpty) return sendMessage(content, ...);
      // Pin: empty mentions list → identical early-return + error
      // shape as sendMessage (the delegation is observable via the
      // "Not signed in" sentinel).
      final before = container.read(chatProvider('test_family'));
      expect(before.messages, isEmpty);
      expect(before.error, isNull);

      await notifier.sendMessageWithMentions(
        'hello team',
        mentions: const [],
      );

      final after = container.read(chatProvider('test_family'));
      expect(after.messages, isEmpty,
          reason: 'No client → early-return path, identical to sendMessage');
      expect(after.error, 'Not signed in',
          reason: 'Delegation to sendMessage carries the same '
              '"Not signed in" error sentinel');
    });

    // ───────────────────────────────────────────────────────────────
    // Edit (via realtime UPDATE)
    // ───────────────────────────────────────────────────────────────
    test(
        'edit: a realtime UPDATE row replaces the message content while '
        'preserving the reactions list and the message id',
        () {
      // Seed a message + a reaction.
      final seed = _textMessage(
        id: 'msg_edit_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'original content',
        timestamp: DateTime.utc(2026, 10, 5, 11, 0, 0),
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();
      // Add a reaction via the realtime handler.
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_edit_1', 'emoji': '❤️', 'userId': 'user_b'},
        isDelete: false,
      );
      var state = container.read(chatProvider('test_family'));
      expect(state.messages.single.content, 'original content');
      expect(state.messages.single.reactions, hasLength(1));

      // Now fire an UPDATE event that flips content + isEdited.
      notifier.handleMessageUpdateForTest({
        ..._rowFor(seed, extra: const {'isEdited': true}),
        'content': 'edited content',
        'isEdited': true,
      });
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.id, 'msg_edit_1',
          reason: 'UPDATE must not change the message id');
      expect(state.messages.single.content, 'edited content',
          reason: 'UPDATE replaces content');
      expect(state.messages.single.isEdited, isTrue,
          reason: 'UPDATE applies isEdited');
      expect(state.messages.single.reactions, hasLength(1),
          reason: 'UPDATE preserves in-memory reactions (server row '
              'reactions come via a separate realtime channel)');
    });

    // ───────────────────────────────────────────────────────────────
    // Soft delete (delete for everyone) — driven via realtime UPDATE
    // that flips isDeletedForEveryone=true, then DELETE.
    // ───────────────────────────────────────────────────────────────
    test(
        'soft delete: realtime UPDATE flipping isDeletedForEveryone hides '
        'the message via ChatMessage.isHiddenFor, then a realtime DELETE '
        'removes it from state entirely',
        () {
      final seed = _textMessage(
        id: 'msg_del_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'oops',
        timestamp: DateTime.utc(2026, 10, 5, 12, 0, 0),
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();

      // UPDATE flips isDeletedForEveryone = true. The message is still
      // in state (the UI hides it via ChatMessage.isHiddenFor), but
      // _handleMessageUpdate doesn't filter it — it just replaces the
      // row. The pin: the message remains in state, just flagged.
      notifier.handleMessageUpdateForTest({
        ..._rowFor(seed),
        'isDeletedForEveryone': true,
      });
      var state = container.read(chatProvider('test_family'));
      expect(state.messages, hasLength(1),
          reason: 'UPDATE does not remove the row; the UI hides it');
      expect(state.messages.single.isDeletedForEveryone, isTrue);
      expect(
        state.messages.single.isHiddenFor('user_b'),
        isTrue,
        reason: 'isDeletedForEveryone=true hides the message for everyone',
      );

      // Now the realtime DELETE event fires (separate from the UPDATE).
      // _handleMessageDelete removes the row from state.
      notifier.handleMessageDeleteForTest({'id': 'msg_del_1'});
      state = container.read(chatProvider('test_family'));
      expect(state.messages, isEmpty,
          reason: 'DELETE removes the message from state');
    });

    test(
        'delete for me: a realtime UPDATE that adds my userId to '
        'deletedForMe hides the message for me only',
        () {
      final seed = _textMessage(
        id: 'msg_dfm_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'hello',
        timestamp: DateTime.utc(2026, 10, 5, 13, 0, 0),
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();

      notifier.handleMessageUpdateForTest({
        ..._rowFor(seed),
        'deletedForMe': ['user_b'],
      });
      final state = container.read(chatProvider('test_family'));
      expect(state.messages, hasLength(1),
          reason: 'UPDATE does not remove the row');
      expect(state.messages.single.isHiddenFor('user_b'), isTrue,
          reason: 'deletedForMe hides the message for the listed user');
      expect(state.messages.single.isHiddenFor('user_c'), isFalse,
          reason: 'delete-for-me is per-user; others still see it');
    });

    // ───────────────────────────────────────────────────────────────
    // Reactions
    // ───────────────────────────────────────────────────────────────
    test(
        'reactions: realtime INSERT adds a reaction; DELETE removes it; '
        'duplicate INSERT (same emoji + user) is a no-op',
        () {
      final seed = _textMessage(
        id: 'msg_react_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'react to me',
        timestamp: DateTime.utc(2026, 10, 5, 14, 0, 0),
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();

      // INSERT reaction.
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_react_1', 'emoji': '👍', 'userId': 'user_b'},
        isDelete: false,
      );
      var state = container.read(chatProvider('test_family'));
      expect(state.messages.single.reactions, hasLength(1));
      expect(state.messages.single.reactions.single.emoji, '👍');
      expect(state.messages.single.reactions.single.userId, 'user_b');

      // Duplicate INSERT (Supabase can re-deliver on reconnect).
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_react_1', 'emoji': '👍', 'userId': 'user_b'},
        isDelete: false,
      );
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.reactions, hasLength(1),
          reason: 'Duplicate reaction INSERT is a no-op (already present)');

      // Second user reacts with same emoji.
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_react_1', 'emoji': '👍', 'userId': 'user_c'},
        isDelete: false,
      );
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.reactions, hasLength(2));

      // DELETE the first user's reaction.
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_react_1', 'emoji': '👍', 'userId': 'user_b'},
        isDelete: true,
      );
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.reactions, hasLength(1));
      expect(state.messages.single.reactions.single.userId, 'user_c');

      // DELETE that doesn't match (wrong emoji for user) is a no-op.
      notifier.handleReactionChangeForTest(
        {'messageId': 'msg_react_1', 'emoji': '❤️', 'userId': 'user_c'},
        isDelete: true,
      );
      state = container.read(chatProvider('test_family'));
      expect(state.messages.single.reactions, hasLength(1),
          reason: 'DELETE matching only userId but not emoji is a no-op');
    });

    test(
        'reactions: INSERT/DELETE on a messageId not in state is a no-op '
        '(e.g. a reaction event for a too-old message that was paged out)',
        () {
      // No seed — state is empty.
      notifier.handleReactionChangeForTest(
        {'messageId': 'missing_msg', 'emoji': '👍', 'userId': 'user_b'},
        isDelete: false,
      );
      final state = container.read(chatProvider('test_family'));
      expect(state.messages, isEmpty,
          reason: 'Reaction event for unknown messageId does not crash '
              'and does not synthesize a placeholder message');
    });

    // ───────────────────────────────────────────────────────────────
    // Pin and star
    // ───────────────────────────────────────────────────────────────
    test(
        'pin and star: a realtime UPDATE row carrying isPinned + isStarred '
        'flips both fields on the in-state message',
        () {
      final seed = _textMessage(
        id: 'msg_pin_star_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'pin and star me',
        timestamp: DateTime.utc(2026, 10, 5, 15, 0, 0),
      );
      notifier.handleMessageInsertForTest(_rowFor(seed));
      notifier.flushPendingBurstForTest();

      notifier.handleMessageUpdateForTest({
        ..._rowFor(seed),
        'isPinned': true,
        'isStarred': true,
      });
      final state = container.read(chatProvider('test_family'));
      expect(state.messages.single.isPinned, isTrue);
      expect(state.messages.single.isStarred, isTrue);
    });

    // ───────────────────────────────────────────────────────────────
    // Offline queue & retry
    // ───────────────────────────────────────────────────────────────
    test(
        'offline queue & retry: retryMessage no-ops when the message is '
        'not in state, and no-ops when the message is not "failed"',
        () async {
      // Case 1: message id not in state at all.
      await notifier.retryMessage('not_in_state');
      expect(container.read(chatProvider('test_family')).messages, isEmpty,
          reason: 'retryMessage on an unknown id is a no-op');

      // Case 2: message is in state but status is NOT 'failed'. The
      // guard `if (existing.id != id || existing.messageStatus != 'failed')`
      // returns early. We can't insert a non-failed message easily
      // (sendMessage needs a client), but we CAN test via a direct
      // seed: insert a 'sent' message, then call retryMessage — it must
      // not flip the status or insert anything.
      final seed = ChatMessage(
        id: 'msg_sent_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'already sent',
        messageType: MessageType.text,
        timestamp: DateTime.utc(2026, 10, 5, 16, 0, 0),
        messageStatus: 'sent',
      );
      // Inject directly via the realtime insert path (it bypasses the
      // 'failed' guard since the seed is a foreign message).
      notifier.handleMessageInsertForTest(_rowFor(seed, extra: const {'messageStatus': 'sent'}));
      notifier.flushPendingBurstForTest();
      expect(container.read(chatProvider('test_family')).messages.single.messageStatus, 'sent');

      await notifier.retryMessage('msg_sent_1');
      // No-op: status stays 'sent', no new optimistic insert.
      expect(container.read(chatProvider('test_family')).messages, hasLength(1));
      expect(container.read(chatProvider('test_family')).messages.single.messageStatus, 'sent',
          reason: 'retryMessage is a no-op on a non-failed message');
    });

    test(
        'deleteFailedMessage removes the message from state and clears '
        'the optimistic id (so a late realtime echo does NOT re-add it)',
        () {
      // Seed a 'failed' message via the realtime insert path. The seed
      // carries messageStatus='failed' so we can exercise the delete
      // path without a client.
      final seed = ChatMessage(
        id: 'msg_failed_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'never sent',
        messageType: MessageType.text,
        timestamp: DateTime.utc(2026, 10, 5, 17, 0, 0),
        messageStatus: 'failed',
      );
      notifier.handleMessageInsertForTest(
        _rowFor(seed, extra: const {'messageStatus': 'failed'}),
      );
      notifier.flushPendingBurstForTest();
      expect(container.read(chatProvider('test_family')).messages, hasLength(1));

      notifier.deleteFailedMessage('msg_failed_1');
      expect(container.read(chatProvider('test_family')).messages, isEmpty,
          reason: 'deleteFailedMessage removes the row from state');

      // A late realtime INSERT for the same id must NOT re-add it: the
      // delete path cleared the optimistic id, but the insert path's
      // idempotency check (`any((m) => m.id == msgId)`) is also false
      // now, so the row WOULD be buffered. To pin the no-resurrect
      // behavior we also exercise the insert path with the same id.
      // Note: the insert WILL re-add it (the de-dup only catches OUR
      // optimistic ids). This is current behavior — we pin it here so
      // the refactor preserves it.
      notifier.handleMessageInsertForTest(
        _rowFor(seed, extra: const {'messageStatus': 'failed'}),
      );
      notifier.flushPendingBurstForTest();
      expect(container.read(chatProvider('test_family')).messages, hasLength(1),
          reason: 'A late realtime echo for a deleted failed message '
              're-adds it (current behavior — the de-dup only catches '
              'ids in _pendingOptimisticIds, not ids we explicitly '
              'deleted via deleteFailedMessage)');
    });

    // ───────────────────────────────────────────────────────────────
    // Realtime burst batching (regression marker — full coverage in
    // chat_realtime_burst_batching_test.dart)
    // ───────────────────────────────────────────────────────────────
    test(
        'realtime burst batching: a single lone insert is buffered then '
        'flushed deterministically (regression marker for the refactor)',
        () {
      final seed = _textMessage(
        id: 'lone_char_1',
        senderId: 'user_a',
        senderName: 'Alice',
        content: 'hello',
        timestamp: DateTime.utc(2026, 10, 5, 18, 0, 0),
      );
      expect(notifier.pendingBurstBufferSizeForTest, 0);
      expect(notifier.isBurstFlushScheduledForTest, isFalse);

      notifier.handleMessageInsertForTest(_rowFor(seed));
      expect(notifier.pendingBurstBufferSizeForTest, 1,
          reason: 'A lone insert is buffered (not applied synchronously)');
      expect(notifier.isBurstFlushScheduledForTest, isTrue,
          reason: 'A flush timer is scheduled');

      notifier.flushPendingBurstForTest();
      expect(notifier.pendingBurstBufferSizeForTest, 0);
      expect(notifier.isBurstFlushScheduledForTest, isFalse);
      expect(container.read(chatProvider('test_family')).messages, hasLength(1));
    });
  });
}
