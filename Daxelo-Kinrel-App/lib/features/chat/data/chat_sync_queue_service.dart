// lib/features/chat/data/chat_sync_queue_service.dart
//
// DAXELO KINREL — Feature 4: Offline-First Chat Sync Queue
//
// Reuses the existing PendingOperations Drift table (defined in
// lib/core/database/app_database.dart) to queue chat actions taken while
// offline. On reconnect, the queue is flushed in order — each action is
// replayed via the Socket.IO emit methods with an idempotency key so the
// server deduplicates (no duplicate messages, no duplicate reactions).
//
// Tracked action types:
//   - send_message: emitChatMessage with clientMessageId=tempId
//   - send_reaction: emitAddReaction (idempotent via ChatReaction unique constraint)
//   - mark_read: emitMarkAsRead (idempotent via ChatReadReceipt unique constraint)
//
// Conflict resolution for reactions:
//   Reactions are ADDITIVE — if two users react to the same message while
//   both are offline, both reactions should appear when they reconnect
//   (not overwrite each other). The server's ChatReaction table has
//   @@unique([messageId, userId, emoji]) which enforces this: each user's
//   reaction is a distinct row, so concurrent offline reactions merge
//   naturally (last-write-wins per (message, user, emoji) tuple, not
//   per-message).
//
// The existing message_queue_service.dart handles retry for FAILED
// messages (network timeout, server error). THIS service handles the
// broader offline-sync case: actions taken while the socket is
// disconnected, replayed in order on reconnect.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/isar_database.dart' show isarProvider;
import '../../../core/network/socket_service.dart';
import '../../../core/services/supabase_service.dart';

/// The type of chat action queued for sync.
enum ChatSyncActionType {
  sendMessage,
  addReaction,
  removeReaction,
  markRead,
  pinMessage,
  unpinMessage,
}

