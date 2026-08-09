// lib/features/chat/data/chat_enhancement_service.dart
//
// DAXELO KINREL — Chat Enhancement Service
//
// Calls all the chat enhancement RPCs (reactions, read receipts, delete,
// edit, typing, star, pin) via Supabase.
//

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class ChatEnhancementService {
  ChatEnhancementService(this._ref);
  final Ref _ref;

  /// Delete a message for the current user only (other users still see it).
  Future<bool> deleteForMe(String messageId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_delete_message_for_me', params: {'p_message_id': messageId});
      return true;
    } catch (e) {
      debugPrint('⚠️ deleteForMe: $e');
      return false;
    }
  }

  /// Delete a message for everyone (sender or admin only).
  Future<bool> deleteForEveryone(String messageId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_delete_message_for_everyone', params: {'p_message_id': messageId});
      return true;
    } catch (e) {
      debugPrint('⚠️ deleteForEveryone: $e');
      return false;
    }
  }

  /// Edit a message (sender only).
  Future<bool> editMessage(String messageId, String newContent) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_edit_message', params: {
        'p_message_id': messageId,
        'p_new_content': newContent,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ editMessage: $e');
      return false;
    }
  }

  /// Mark all messages in a family chat as read by the current user.
  Future<void> markMessagesAsRead(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;
      await client.rpc('fn_mark_messages_read', params: {'p_family_id': familyId});
    } catch (e) {
      debugPrint('⚠️ markMessagesAsRead: $e');
    }
  }

  /// Toggle an emoji reaction on a message.
  Future<bool> toggleReaction(String messageId, String emoji) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_toggle_reaction', params: {
        'p_message_id': messageId,
        'p_emoji': emoji,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ toggleReaction: $e');
      return false;
    }
  }

  /// Set typing status for the current user in a family chat.
  Future<void> setTypingStatus(String familyId, bool isTyping) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;
      await client.rpc('fn_set_typing_status', params: {
        'p_family_id': familyId,
        'p_is_typing': isTyping,
      });
    } catch (e) {
      // Silent — typing status is best-effort
    }
  }

  /// Star or unstar a message.
  Future<bool> starMessage(String messageId, bool starred) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_star_message', params: {
        'p_message_id': messageId,
        'p_starred': starred,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ starMessage: $e');
      return false;
    }
  }

  /// Pin or unpin a message (admin/creator only).
  Future<bool> pinMessage(String messageId, bool pinned) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      await client.rpc('fn_pin_message', params: {
        'p_message_id': messageId,
        'p_pinned': pinned,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ pinMessage: $e');
      return false;
    }
  }

  /// Fetch reactions for a message.
  Future<List<Map<String, dynamic>>> getReactions(String messageId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];
      final response = await client
          .from('ChatReaction')
          .select('userId, emoji, createdAt')
          .eq('messageId', messageId);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Fetch typing status for a family chat (excluding current user).
  Future<List<Map<String, dynamic>>> getTypingUsers(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];
      final userId = client.auth.currentUser?.id;
      final response = await client
          .from('ChatTypingStatus')
          .select('userId, isTyping, updatedAt')
          .eq('familyId', familyId)
          .eq('isTyping', true)
          .neq('userId', userId ?? '');
      // Filter: only show typing within last 5 seconds
      final now = DateTime.now();
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .where((e) {
            final updatedAt = DateTime.tryParse(e['updatedAt']?.toString() ?? '');
            return updatedAt != null && now.difference(updatedAt).inSeconds < 5;
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get unread message count for a family chat.
  Future<int> getUnreadCount(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return 0;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return 0;

      // Count messages not sent by this user that don't have a read receipt
      final response = await client
          .from('ChatMessage')
          .select('id')
          .eq('familyId', familyId)
          .neq('senderId', userId)
          .eq('isDeletedForEveryone', false);

      final allMessageIds = (response as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();

      if (allMessageIds.isEmpty) return 0;

      // Get read receipt message IDs
      final readResponse = await client
          .from('ChatReadReceipt')
          .select('messageId')
          .eq('userId', userId)
          .inFilter('messageId', allMessageIds);

      final readIds = (readResponse as List)
          .map((e) => (e as Map<String, dynamic>)['messageId'] as String)
          .toSet();

      return allMessageIds.where((id) => !readIds.contains(id)).length;
    } catch (e) {
      return 0;
    }
  }

  /// Save chat settings (wallpaper, mute, pin, archive).
  Future<void> saveChatSettings({
    required String familyId,
    String? wallpaperUrl,
    String? wallpaperColor,
    bool? isMuted,
    bool? isPinned,
    bool? isArchived,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final id = 'cs_${userId}_$familyId';
      final data = <String, dynamic>{
        'id': id,
        'userId': userId,
        'familyId': familyId,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (wallpaperUrl != null) data['wallpaperUrl'] = wallpaperUrl;
      if (wallpaperColor != null) data['wallpaperColor'] = wallpaperColor;
      if (isMuted != null) data['isMuted'] = isMuted;
      if (isPinned != null) data['isPinned'] = isPinned;
      if (isArchived != null) data['isArchived'] = isArchived;

      await client.from('ChatSettings').upsert(data, onConflict: 'userId, familyId');
    } catch (e) {
      debugPrint('⚠️ saveChatSettings: $e');
    }
  }

  /// Get chat settings for the current user + family.
  Future<Map<String, dynamic>?> getChatSettings(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return null;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await client
          .from('ChatSettings')
          .select()
          .eq('userId', userId)
          .eq('familyId', familyId)
          .maybeSingle();

      return response as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }
}

final chatEnhancementServiceProvider = Provider<ChatEnhancementService>((ref) {
  return ChatEnhancementService(ref);
});
