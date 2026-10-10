// lib/features/chat/data/saved_messages_provider.dart
//
// DAXELO KINREL — Tier 1 Feature 1.1: Saved Messages — Provider
//
// Calls the NestJS endpoint exposed by SavedMessagesController:
//   • GET /chat/saved-messages — returns the user's self-DM preview
//
// The actual DM-with-self persistence goes through the existing
// DirectMessage table (RLS permits senderId = receiverId = auth.uid()).
// This provider just fetches the preview row that the inbox renders at
// the top of the DM section.
//
// Used by:
//   - chat_inbox_screen.dart (renders the Saved Messages row above DMs)
//   - direct_chat_screen.dart (when otherUserId == currentUserId, the
//     header shows "Saved Messages" + a bookmark icon)

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/dio_client.dart';

/// Snapshot of the user's self-DM inbox row.
@immutable
class SavedMessagesPreview {
  const SavedMessagesPreview({
    required this.hasSavedMessages,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.otherUserUsername,
    this.lastMessageContent,
    this.lastMessageCreatedAt,
    this.lastMessageType,
    required this.unreadCount,
  });

  factory SavedMessagesPreview.fromJson(Map<String, dynamic> json) {
    return SavedMessagesPreview(
      hasSavedMessages: json['hasSavedMessages'] as bool? ?? false,
      otherUserId: json['otherUserId'] as String? ?? '',
      otherUserName: json['otherUserName'] as String? ?? 'Saved Messages',
      otherUserAvatar: json['otherUserAvatar'] as String?,
      otherUserUsername: json['otherUserUsername'] as String?,
      lastMessageContent: json['lastMessageContent'] as String?,
      lastMessageCreatedAt: json['lastMessageCreatedAt'] as String?,
      lastMessageType: json['lastMessageType'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  final bool hasSavedMessages;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String? otherUserUsername;
  final String? lastMessageContent;
  final String? lastMessageCreatedAt;
  final String? lastMessageType;
  final int unreadCount;

  /// Always true for self-DMs (used by the inbox to render the bookmark
  /// icon + a "Saved" label rather than the user's avatar).
  bool get isSelf => true;
}

class SavedMessagesNotifier extends StateNotifier<SavedMessagesPreview?> {
  SavedMessagesNotifier(this._dio) : super(null);

  final Dio _dio;

  /// Refresh the Saved Messages preview. Called by the inbox on each
  /// pull-to-refresh + whenever a new DM-to-self is detected.
  Future<void> refresh() async {
    try {
      final response = await _dio.get('/chat/saved-messages');
      final data = response.data as Map<String, dynamic>?;
      if (data != null && (data['success'] as bool? ?? false)) {
        state = SavedMessagesPreview.fromJson(data);
      } else {
        // No saved messages yet — render an empty placeholder row so
        // the inbox still shows the "Saved Messages" entry (matches
        // WhatsApp: the row is always there even if empty).
        state = SavedMessagesPreview(
          hasSavedMessages: false,
          otherUserId: '',
          otherUserName: 'Saved Messages',
          unreadCount: 0,
        );
      }
    } catch (e) {
      // Non-fatal: the inbox still shows the placeholder.
      if (kDebugMode) {
        debugPrint('SavedMessagesPreview load failed: $e');
      }
      state = SavedMessagesPreview(
        hasSavedMessages: false,
        otherUserId: '',
        otherUserName: 'Saved Messages',
        unreadCount: 0,
      );
    }
  }
}

final savedMessagesProvider =
    StateNotifierProvider<SavedMessagesNotifier, SavedMessagesPreview?>(
  (ref) => SavedMessagesNotifier(ref.read(dioProvider)),
);
