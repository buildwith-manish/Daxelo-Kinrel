// lib/features/chat/data/drafts_provider.dart
//
// DAXELO KINREL — Tier 1 Feature 1.3: Auto-saved Drafts — Provider
//
// Calls the NestJS endpoints exposed by DraftsController:
//   • POST /chat/drafts             — upsert or clear
//   • GET  /chat/drafts?familyId=X  — load for family chat
//   • GET  /chat/drafts?receiverId=X — load for DM
//   • GET  /chat/drafts/list        — list all (used on app startup)
//
// Multi-device sync: the ChatDraft table is in the supabase_realtime
// publication, so the user's other devices see draft updates live via
// Supabase Realtime. This provider ALSO listens to the realtime stream
// and refreshes its local cache when a remote update arrives.
//
// Used by:
//   - chat_screen.dart (debounce-write the controller text 800ms after
//     the last keystroke; restore on screen open; clear on send).
//   - direct_chat_screen.dart (same pattern for DMs).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/dio_client.dart';

/// One draft row. Targets EITHER familyId (group) OR receiverId (DM).
@immutable
class ChatDraft {
  const ChatDraft({
    required this.id,
    required this.userId,
    this.familyId,
    this.receiverId,
    required this.draftText,
    this.replyToId,
    required this.updatedAt,
  });

