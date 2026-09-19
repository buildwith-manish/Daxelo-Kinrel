// lib/features/chat/data/message_queue_service.dart
//
// DAXELO KINREL — Pack 13.1: Message Delivery Queue + Retry Service
//
// Handles offline message queueing and retry logic for chat messages.
// When a sendMessage call fails (network timeout, socket disconnect,
// server error), the message is stored locally with status='failed'
// and a retry button is shown in the UI.
//
// On reconnect (socket.status == connected), the queue is flushed:
// each failed message is re-sent in order. If a retry succeeds, the
// message status flips to 'sent' (and the normal delivery → read flow
// takes over). If a retry fails again, the message stays in the queue
// with a bumped retryCount.
//
// Max retries per message: 5. After that, the message is marked
// 'failed' permanently and the user must manually delete it.
//
// Storage: messages are persisted to SharedPreferences as a JSON array
// keyed by familyId, so they survive app restarts. (We intentionally
// don't use Isar/Drift here — the queue is small + ephemeral, and
// SharedPreferences is simpler + faster for this use case.)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/services/supabase_service.dart';

/// A queued (failed) message waiting for retry.
class QueuedMessage {
  const QueuedMessage({
    required this.tempId,
    required this.familyId,
    required this.content,
    required this.messageType,
    required this.replyToId,
    required this.createdAt,
    required this.retryCount,
    this.senderPersonId,
    this.senderInitials,
  });

  /// Client-generated optimistic ID. Used to match the queued message
  /// back to the optimistic message in the chat_provider's state.
  final String tempId;

  final String familyId;
  final String content;
  final String messageType;
  final String? replyToId;
  final DateTime createdAt;
  final int retryCount;
  final String? senderPersonId;
  final String? senderInitials;

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'familyId': familyId,
        'content': content,
        'messageType': messageType,
        'replyToId': replyToId,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'senderPersonId': senderPersonId,
        'senderInitials': senderInitials,
      };

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    return QueuedMessage(
      tempId: json['tempId'] as String,
      familyId: json['familyId'] as String,
      content: json['content'] as String,
      messageType: json['messageType'] as String? ?? 'text',
      replyToId: json['replyToId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      senderPersonId: json['senderPersonId'] as String?,
      senderInitials: json['senderInitials'] as String?,
    );
  }

  QueuedMessage copyWith({int? retryCount}) {
    return QueuedMessage(
      tempId: tempId,
      familyId: familyId,
      content: content,
      messageType: messageType,
      replyToId: replyToId,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      senderPersonId: senderPersonId,
      senderInitials: senderInitials,
    );
  }
}

/// Callback the chat_provider registers so we can update the optimistic
/// message's status in Riverpod state when a retry succeeds or fails.
typedef MessageStatusCallback = void Function(
  String tempId, {
  required String status,
  int? retryCount,
  String? error,
});

/// The MessageQueueService manages the failed-message retry queue.
class MessageQueueService {
  MessageQueueService(this._ref);
  final Ref _ref;

  static const _storageKey = 'chat_failed_message_queue';
  static const _maxRetries = 5;

  /// In-memory cache of the queue, keyed by familyId.
  /// Loaded from SharedPreferences on first access.
  final Map<String, List<QueuedMessage>> _queues = {};
  bool _loaded = false;

  /// Registered by the chat_provider so we can update message status
  /// in Riverpod state when a retry succeeds/fails.
  MessageStatusCallback? _statusCallback;

  /// True when a flush is in progress. Prevents concurrent flushes
  /// from double-sending the same message.
  bool _flushing = false;

  /// Register the chat_provider's status-update callback.
  void registerStatusCallback(MessageStatusCallback callback) {
    _statusCallback = callback;
  }

