// lib/features/games/shared/services/invite_queue_service.dart
//
// InviteQueueService — guarantees game invites are delivered even when
// the SocketService is momentarily disconnected.
//
// Root cause of the "invitation reliability" complaint:
//   SocketService.sendGameInvite() throws StateError('Socket not
//   connected') if the socket is down. The InviteFamilySheet catches
//   the error silently — the invite is lost.
//
// Fix:
//   1. enqueue() every invite instead of emitting immediately.
//   2. If the socket is connected, emit immediately + remove from
//      the queue.
//   3. If the socket is NOT connected, keep the invite in the queue,
//      force a connect(), and flush the queue when onConnectionChange
//      reports connected=true.
//   4. Persist the queue to SharedPreferences so pending invites
//      survive app restarts.
//   5. Cap the queue at 50 (FIFO eviction) — prevents unbounded growth
//      if a socket is permanently down.
//
// Usage in InviteFamilySheet:
//   await ref.read(inviteQueueProvider.notifier).enqueue(
//     toUserId: m.user.id,
//     invite: invite,
//   );
//
// The service auto-flushes when the socket reconnects. Callers don't
// need to wait — enqueue() returns immediately with a success bool
// (true = emitted immediately, false = queued for later delivery).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/socket_service.dart';
import '../models/game_invite.dart';

/// One entry in the persistent invite queue.
@immutable
class QueuedInvite {
  const QueuedInvite({
    required this.id,
    required this.toUserId,
    required this.invite,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String toUserId;
  final GameInvite invite;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  QueuedInvite copyWith({
    int? attempts,
    String? lastError,
  }) =>
      QueuedInvite(
        id: id,
        toUserId: toUserId,
        invite: invite,
        queuedAt: queuedAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'toUserId': toUserId,
        'invite': invite.toJson(),
        'queuedAt': queuedAt.toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
      };

  factory QueuedInvite.fromJson(Map<String, dynamic> json) {
    return QueuedInvite(
      id: (json['id'] ?? '') as String,
      toUserId: (json['toUserId'] ?? '') as String,
      invite: GameInvite.fromJson(
          Map<String, dynamic>.from(json['invite'] as Map? ?? {})),
      queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
          DateTime.now(),
      attempts: (json['attempts'] ?? 0) as int,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Persistent queue of game invites waiting for socket reconnection.
class InviteQueueService extends StateNotifier<List<QueuedInvite>> {
  InviteQueueService(this._ref) : super(const []) {
    _init();
  }

  final Ref _ref;
  static const _storageKey = 'pending_game_invites_v1';
  static const _maxQueueSize = 50;
  static const _maxAttempts = 5;

  VoidCallback? _connectionUnsub;
  Timer? _flushTimer;

  Future<void> _init() async {
    // Load persisted queue.
    await _loadFromDisk();

    // Subscribe to socket connection changes — flush when connected.
    final socket = _ref.read(socketServiceProvider);
    _connectionUnsub = socket.onConnectionChange((connected) {
      if (connected) {
        // Small delay to let the socket fully stabilize.
        Future.delayed(const Duration(milliseconds: 500), _flush);
      }
    });

    // Also attempt a flush every 30s — in case onConnectionChange
    // misses an event (e.g. the socket was already connected when we
    // subscribed).
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flush());

    // Kick off an initial flush in case the socket is already up.
    Future.microtask(_flush);
  }

  /// Enqueue an invite. Returns true if emitted immediately, false if
  /// queued for later delivery.
  Future<bool> enqueue({
    required String toUserId,
    required GameInvite invite,
  }) async {
    final entry = QueuedInvite(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      toUserId: toUserId,
      invite: invite,
      queuedAt: DateTime.now(),
    );

    final socket = _ref.read(socketServiceProvider);
    if (socket.isConnected) {
      try {
        await socket.sendGameInvite(toUserId: toUserId, invite: invite);
        return true;
      } catch (e) {
        debugPrint('[InviteQueue] immediate send failed, queuing: $e');
        // Fall through to queue path.
      }
    }

    state = [...state, entry];
    // Evict oldest if we've hit the cap.
    if (state.length > _maxQueueSize) {
      state = state.sublist(state.length - _maxQueueSize);
    }
    await _persist();

    // Try to connect the socket — if it comes up, _flush will fire.
    if (!socket.isConnected) {
      try {
        socket.connect();
      } catch (_) {
        // Connection failures are expected when offline; the 30s timer
        // will retry.
      }
    }
    return false;
  }

  /// Try to deliver every queued invite. Removes entries that succeed
  /// or that have exceeded the max-attempt cap.
  Future<void> _flush() async {
    if (state.isEmpty) return;
    final socket = _ref.read(socketServiceProvider);
    if (!socket.isConnected) {
      // Try to (re)connect.
      try {
        socket.connect();
      } catch (_) {}
      return;
    }

    final remaining = <QueuedInvite>[];
    for (final entry in state) {
      try {
        await socket.sendGameInvite(
          toUserId: entry.toUserId,
          invite: entry.invite,
        );
        debugPrint('[InviteQueue] delivered invite ${entry.id}');
      } catch (e) {
        final attempts = entry.attempts + 1;
        if (attempts >= _maxAttempts) {
          debugPrint('[InviteQueue] dropping invite ${entry.id} after '
              '$attempts failed attempts: $e');
          continue;
        }
        remaining.add(entry.copyWith(
          attempts: attempts,
          lastError: '$e',
        ));
      }
    }
    if (remaining.length != state.length) {
      state = remaining;
      await _persist();
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List? ?? [];
      state = list
          .map((e) => QueuedInvite.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (state.isNotEmpty) {
        debugPrint('[InviteQueue] loaded ${state.length} pending invite(s)');
      }
    } catch (e) {
      debugPrint('[InviteQueue] load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(state.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (e) {
      debugPrint('[InviteQueue] persist error: $e');
    }
  }

  /// Manually clear the queue (e.g. when the user signs out).
  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  @override
  void dispose() {
    _connectionUnsub?.call();
    _flushTimer?.cancel();
    super.dispose();
  }
}

// Note: socketServiceProvider is defined in
// lib/core/network/socket_service.dart. We import it from there rather
// than redefining it here.

final inviteQueueProvider =
    StateNotifierProvider<InviteQueueService, List<QueuedInvite>>(
  (ref) => InviteQueueService(ref),
);