/// A queued chat action with its idempotency key + payload.
class ChatSyncAction {
  const ChatSyncAction({
    required this.id,
    required this.type,
    required this.familyId,
    required this.idempotencyKey,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  final int id;
  final ChatSyncActionType type;
  final String familyId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;

  factory ChatSyncAction.fromPendingOperation(PendingOperation op) {
    return ChatSyncAction(
      id: op.id,
      type: ChatSyncActionType.values.firstWhere(
        (t) => t.name == op.operationType,
        orElse: () => ChatSyncActionType.sendMessage,
      ),
      familyId: op.collection, // reuse collection field for familyId
      idempotencyKey: op.recordId ?? '',
      payload: op.payload != null
          ? jsonDecode(op.payload!) as Map<String, dynamic>
          : <String, dynamic>{},
      createdAt: op.createdAt,
      retryCount: op.retryCount,
    );
  }
}

/// The ChatSyncQueueService manages offline chat actions.
///
/// Usage:
///   1. When the socket disconnects, the chat_provider calls enqueue*()
///      for each action instead of emitting directly.
///   2. When the socket reconnects, the chat_provider calls flush().
///   3. Each action is replayed in order (oldest first) via the socket
///      emit methods, with the idempotencyKey passed as tempId so the
///      server deduplicates.
class ChatSyncQueueService {
  ChatSyncQueueService(this._ref, this._db);
  final Ref _ref;
  final AppDatabase _db;

  bool _flushing = false;

  /// Enqueue a send-message action. The [idempotencyKey] should be a
  /// client-generated unique ID (e.g. 'cm_<timestamp>_<random>') that
  /// the server uses for dedup on retry.
  Future<int> enqueueSendMessage({
    required String familyId,
    required String idempotencyKey,
    required String content,
    String messageType = 'text',
    String? replyToId,
  }) async {
    return _enqueue(
      type: ChatSyncActionType.sendMessage,
      familyId: familyId,
      idempotencyKey: idempotencyKey,
      payload: {
        'content': content,
        'messageType': messageType,
        if (replyToId != null) 'replyToId': replyToId,
      },
    );
  }

  /// Enqueue an add-reaction action. Idempotent via the server's
  /// ChatReaction @@unique([messageId, userId, emoji]) constraint.
  Future<int> enqueueAddReaction({
    required String familyId,
    required String messageId,
    required String emoji,
  }) async {
    return _enqueue(
      type: ChatSyncActionType.addReaction,
      familyId: familyId,
      // The idempotency key for reactions is the (messageId, emoji) tuple
      // — the server's unique constraint deduplicates.
      idempotencyKey: 'reaction_${messageId}_$emoji',
      payload: {
        'messageId': messageId,
        'emoji': emoji,
      },
    );
  }

  /// Enqueue a mark-read action. Idempotent via ChatReadReceipt unique.
  Future<int> enqueueMarkRead({
    required String familyId,
    String? messageId,
  }) async {
    return _enqueue(
      type: ChatSyncActionType.markRead,
      familyId: familyId,
      idempotencyKey: 'read_${familyId}_${messageId ?? 'all'}',
      payload: {
        if (messageId != null) 'messageId': messageId,
      },
    );
  }

  Future<int> _enqueue({
    required ChatSyncActionType type,
    required String familyId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final id = await _db.upsertPendingOperation(
      PendingOperationsCompanion.insert(
        operationType: type.name,
        collection: familyId,
        recordId: Value(idempotencyKey),
        payload: Value(jsonEncode(payload)),
        createdAt: DateTime.now(),
      ),
    );
    debugPrint(
      '[ChatSyncQueue] Enqueued ${type.name} for family $familyId (id=$id, key=$idempotencyKey)',
    );
    return id;
  }

  /// Get all queued actions for a family, oldest first.
  Future<List<ChatSyncAction>> getQueuedActions(String familyId) async {
    final ops = await _db.getPendingOperations();
    return ops
        .where((op) => op.collection == familyId)
        .map((op) => ChatSyncAction.fromPendingOperation(op))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Flush all queued actions for a family, in order (oldest first).
  /// Called by the chat_provider on socket reconnect.
  ///
  /// Each action is replayed via the socket emit methods. If the emit
  /// succeeds (socket is connected), the action is dequeued. If it fails
  /// (socket drops mid-flush), the action stays in the queue with a
  /// bumped retryCount — the next flush will retry it.
  Future<void> flushFamily(String familyId) async {
    if (_flushing) return; // prevent concurrent flushes
    _flushing = true;
    try {
      final socket = _ref.read(socketServiceProvider);
      if (!socket.isConnected) {
        debugPrint('[ChatSyncQueue] Socket not connected — skipping flush');
        return;
      }

      final actions = await getQueuedActions(familyId);
      if (actions.isEmpty) return;

      debugPrint(
        '[ChatSyncQueue] Flushing ${actions.length} action(s) for family $familyId',
      );

      for (final action in actions) {
        final success = await _replayAction(socket, action);
        if (success) {
          await _db.deletePendingOperation(action.id);
          debugPrint('[ChatSyncQueue] Replayed + dequeued ${action.type.name} (id=${action.id})');
        } else {
          // Bump retryCount — the action stays in the queue.
          await _db.upsertPendingOperation(
            PendingOperationsCompanion(
              id: Value(action.id),
              operationType: Value(action.type.name),
              collection: Value(action.familyId),
              recordId: Value(action.idempotencyKey),
              payload: Value(jsonEncode(action.payload)),
              createdAt: Value(action.createdAt),
              retryCount: Value(action.retryCount + 1),
              lastRetryAt: Value(DateTime.now()),
            ),
          );
          debugPrint(
            '[ChatSyncQueue] Replay failed for ${action.type.name} (id=${action.id}, retry=${action.retryCount + 1})',
          );
          // Stop flushing on the first failure — the socket probably dropped.
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Replay a single action via the socket. Returns true on success.
  Future<bool> _replayAction(
    SocketService socket,
    ChatSyncAction action,
  ) async {
    try {
      switch (action.type) {
        case ChatSyncActionType.sendMessage:
          // Pass the idempotencyKey as tempId so the server deduplicates.
          socket.emitChatMessage(
            familyId: action.familyId,
            content: action.payload['content'] as String,
            messageType: action.payload['messageType'] as String? ?? 'text',
            replyToId: action.payload['replyToId'] as String?,
            tempId: action.idempotencyKey,
          );
          return true;

        case ChatSyncActionType.addReaction:
          socket.emitAddReaction(
            familyId: action.familyId,
            messageId: action.payload['messageId'] as String,
            emoji: action.payload['emoji'] as String,
          );
          return true;

        case ChatSyncActionType.removeReaction:
          socket.emitRemoveReaction(
            familyId: action.familyId,
            messageId: action.payload['messageId'] as String,
            emoji: action.payload['emoji'] as String,
          );
          return true;

        case ChatSyncActionType.markRead:
          socket.emitMarkAsRead(
            familyId: action.familyId,
            messageId: action.payload['messageId'] as String?,
          );
          return true;

        case ChatSyncActionType.pinMessage:
          socket.emitPinMessage(
            familyId: action.familyId,
            messageId: action.payload['messageId'] as String,
          );
          return true;

        case ChatSyncActionType.unpinMessage:
          socket.emitUnpinMessage(
            familyId: action.familyId,
            messageId: action.payload['messageId'] as String,
          );
          return true;
      }
    } catch (e) {
      debugPrint('[ChatSyncQueue] Replay error for ${action.type.name}: $e');
      return false;
    }
  }

  /// Clear all queued actions for a family (e.g. on sign-out).
  Future<void> clearFamily(String familyId) async {
    final ops = await _db.getPendingOperations();
    for (final op in ops) {
      if (op.collection == familyId) {
        await _db.deletePendingOperation(op.id);
      }
    }
  }
}

/// Riverpod provider for the ChatSyncQueueService.
final chatSyncQueueServiceProvider = Provider<ChatSyncQueueService>((ref) {
  // The AppDatabase is a singleton provided by the isarProvider (legacy
  // name — the app migrated from Isar to Drift but kept the provider name).
  final db = ref.watch(isarProvider);
  return ChatSyncQueueService(ref, db);
});
