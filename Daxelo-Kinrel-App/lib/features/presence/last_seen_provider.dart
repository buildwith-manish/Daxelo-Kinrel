// lib/features/presence/last_seen_provider.dart
//
// DAXELO KINREL — Last Seen Provider (Tier 1 chat feature)
//
// Fetches + subscribes to the UserPresence table (created by the
// 20260906180000 migration). Exposes a per-user lookup that other UI
// can use to render "online" / "last seen 5m ago" / "last seen yesterday"
// labels.
//
// The provider is family-independent — UserPresence is global per user
// (a user has exactly one presence row, shared across all their
// families). This matches WhatsApp's model: a user is either "online"
// (active in any chat) or "last seen X ago" (not active anywhere).
//
// Two ways the presence row gets updated:
//   1. The chat screen's ChatNotifier calls fn_update_last_seen(true)
//      on _subscribeToRealtime, and fn_update_last_seen(false) on
//      dispose. This catches the common case (open chat → online;
//      close chat → last seen).
//   2. A future heartbeat (not yet implemented) would call
//      fn_update_last_seen(true) every 30s while the app is foregrounded,
//      and fn_update_last_seen(false) on app background. For v1 the
//      chat-screen-open/close trigger is sufficient.
//
// Realtime: this provider subscribes to UserPresence INSERT/UPDATE
// events so the local cache stays in sync without polling. The
// migration already added UserPresence to the supabase_realtime
// publication with REPLICA IDENTITY FULL.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

/// A single user's presence state.
class UserLastSeen {
  const UserLastSeen({
    required this.userId,
    required this.isOnline,
    this.lastSeenAt,
    this.updatedAt,
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastSeenAt; // null when isOnline = true
  final DateTime? updatedAt;

  factory UserLastSeen.fromJson(Map<String, dynamic> json) {
    return UserLastSeen(
      userId: json['userId'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] == null
          ? null
          : DateTime.tryParse(json['lastSeenAt'].toString()),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.tryParse(json['updatedAt'].toString()),
    );
  }
}

/// Format a [UserLastSeen] into a human-readable label.
///
///   • isOnline → "online"
///   • lastSeenAt null → "offline" (no last-seen data yet)
///   • lastSeenAt < 1 min → "last seen just now"
///   • lastSeenAt < 60 min → "last seen 5m ago"
///   • lastSeenAt < 24 h → "last seen 5h ago"
///   • lastSeenAt < 7 d → "last seen 3d ago"
///   • else → "last seen 25/12/2026"
///
/// Returns "offline" for null presence (the user has never opened the
/// app since this feature shipped).
String formatLastSeen(UserLastSeen? presence) {
  if (presence == null) return 'offline';
  if (presence.isOnline) return 'online';
  final last = presence.lastSeenAt;
  if (last == null) return 'offline';

  final now = DateTime.now();
  final diff = now.difference(last.toLocal());

  if (diff.isNegative) return 'online'; // clock skew — treat as online
  if (diff.inSeconds < 60) return 'last seen just now';
  if (diff.inMinutes < 60) {
    return 'last seen ${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return 'last seen ${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return 'last seen ${diff.inDays}d ago';
  }
  final d = last.toLocal();
  return 'last seen ${d.day}/${d.month}/${d.year}';
}

/// Whether the user is currently online (green dot) vs. offline.
bool isUserOnline(UserLastSeen? presence) {
  if (presence == null) return false;
  return presence.isOnline;
}

/// A Riverpod StateNotifier that holds a Map<userId, UserLastSeen>
/// and keeps it in sync with the UserPresence table via Supabase
/// Realtime.
class LastSeenNotifier extends StateNotifier<Map<String, UserLastSeen>> {
  LastSeenNotifier(this._ref) : super(const {}) {
    _init();
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  bool _initialized = false;

  SupabaseClient? get _client => _ref.read(supabaseProvider);

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    final client = _client;
    if (client == null) return;

    // 1. Initial fetch of all presence rows. (RLS allows any
    // authenticated user to SELECT all rows — needed to render
    // "last seen" for members across families.)
    try {
      final response = await client
          .from('UserPresence')
          .select()
          .timeout(const Duration(seconds: 10));
      final map = <String, UserLastSeen>{};
      for (final row in response as List) {
        final p = UserLastSeen.fromJson(row as Map<String, dynamic>);
        if (p.userId.isNotEmpty) map[p.userId] = p;
      }
      if (mounted) state = map;
    } catch (e) {
      debugPrint('⚠️ LastSeenNotifier initial fetch error: $e');
    }

    // 2. Subscribe to realtime changes on UserPresence.
    _channel = client
        .channel('user_presence')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'UserPresence',
          callback: (payload) {
            final newRow = payload.newRecord;
            _upsert(UserLastSeen.fromJson(newRow));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'UserPresence',
          callback: (payload) {
            final newRow = payload.newRecord;
            _upsert(UserLastSeen.fromJson(newRow));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'UserPresence',
          callback: (payload) {
            final oldRow = payload.oldRecord;
            final userId = oldRow['userId'] as String?;
            if (userId != null && mounted) {
              final newMap = Map<String, UserLastSeen>.from(state);
              newMap.remove(userId);
              state = newMap;
            }
          },
        )
        .subscribe();

    debugPrint('📡 LastSeenNotifier: subscribed to UserPresence realtime');
  }

  void _upsert(UserLastSeen p) {
    if (!mounted || p.userId.isEmpty) return;
    final newMap = Map<String, UserLastSeen>.from(state);
    newMap[p.userId] = p;
    state = newMap;
  }

  /// Update the current user's presence. Called by ChatNotifier on
  /// chat screen open (true) and close (false).
  Future<void> updateMyPresence(bool isOnline) async {
    final client = _client;
    final myUserId = client?.auth.currentUser?.id;
    if (client == null || myUserId == null) return;
    try {
      await client.rpc(
        'fn_update_last_seen',
        params: {'p_is_online': isOnline},
      ).timeout(const Duration(seconds: 5));
      // Optimistically update the local cache so the caller's own
      // presence reflects immediately in any UI that's watching.
      _upsert(UserLastSeen(
        userId: myUserId,
        isOnline: isOnline,
        lastSeenAt: isOnline ? null : DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('⚠️ LastSeenNotifier.updateMyPresence error: $e');
    }
  }

  /// Look up a single user's presence. Returns null if the user has
  /// never opened the app since this feature shipped (no UserPresence
  /// row exists yet).
  UserLastSeen? forUser(String userId) => state[userId];

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

/// Global provider for last-seen state. Family-independent (UserPresence
/// is a global per-user table, not per-family).
final lastSeenProvider =
    StateNotifierProvider<LastSeenNotifier, Map<String, UserLastSeen>>((ref) {
  return LastSeenNotifier(ref);
});

/// Convenience provider: a FutureProvider that calls
/// fn_update_last_seen(true) on first build + false on dispose. Used
/// by the Family Profile screen (and other screens that want to mark
/// the user as active even when they're not in a chat).
final markOnlineOnDisposeProvider = FutureProvider.family<void, bool>((ref, isOnline) async {
  ref.onDispose(() async {
    await ref.read(lastSeenProvider.notifier).updateMyPresence(false);
  });
  await ref.read(lastSeenProvider.notifier).updateMyPresence(isOnline);
});
