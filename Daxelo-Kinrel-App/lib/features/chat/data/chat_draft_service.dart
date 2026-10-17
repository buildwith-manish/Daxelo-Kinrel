// lib/features/chat/data/chat_draft_service.dart
//
// DAXELO KINREL — Chat Draft Service (local-only)
//
// Saves typed text per conversation (family chat or direct chat) after
// ~500ms of no typing, restores on return, clears on send/empty.
// Drafts survive app restarts (SharedPreferences-backed). Drafts are
// LOCAL to the device in this version — they are NOT synced to the
// server (per the spec: "Drafts are local to the device in this
// version. Do not sync them to the server.").
//
// Storage layout:
//   SharedPreferences key: 'chat_draft.<familyId>'
//   SharedPreferences key (direct): 'chat_draft.dm.<otherUserId>'
//   Value: JSON { 'text': String, 'replyToId': String?,
//                 'replyToContent': String?, 'replyToSenderName': String?,
//                 'updatedAt': ISO8601 }
//
// The key uses the SAME familyId scoping convention as the existing
// ChatWallpaperProvider / ChatLockService (so drafts for the same
// family chat are stable across chat screen re-opens, even when the
// user navigates away and back).
//
// Direct chats use a separate key prefix 'dm.' keyed on the other
// user's id — matches the dm_-keyed wallpaper/lock convention used
// elsewhere (see chat_screen.dart's _chatSettingsKey getter).
//
// The service is intentionally a thin SharedPreferences wrapper — no
// Drift, no Isar, no Riverpod state. The chat screen debounces the
// save (500ms after the last keystroke) and reads the draft on
// initState. This mirrors message_queue_service.dart's pattern.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/chat_provider.dart' show ChatMessage;

/// A persisted draft — the typed text + the reply-to target (if any).
/// Both are saved atomically (single SharedPreferences write) so a
/// mid-typed reply-to selection doesn't leave a half-saved draft.
class ChatDraft {
  const ChatDraft({
    required this.text,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    required this.updatedAt,
  });

  factory ChatDraft.fromJson(Map<String, dynamic> json) => ChatDraft(
        text: json['text'] as String? ?? '',
        replyToId: json['replyToId'] as String?,
        replyToContent: json['replyToContent'] as String?,
        replyToSenderName: json['replyToSenderName'] as String?,
        updatedAt: json['updatedAt'] is String
            ? DateTime.tryParse(json['updatedAt'] as String) ??
                DateTime.now()
            : DateTime.now(),
      );

  final String text;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final DateTime updatedAt;

  bool get isEmpty =>
      text.trim().isEmpty && replyToId == null && replyToContent == null;

  Map<String, dynamic> toJson() => {
        'text': text,
        'replyToId': replyToId,
        'replyToContent': replyToContent,
        'replyToSenderName': replyToSenderName,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Thin SharedPreferences wrapper for per-conversation chat drafts.
///
/// Methods never throw — a SharedPreferences failure degrades to a
/// no-op (draft not saved / not restored) and a debugPrint, never to
/// a chat-screen crash.
class ChatDraftService {
  static const String _familyKeyPrefix = 'chat_draft.';
  static const String _dmKeyPrefix = 'chat_draft.dm.';

  String _key(String familyId, {String? directOtherUserId}) {
    if (directOtherUserId != null && directOtherUserId.isNotEmpty) {
      return '$_dmKeyPrefix$directOtherUserId';
    }
    return '$_familyKeyPrefix$familyId';
  }

  Future<ChatDraft?> loadDraft(
    String familyId, {
    String? directOtherUserId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(familyId, directOtherUserId: directOtherUserId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final draft = ChatDraft.fromJson(decoded);
      return draft.isEmpty ? null : draft;
    } catch (e) {
      debugPrint('⚠️ ChatDraftService.loadDraft: $e');
      return null;
    }
  }

  Future<void> saveDraft(
    String familyId, {
    String? directOtherUserId,
    required String text,
    ChatMessage? replyTo,
  }) async {
    try {
      final draft = ChatDraft(
        text: text,
        replyToId: replyTo?.id,
        replyToContent: replyTo?.content,
        replyToSenderName: replyTo?.senderName,
        updatedAt: DateTime.now(),
      );
      // Skip the write entirely if the draft is empty AND there's no
      // existing draft to clear — avoids touching SharedPreferences
      // on every keystroke when the field is already empty.
      final prefs = await SharedPreferences.getInstance();
      final key = _key(familyId, directOtherUserId: directOtherUserId);
      if (draft.isEmpty) {
        // Empty draft: clear any existing stored draft.
        await prefs.remove(key);
        return;
      }
      await prefs.setString(key, jsonEncode(draft.toJson()));
    } catch (e) {
      debugPrint('⚠️ ChatDraftService.saveDraft: $e');
    }
  }

  Future<void> clearDraft(
    String familyId, {
    String? directOtherUserId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(familyId, directOtherUserId: directOtherUserId));
    } catch (e) {
      debugPrint('⚠️ ChatDraftService.clearDraft: $e');
    }
  }
}

/// Riverpod provider. Use `ref.read(chatDraftServiceProvider)` from
/// the chat screen (one-shot reads) — drafts are not Riverpod state.
/// The chat screen manages its own debounce timer.
final chatDraftServiceProvider = Provider<ChatDraftService>((ref) {
  return ChatDraftService();
});
