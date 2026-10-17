// lib/features/chat/data/chat_block_report_service.dart
//
// DAXELO KINREL — Chat Block & Report Service
//
// Reuses the existing block store (BlockedUser table, RLS already in
// place for self-serve block/unblock) and the existing ContentReport
// table + moderation module (server-side NestJS endpoint
// POST /api/moderation/report → ModerationService.submitReport writes
// the ContentReport row + a ModerationCase). Does NOT create a second
// block store or a parallel moderation flow.
//
// What's new here:
//   • reportChatMessage(messageId, reason, description?) → POSTs to
//     /api/moderation/report with targetType='chat_message'. The unique
//     constraint on ContentReport(reporterId, targetType, targetId)
//     (added by migration 20261017120000) makes a duplicate report a
//     23505 unique_violation, surfaced as a "you already reported this"
//     success (not an error) by the NestJS handler.
//   • blockUser(userId) → direct INSERT into BlockedUser (RLS allows
//     blockerId = auth.uid()). Mirrors the existing NestJS DELETE
//     /api/users/me/blocked/:userId (unblock) pattern, but for the
//     block direction. Reuses the existing BlockedUser row shape:
//     no second store.
//   • unblockUser(userId) → direct DELETE from BlockedUser. Mirrors
//     the existing NestJS DELETE /api/users/me/blocked/:userId, but
//     calls Supabase directly so we don't need a round-trip to the
//     NestJS backend.
//   • isBlockedByMe(userId) + amIBlockedBy(userId) → cached lookups
//     for the chat UI to decide whether to render the compose box,
//     hide the blocked person's messages, etc.
//   • fetchBlockedUserIds() → the full block list for the current
//     viewer (used by the inbox unread-count filter + the group chat
//     placeholder rendering).
//
// Server-side enforcement (the "they cannot send to me / I cannot send
// to them in direct chats" contract) is implemented at the DB layer by
// the migration's RESTRICTIVE RLS policy on ChatMessage INSERT — NOT
// here. The client-side block UI is the user-facing affordance; the
// server-side policy is the enforcement.
//
// Privacy: this service NEVER exposes who reported whom to other family
// members. The ContentReport table's RLS only allows the reporter to
// SELECT their own rows; the moderation queue is admin-only.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';

/// The supported reasons for reporting a chat message. Mirrors the
/// values the moderation module's classifier + priority mapper already
/// understands (server/src/modules/moderation/moderation.service.ts).
enum ChatReportReason {
  spam,
  harassment,
  inappropriateContent,
  other,
}

extension ChatReportReasonX on ChatReportReason {
  /// Wire value — sent as `reason` to /api/moderation/report and stored
  /// on the ContentReport row. Matches the moderation module's
  /// `mapReportReasonToPriority` recognized values for spam + the
  /// free-form 'other' bucket. 'harassment' and 'inappropriate_content'
  /// are routed to 'urgent'/'normal' priority by the fallback path
  /// (not in the urgent/critical list, so they get 'normal').
  String get wireValue {
    switch (this) {
      case ChatReportReason.spam:
        return 'spam';
      case ChatReportReason.harassment:
        return 'harassment';
      case ChatReportReason.inappropriateContent:
        return 'inappropriate_content';
      case ChatReportReason.other:
        return 'other';
    }
  }

  /// L10n key stem (the per-reason label is at
  /// `chat.reportReason.<stem>` in the .arb files).
  String get l10nStem {
    switch (this) {
      case ChatReportReason.spam:
        return 'spam';
      case ChatReportReason.harassment:
        return 'harassment';
      case ChatReportReason.inappropriateContent:
        return 'inappropriateContent';
      case ChatReportReason.other:
        return 'other';
    }
  }
}

/// Result of a report submission. The client distinguishes "newly filed"
/// from "already reported" so the UI can show the right confirmation
/// ("Report submitted" vs "You already reported this message").
enum ChatReportResult { newlyFiled, alreadyReported, error }

/// Result of a block / unblock operation.
enum ChatBlockResult { ok, error }

class ChatBlockReportService {
  ChatBlockReportService(this._ref);
  final Ref _ref;

  /// Dio HTTP client configured with the NestJS base URL + auth JWT.
  /// Mirrors the pattern in
  /// lib/features/profile/data/profile_provider.dart (loadBlockedUsers,
  /// unblockUser).
  Dio get _dio => _ref.read(dioProvider);