  /// Load the queue from SharedPreferences. Called once on first
  /// enqueue/flush; subsequent calls are no-ops.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final familyId = entry.key;
        final list = (entry.value as List)
            .map((e) => QueuedMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        _queues[familyId] = list;
      }
      if (_queues.isNotEmpty) {
        debugPrint(
          '[MessageQueue] Loaded ${_queues.values.fold(0, (a, b) => a + b.length)} queued message(s) from disk',
        );
      }
    } catch (e) {
      debugPrint('[MessageQueue] Failed to load queue: $e');
    }
  }

  /// Persist the queue to SharedPreferences.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in _queues.entries)
          entry.key: entry.value.map((m) => m.toJson()).toList(),
      });
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('[MessageQueue] Failed to persist queue: $e');
    }
  }

  /// Add a failed message to the queue. Called by the chat_provider
  /// when a sendMessage attempt fails (network timeout, socket error,
  /// server 500, etc.).
  Future<void> enqueue(QueuedMessage msg) async {
    await _ensureLoaded();
    final list = _queues.putIfAbsent(msg.familyId, () => []);
    // Don't enqueue the same tempId twice (idempotent).
    if (list.any((m) => m.tempId == msg.tempId)) return;
    list.add(msg);
    await _persist();
    debugPrint(
      '[MessageQueue] Enqueued message ${msg.tempId} for family ${msg.familyId} '
      '(retry #${msg.retryCount})',
    );
  }

  /// Remove a message from the queue (e.g. after a successful retry,
  /// or when the user deletes the failed message).
  Future<void> dequeue(String familyId, String tempId) async {
    await _ensureLoaded();
    final list = _queues[familyId];
    if (list == null) return;
    list.removeWhere((m) => m.tempId == tempId);
    if (list.isEmpty) _queues.remove(familyId);
    await _persist();
  }

  /// Get all queued (failed) messages for a family. The chat_provider
  /// uses this to render the 'failed' status + retry button on the
  /// corresponding bubbles.
  Future<List<QueuedMessage>> getQueued(String familyId) async {
    await _ensureLoaded();
    return List.unmodifiable(_queues[familyId] ?? const []);
  }

  /// Retry a single message by tempId. Returns true if the retry
  /// succeeded (message removed from queue + status flipped to 'sent'),
  /// false otherwise (status stays 'failed', retryCount bumped).
  Future<bool> retry(String familyId, String tempId) async {
    await _ensureLoaded();
    final list = _queues[familyId];
    if (list == null) return false;
    final idx = list.indexWhere((m) => m.tempId == tempId);
    if (idx == -1) return false;
    final msg = list[idx];
    if (msg.retryCount >= _maxRetries) {
      debugPrint(
        '[MessageQueue] Message $tempId exceeded max retries ($_maxRetries) — giving up',
      );
      _statusCallback?.call(tempId, status: 'failed', retryCount: msg.retryCount);
      return false;
    }
    final success = await _attemptSend(msg);
    if (success) {
      list.removeAt(idx);
      if (list.isEmpty) _queues.remove(familyId);
      await _persist();
      _statusCallback?.call(tempId, status: 'sent');
      debugPrint('[MessageQueue] Retry succeeded for $tempId');
      return true;
    } else {
      // Bump retry count + persist.
      list[idx] = msg.copyWith(retryCount: msg.retryCount + 1);
      await _persist();
      _statusCallback?.call(
        tempId,
        status: 'failed',
        retryCount: list[idx].retryCount,
      );
      debugPrint(
        '[MessageQueue] Retry failed for $tempId (attempt ${list[idx].retryCount}/$_maxRetries)',
      );
      return false;
    }
  }

  /// Flush the entire queue for a family. Called by the chat_provider
  /// on socket reconnect. Each message is retried in order; failures
  /// stay in the queue with a bumped retryCount.
  Future<void> flushFamily(String familyId) async {
    if (_flushing) return; // prevent concurrent flushes
    _flushing = true;
    try {
      await _ensureLoaded();
      final list = _queues[familyId];
      if (list == null || list.isEmpty) return;
      debugPrint(
        '[MessageQueue] Flushing ${list.length} message(s) for family $familyId',
      );
      // Iterate over a copy so we can mutate the original during iteration.
      final snapshot = List<QueuedMessage>.from(list);
      for (final msg in snapshot) {
        if (msg.retryCount >= _maxRetries) continue;
        final success = await _attemptSend(msg);
        if (success) {
          list.removeWhere((m) => m.tempId == msg.tempId);
          _statusCallback?.call(msg.tempId, status: 'sent');
        } else {
          final idx = list.indexWhere((m) => m.tempId == msg.tempId);
          if (idx != -1) {
            list[idx] = msg.copyWith(retryCount: msg.retryCount + 1);
            _statusCallback?.call(
              msg.tempId,
              status: 'failed',
              retryCount: list[idx].retryCount,
            );
          }
        }
      }
      if (list.isEmpty) _queues.remove(familyId);
      await _persist();
    } finally {
      _flushing = false;
    }
  }

  /// Attempt to send a queued message via the socket. Returns true on
  /// success (the 'chat:messageSent' ack will arrive separately and
  /// update the message with the persisted ID).
  ///
  /// We use a 10-second timeout — if the socket doesn't ack within
  /// 10s, the message is considered failed.
  Future<bool> _attemptSend(QueuedMessage msg) async {
    final socket = _ref.read(socketServiceProvider);
    final client = _ref.read(supabaseProvider);
    final myUserId = client?.auth.currentUser?.id ?? '';

    // Try Socket.IO first (preferred for chat — gives instant delivery
    // confirmation). If the socket isn't connected, fall back to the
    // REST API via Supabase insert.
    if (socket.isConnected) {
      try {
        // Emit + wait for ack with a 10s timeout.
        final completer = Completer<bool>();
        late VoidCallback unsub;
        unsub = socket.onChatMessageSent((data) {
          final message = data['message'] as Map<String, dynamic>?;
          if (message != null && message['id'] != null) {
            // The server echoes the persisted message ID. We can't
            // easily match it to our tempId here (the server doesn't
            // return tempId in the ack), so we just complete on the
            // first ack after our emit. This is imperfect — if two
            // retries are in flight, the wrong ack could complete the
            // wrong future. For now, we accept this race because the
            // chat_provider also listens for the ack and updates state.
            if (!completer.isCompleted) {
              completer.complete(true);
              unsub();
            }
          }
        });
        socket.emitChatMessage(
          familyId: msg.familyId,
          content: msg.content,
          messageType: msg.messageType,
          replyToId: msg.replyToId,
          senderPersonId: msg.senderPersonId,
          senderInitials: msg.senderInitials,
        );
        // 10s timeout — matches the user spec.
        final result = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            unsub();
            return false;
          },
        );
        return result;
      } catch (e) {
        debugPrint('[MessageQueue] Socket send failed: $e');
        return false;
      }
    }

    // Fallback: direct Supabase insert (no socket).
    if (client == null || myUserId.isEmpty) return false;
    try {
      final id = msg.tempId; // reuse the tempId as the persisted ID
      await client.from('ChatMessage').insert({
        'id': id,
        'familyId': msg.familyId,
        'senderId': myUserId,
        'senderName': client.auth.currentUser?.userMetadata?['name'] ?? 'Unknown',
        'content': msg.content,
        'messageType': msg.messageType,
        'replyToId': msg.replyToId,
        'messageStatus': 'sent',
        'readBy': [],
        'notified': false,
        'createdAt': msg.createdAt.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('[MessageQueue] Supabase insert failed: $e');
      return false;
    }
  }

  /// Clear the entire queue (e.g. on sign-out).
  Future<void> clear() async {
    _queues.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

/// Riverpod provider for the MessageQueueService.
final messageQueueServiceProvider = Provider<MessageQueueService>((ref) {
  return MessageQueueService(ref);
});