  factory ChatDraft.fromJson(Map<String, dynamic> json) {
    return ChatDraft(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      familyId: json['familyId'] as String?,
      receiverId: json['receiverId'] as String?,
      draftText: json['draftText'] as String? ?? '',
      replyToId: json['replyToId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String userId;
  final String? familyId;
  final String? receiverId;
  final String draftText;
  final String? replyToId;
  final DateTime updatedAt;

  /// Whether this draft is for a family group chat (vs a DM).
  bool get isFamilyDraft => familyId != null && receiverId == null;
}

/// State shape exposed by DraftsProvider.
class DraftsState {
  const DraftsState({
    this.drafts = const {},
    this.error,
  });

  /// Keyed by "family:<id>" for family drafts and "dm:<userId>" for DMs.
  /// The composer reads from this map + writes to it locally so typing
  /// feels instant (the server write is debounced 800ms behind).
  final Map<String, String> drafts;
  final String? error;

  DraftsState copyWith({
    Map<String, String>? drafts,
    String? error,
  }) {
    return DraftsState(
      drafts: drafts ?? this.drafts,
      error: error,
    );
  }

  /// Read the draft text for a specific chat (or empty string).
  String textFor({String? familyId, String? receiverId}) {
    final key = _keyFor(familyId: familyId, receiverId: receiverId);
    return drafts[key] ?? '';
  }

  static String _keyFor({String? familyId, String? receiverId}) {
    if (familyId != null) return 'family:$familyId';
    if (receiverId != null) return 'dm:$receiverId';
    return '';
  }
}

class DraftsNotifier extends StateNotifier<DraftsState> {
  DraftsNotifier(this._dio) : super(const DraftsState()) {
    _initRealtime();
  }

  final Dio _dio;
  StreamSubscription? _realtimeSub;
  Timer? _debounceTimer;

  /// Initialize the Supabase Realtime listener so draft updates from
  /// other devices (or other chats on this device) reflect in real-time.
  /// The realtime payload is a ChatDraft row; we update the local cache.
  void _initRealtime() {
    try {
      final channel = Supabase.instance.client.channel('chat-drafts-realtime');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'ChatDraft',
        callback: (payload) {
          final row = payload.newRecord;
          if (row == null) return;
          final userId = row['userId'] as String?;
          if (userId == null) return;
          // The RLS policy on ChatDraft only lets the owner SELECT,
          // so any row we receive is necessarily ours.
          final familyId = row['familyId'] as String?;
          final receiverId = row['receiverId'] as String?;
          final text = row['draftText'] as String? ?? '';
          final key = (familyId != null)
              ? 'family:$familyId'
              : (receiverId != null ? 'dm:$receiverId' : '');
          if (key.isEmpty) return;
          final newMap = Map<String, String>.from(state.drafts);
          if (text.isEmpty) {
            newMap.remove(key);
          } else {
            newMap[key] = text;
          }
          state = state.copyWith(drafts: newMap);
        },
      );
      channel.subscribe();
    } catch (e) {
      // Non-fatal: we'll fall back to per-screen HTTP refreshes.
      if (kDebugMode) {
        debugPrint('Drafts realtime init failed: $e');
      }
    }
  }

  /// On startup, load all the user's drafts. Called once on app boot
  /// by the chat inbox screen.
  Future<void> loadAll() async {
    try {
      final response = await _dio.dio.get('/chat/drafts/list');
      final list = (response.data as List<dynamic>?)
              ?.map((e) => ChatDraft.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      final map = <String, String>{};
      for (final d in list) {
        final key = d.isFamilyDraft
            ? 'family:${d.familyId}'
            : 'dm:${d.receiverId}';
        if (d.draftText.isNotEmpty) map[key] = d.draftText;
      }
      state = state.copyWith(drafts: map);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load drafts: $e');
    }
  }

  /// Update the local cache immediately (instant UI) + debounce-write
  /// to the server 800ms later (so we don't spam the API on every
  /// keystroke). Empty text clears.
  void updateLocal({
    String? familyId,
    String? receiverId,
    required String text,
  }) {
    final key = _keyFor(familyId: familyId, receiverId: receiverId);
    if (key.isEmpty) return;
    final newMap = Map<String, String>.from(state.drafts);
    if (text.isEmpty) {
      newMap.remove(key);
    } else {
      newMap[key] = text;
    }
    state = state.copyWith(drafts: newMap);

    // Debounce the server write.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _persist(familyId: familyId, receiverId: receiverId, text: text);
    });
  }

  Future<void> _persist({
    String? familyId,
    String? receiverId,
    required String text,
  }) async {
    try {
      await _dio.dio.post('/chat/drafts', data: {
        if (familyId != null) 'familyId': familyId,
        if (receiverId != null) 'receiverId': receiverId,
        'draftText': text,
      });
    } catch (e) {
      // Non-fatal: the local cache still has the draft; we'll retry on
      // the next debounce tick. Log for debug builds.
      if (kDebugMode) {
        debugPrint('Draft persist failed: $e');
      }
    }
  }

  /// Load the draft for a single chat (used by chat_screen on open).
  Future<void> load({String? familyId, String? receiverId}) async {
    try {
      final response = await _dio.dio.get('/chat/drafts', queryParameters: {
        if (familyId != null) 'familyId': familyId,
        if (receiverId != null) 'receiverId': receiverId,
      });
      final data = response.data as Map<String, dynamic>?;
      final hasDraft = data?['hasDraft'] as bool? ?? false;
      final text = data?['draftText'] as String? ?? '';
      final key = _keyFor(familyId: familyId, receiverId: receiverId);
      final newMap = Map<String, String>.from(state.drafts);
      if (hasDraft && text.isNotEmpty) {
        newMap[key] = text;
      } else {
        newMap.remove(key);
      }
      state = state.copyWith(drafts: newMap);
    } catch (e) {
      // Non-fatal — local cache is the source of truth for the UI.
      if (kDebugMode) {
        debugPrint('Draft load failed: $e');
      }
    }
  }

  /// Clear the draft for a chat (called after a successful send).
  Future<void> clear({String? familyId, String? receiverId}) async {
    // Local clear is instant.
    final key = _keyFor(familyId: familyId, receiverId: receiverId);
    final newMap = Map<String, String>.from(state.drafts);
    newMap.remove(key);
    state = state.copyWith(drafts: newMap);
    // Cancel any pending debounce write so we don't re-create the
    // just-cleared draft.
    _debounceTimer?.cancel();
    // Server clear (empty text = delete).
    await _persist(familyId: familyId, receiverId: receiverId, text: '');
  }

  static String _keyFor({String? familyId, String? receiverId}) {
    if (familyId != null) return 'family:$familyId';
    if (receiverId != null) return 'dm:$receiverId';
    return '';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}

final draftsProvider = StateNotifierProvider<DraftsNotifier, DraftsState>(
  (ref) => DraftsNotifier(ref.read(dioProvider)),
);