  /// Report a chat message. Writes a ContentReport row via the existing
  /// /api/moderation/report endpoint (which the moderation module's
  /// submitReport handler backs — see
  /// server/src/modules/moderation/moderation.service.ts). The unique
  /// constraint on ContentReport(reporterId, targetType, targetId)
  /// means a duplicate report from the same user for the same message
  /// surfaces as a 23505 unique_violation — caught by the NestJS handler
  /// and returned as `result: 'already_reported'`.
  ///
  /// Returns [ChatReportResult.newlyFiled] on success,
  /// [ChatReportResult.alreadyReported] if the user has already filed
  /// a report for this message, [ChatReportResult.error] otherwise.
  Future<ChatReportResult> reportChatMessage({
    required String messageId,
    required ChatReportReason reason,
    String? description,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return ChatReportResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return ChatReportResult.error;

      // POST /api/moderation/report with the auth JWT injected by the
      // Dio _AuthInterceptor (mirrors the existing pattern in
      // profile_provider.dart). The NestJS handler writes the
      // ContentReport row AND creates a ModerationCase for the
      // moderation queue (admin-side flow).
      //
      // 23505 (unique_violation) on the ContentReport insert is caught
      // by the NestJS handler and returned as 200 with
      // `{result: 'already_reported'}`. We also defensively catch a
      // raw 23505 here in case the handler doesn't catch it.
      final response = await _dio.post(
        '/api/moderation/report',
        data: {
          'targetType': 'chat_message',
          'targetId': messageId,
          'reason': reason.wireValue,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final result = data['result'];
        if (result == 'already_reported') {
          return ChatReportResult.alreadyReported;
        }
        if (result == 'ok' || data['id'] != null) {
          return ChatReportResult.newlyFiled;
        }
      }
      // Fallback: assume newly-filed if we got a 2xx response without
      // a recognizable result field (the NestJS handler returns the
      // ContentReport row on success, which has an `id`).
      return ChatReportResult.newlyFiled;
    } on DioException catch (e) {
      // The NestJS moderation endpoint catches Postgres 23505 and
      // returns 200 with `result: 'already_reported'`. If it ever
      // surfaces the raw 23505 as a 4xx/5xx, the response body carries
      // a `code: '23505'` field (per the NestJS error envelope).
      final code = e.response?.data is Map
          ? (e.response?.data as Map)['code']
          : null;
      if (code == '23505' || e.response?.statusCode == 409) {
        return ChatReportResult.alreadyReported;
      }
      debugPrint('⚠️ ChatBlockReportService.reportChatMessage DioException: ${e.message}');
      return ChatReportResult.error;
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — defensive catch in case the call
      // goes directly to Supabase (e.g. if the Edge Function path is
      // used in the future).
      if (e.code == '23505') {
        return ChatReportResult.alreadyReported;
      }
      debugPrint('⚠️ ChatBlockReportService.reportChatMessage PostgrestException: $e');
      return ChatReportResult.error;
    } catch (e) {
      debugPrint('⚠️ ChatBlockReportService.reportChatMessage: $e');
      return ChatReportResult.error;
    }
  }

  /// Block a user. INSERTs a row into BlockedUser (RLS allows
  /// blockerId = auth.uid()). The existing unblock flow
  /// (lib/features/profile/presentation/blocked_users_screen.dart) and
  /// the existing NestJS GET /api/users/me/blocked (list) will
  /// automatically surface this row — there's no second store.
  Future<ChatBlockResult> blockUser(String blockedUserId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return ChatBlockResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return ChatBlockResult.error;
      if (blockedUserId.isEmpty || blockedUserId == myUserId) {
        return ChatBlockResult.error;
      }

      // Direct INSERT into BlockedUser. RLS policy
      // "Users can block others" (created by
      // 20260608182557_fix_rls_tables_with_missing_policies.sql) allows
      // blockerId = auth.uid(). The unique (blockerId, blockedId)
      // constraint makes a re-block idempotent (ON CONFLICT DO NOTHING).
      await client.from('BlockedUser').upsert(
        {
          'id': 'bu_${myUserId}_$blockedUserId',
          'blockerId': myUserId,
          'blockedId': blockedUserId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'blockerId, blockedId',
      );
      return ChatBlockResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatBlockReportService.blockUser: $e');
      return ChatBlockResult.error;
    }
  }

  /// Unblock a user. DELETEs the BlockedUser row. RLS policy
  /// "Users can unblock others" (blockerId = auth.uid()) allows this.
  /// The existing blocked_users_screen.dart uses the NestJS DELETE
  /// /api/users/me/blocked/:userId endpoint — this method hits Supabase
  /// directly so chat can unblock without a round-trip to NestJS. Both
  /// paths target the same row.
  Future<ChatBlockResult> unblockUser(String blockedUserId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return ChatBlockResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return ChatBlockResult.error;

      await client
          .from('BlockedUser')
          .delete()
          .eq('blockerId', myUserId)
          .eq('blockedId', blockedUserId);
      return ChatBlockResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatBlockReportService.unblockUser: $e');
      return ChatBlockResult.error;
    }
  }

  /// Fetch the current viewer's blocked user IDs. Used by:
  ///   • The inbox unread-count filter (don't count messages from
  ///     blocked senders).
  ///   • The group chat message-bubble placeholder renderer (hide the
  ///     blocked person's messages behind "Message from a blocked user").
  ///   • The direct-chat compose box (hide input if the other party is
  ///     blocked).
  ///
  /// Returns an empty list on error or no session — never throws.
  Future<Set<String>> fetchBlockedUserIds() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return const {};
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return const {};

      // RLS policy "Users can view own blocked users" allows
      // blockerId = auth.uid(). The SELECT is scoped to my own rows.
      final response = await client
          .from('BlockedUser')
          .select('blockedId')
          .eq('blockerId', myUserId);
      final rows = response as List<dynamic>? ?? const [];
      return rows
          .map((r) => (r as Map<String, dynamic>?)?['blockedId'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('⚠️ ChatBlockReportService.fetchBlockedUserIds: $e');
      return const {};
    }
  }

  /// Has the current viewer blocked this user? (Outbound direction.)
  /// Useful when entering a direct chat with [otherUserId] — the chat
  /// UI uses this to decide whether to render the "You blocked this
  /// person" banner + hide the compose box.
  Future<bool> isBlockedByMe(String otherUserId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return false;

      final response = await client
          .from('BlockedUser')
          .select('id')
          .eq('blockerId', myUserId)
          .eq('blockedId', otherUserId)
          .limit(1)
          .maybeSingle();
      return response != null;
    } catch (e) {
      debugPrint('⚠️ ChatBlockReportService.isBlockedByMe: $e');
      return false;
    }
  }
}

/// Riverpod provider. Use `ref.read(chatBlockReportServiceProvider)` from
/// the chat screen / sheet / placeholder widgets.
final chatBlockReportServiceProvider =
    Provider<ChatBlockReportService>((ref) => ChatBlockReportService(ref));
