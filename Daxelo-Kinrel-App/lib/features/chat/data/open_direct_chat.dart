// lib/features/chat/data/open_direct_chat.dart
//
// DAXELO KINREL — C2: Direct Chat → Private 2-Person Group
//
// Helper that calls fn_get_or_create_direct_group to find or create a
// direct group (Family row with groupType='direct') between the caller
// and another user within a shared family, then opens the SAME ChatScreen
// that group chats use — with isDirectChat=true to hide group-only UI.
//
// This replaces all old DM entry points (direct_chat_screen.dart,
// sendGameInviteDm, /dm/:otherUserId route) with a single helper that
// uses the group chat infrastructure.
//
// Dependencies: the C1 migration (20261101120000_dm_rebuild_direct_groups.sql)
// must be applied to the database first — it adds the groupType/directKey
// columns + the fn_get_or_create_direct_group RPC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/supabase_service.dart';
import '../presentation/chat_screen.dart';

/// The result of calling fn_get_or_create_direct_group.
class DirectGroupResult {
  final bool success;
  final String? groupId;
  final String? error;

  DirectGroupResult({required this.success, this.groupId, this.error});

  factory DirectGroupResult.fromJson(Map<String, dynamic> json) {
    return DirectGroupResult(
      success: json['success'] as bool? ?? false,
      groupId: json['groupId'] as String?,
      error: json['error'] as String?,
    );
  }
}

/// Calls fn_get_or_create_direct_group(otherUserId, familyId) via Supabase RPC.
/// Returns the direct group ID or an error.
Future<DirectGroupResult> getOrCreateDirectGroup(
  WidgetRef ref,
  String otherUserId,
  String familyId,
) async {
  try {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      return DirectGroupResult(success: false, error: 'supabase_not_initialized');
    }
    final result = await client.rpc(
      'fn_get_or_create_direct_group',
      params: {
        'p_other_user_id': otherUserId,
        'p_family_id': familyId,
      },
    );
    if (result == null) {
      return DirectGroupResult(success: false, error: 'rpc_returned_null');
    }
    final json = result as Map<String, dynamic>;
    final parsed = DirectGroupResult.fromJson(json);
    if (!parsed.success) {
      debugPrint('⚠️ getOrCreateDirectGroup failed: ${parsed.error}');
    }
    return parsed;
  } catch (e) {
    debugPrint('⚠️ getOrCreateDirectGroup exception: $e');
    return DirectGroupResult(success: false, error: e.toString());
  }
}

/// Opens the direct chat between the current user and [otherUserId] within
/// [familyId]. Calls fn_get_or_create_direct_group to find/create the
/// direct group, then navigates to the ChatScreen with isDirectChat=true.
///
/// Replaces the old /dm/:otherUserId route + DirectChatScreen.
/// The ChatScreen receives:
///   • familyId = the direct group's ID
///   • familyName = the other user's display name (resolved by the screen)
///   • isDirectChat = true (hides group-only UI: group info, members,
///     admin roles, mentions picker, Family chip, sender labels,
///     relationship pills/rails, read-by list, group name/photo editing)
///   • showFamilyNav = false (full-screen, no bottom nav)
///   • hideAppBar = false (the screen renders its own header with the
///     other person's name + relationship subtitle)
Future<void> openDirectChat(
  BuildContext context,
  WidgetRef ref,
  String otherUserId,
  String familyId, {
  String? otherUserName,
  String? otherUserAvatar,
}) async {
  // Show a loading indicator while the RPC resolves.
  // (WhatsApp shows a brief blank chat while loading — we match that.)
  final result = await getOrCreateDirectGroup(ref, otherUserId, familyId);
  if (!result.success || result.groupId == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open chat: ${result.error ?? "unknown error"}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  // Navigate to the ChatScreen with isDirectChat=true.
  // The route is /family/:familyId/chat (the SAME route group chats use)
  // — the ChatScreen detects isDirectChat from the Family row's groupType
  // via the chatProvider, OR we pass it as an explicit parameter.
  if (context.mounted) {
    context.push(
      '/family/${result.groupId}/chat',
      extra: {
        'isDirectChat': true,
        'otherUserId': otherUserId,
        'otherUserName': otherUserName,
        'otherUserAvatar': otherUserAvatar,
      },
    );
  }
}
