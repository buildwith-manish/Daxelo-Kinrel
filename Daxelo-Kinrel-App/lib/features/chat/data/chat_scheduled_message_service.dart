// lib/features/chat/data/chat_scheduled_message_service.dart
//
// DAXELO KINREL — Scheduled Chat Message Service (client)
//
// CRUD for the ChatScheduledMessage table (added by migration
// 20261018120000_chat_scheduled_messages.sql). Reuses the existing
// supabaseProvider + Dio auth interceptor pattern. No new packages.
//
// The dispatch itself runs server-side via pg_cron + the
// fn_dispatch_scheduled_chat_messages() SQL function — the client
// just queues + lists + cancels + retries.
//
// Privacy: the table's RLS is author-only (only the author can
// SELECT/INSERT/UPDATE/DELETE their own rows). No other family
// member can see who scheduled what.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

/// Status of a scheduled message row. Mirrors the DB column.
enum ScheduledMessageStatus { pending, sent, cancelled, failed }

ScheduledMessageStatus _parseStatus(String? s) {
  switch (s) {
    case 'sent':
      return ScheduledMessageStatus.sent;
    case 'cancelled':
      return ScheduledMessageStatus.cancelled;
    case 'failed':
      return ScheduledMessageStatus.failed;
    case 'pending':
    default:
      return ScheduledMessageStatus.pending;
  }
}

/// A scheduled chat message row. Mirrors the ChatScheduledMessage table
/// columns; the wire shape comes from Supabase's Postgrest JSON.
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.familyId,
    this.groupId,
    required this.authorId,
    required this.content,
    required this.messageType,
    this.replyToId,
    required this.sendAt,
    required this.status,
    this.sentMessageId,
    this.failureReason,
    required this.createdAt,
    this.sentAt,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) {
    return ScheduledMessage(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      groupId: json['groupId'] as String?,
      authorId: json['authorId'] as String? ?? '',
      content: json['content'] as String? ?? '',
      messageType: json['messageType'] as String? ?? 'text',
      replyToId: json['replyToId'] as String?,
      sendAt:
          DateTime.tryParse(json['sendAt'] as String? ?? '') ?? DateTime.now(),
      status: _parseStatus(json['status'] as String?),
      sentMessageId: json['sentMessageId'] as String?,
      failureReason: json['failureReason'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      sentAt: json['sentAt'] == null
          ? null
          : DateTime.tryParse(json['sentAt'] as String),
    );
  }

  final String id;
  final String familyId;
  final String? groupId;
  final String authorId;
  final String content;
  final String messageType;
  final String? replyToId;
  final DateTime sendAt;
  final ScheduledMessageStatus status;
  final String? sentMessageId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? sentAt;

  /// True if the user can still cancel/edit. Once 'sent' or 'cancelled'
  /// the row is immutable (except by the dispatch function itself).
  bool get isMutable =>
      status == ScheduledMessageStatus.pending ||
      status == ScheduledMessageStatus.failed;

  /// True if the sendAt is in the past (server-side validation also
  /// rejects this; this is the client-side mirror for the schedule
  /// sheet's pre-flight check).
  bool get isPastTime =>
      sendAt.isBefore(DateTime.now()) &&
      status == ScheduledMessageStatus.pending;

  Map<String, dynamic> toJson({required String authorId}) => {
        'id': id,
        'familyId': familyId,
        'groupId': groupId,
        'authorId': authorId,
        'content': content,
        'messageType': messageType,
        'replyToId': replyToId,
        'sendAt': sendAt.toUtc().toIso8601String(),
        'status': status.name,
        'sentMessageId': sentMessageId,
        'failureReason': failureReason,
      };
}

/// Result of a schedule attempt.
enum ScheduleResult {
  ok,
  pastTimeRejected,
  notSignedIn,
  error,
}

/// Result of a cancel / retry attempt.
enum CancelResult { ok, error }

class ChatScheduledMessageService {
  ChatScheduledMessageService(this._ref);
  final Ref _ref;

  /// Schedule a new message. Returns the created row id on success.
  /// `sendAt` MUST be in the future — past times are rejected with
  /// [ScheduleResult.pastTimeRejected] (the server also rejects via
  /// a CHECK constraint, so this is the client-side mirror).
  Future<ScheduleResult> schedule({
    required String familyId,
    String? groupId,
    required String content,
    String? replyToId,
    required DateTime sendAt,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return ScheduleResult.notSignedIn;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return ScheduleResult.notSignedIn;

      final trimmed = content.trim();
      if (trimmed.isEmpty) return ScheduleResult.error;

      // Reject past times — store UTC, compare against now().
      final now = DateTime.now();
      if (!sendAt.isAfter(now.add(const Duration(seconds: 30)))) {
        // Allow a 30-second fudge so a "send in 30 seconds" debug test
        // doesn't get rejected. Real scheduled messages are minutes+
        // in the future, so this is fine.
        return ScheduleResult.pastTimeRejected;
      }

      await client.from('ChatScheduledMessage').insert({
        'familyId': familyId,
        'groupId': groupId,
        'authorId': myUserId,
        'content': trimmed,
        'messageType': 'text', // v1: text-only
        'replyToId': replyToId,
        'sendAt': sendAt.toUtc().toIso8601String(),
        'status': 'pending',
      });
      return ScheduleResult.ok;
    } on PostgrestException catch (e) {
      // 23514 = check_violation (the sendAt > now() CHECK constraint
      // the migration adds; if the user is on a device with a skewed
      // clock, the server-side CHECK rejects with 23514). Surface as
      // pastTimeRejected.
      if (e.code == '23514') {
        return ScheduleResult.pastTimeRejected;
      }
      debugPrint('⚠️ ChatScheduledMessageService.schedule PostgrestException: $e');
      return ScheduleResult.error;
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.schedule: $e');
      return ScheduleResult.error;
    }
  }

  /// List pending + failed scheduled messages for the given
  /// conversation (familyId + optional groupId). Sent and cancelled
  /// rows are excluded — the UI only shows pending/failed.
  Future<List<ScheduledMessage>> listForConversation({
    required String familyId,
    String? groupId,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return const [];
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return const [];

      // The RLS policy restricts to authorId = auth.uid() at the DB
      // level; we still filter client-side for clarity + to keep the
      // wire payload small.
      // Build the query. Filter methods (.eq, .inFilter, .isFilter) must
      // come BEFORE transforms (.order, .limit) because the supabase-dart
      // client's filter methods live on PostgrestFilterBuilder, while
      // .order returns PostgrestTransformBuilder (no filter methods).
      // Use a conditional to inline the groupId filter.
      final response = await (groupId == null
          ? client
              .from('ChatScheduledMessage')
              .select()
              .eq('familyId', familyId)
              .eq('authorId', myUserId)
              .inFilter('status', const ['pending', 'failed'])
              .isFilter('groupId', null)
              .order('sendAt', ascending: true)
          : client
              .from('ChatScheduledMessage')
              .select()
              .eq('familyId', familyId)
              .eq('authorId', myUserId)
              .inFilter('status', const ['pending', 'failed'])
              .eq('groupId', groupId)
              .order('sendAt', ascending: true));
      final rows = response as List<dynamic>? ?? const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ScheduledMessage.fromJson)
          .toList();
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.listForConversation: $e');
      return const [];
    }
  }

  /// Cancel a pending scheduled message. Marks status='cancelled'
  /// (the dispatch function won't pick it up). Author-only via RLS.
  Future<CancelResult> cancel(String scheduledId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return CancelResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return CancelResult.error;

      await client
          .from('ChatScheduledMessage')
          .update({
            'status': 'cancelled',
          })
          .eq('id', scheduledId)
          .eq('authorId', myUserId) // double-safety: RLS also enforces
          .inFilter('status', const ['pending', 'failed']);
      return CancelResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.cancel: $e');
      return CancelResult.error;
    }
  }

  /// Retry a failed scheduled message — flips status back to 'pending'
  /// so the next dispatch picks it up. Author-only via RLS.
  Future<CancelResult> retry(String scheduledId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return CancelResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return CancelResult.error;

      await client
          .from('ChatScheduledMessage')
          .update({
            'status': 'pending',
            'failureReason': null,
          })
          .eq('id', scheduledId)
          .eq('authorId', myUserId)
          .eq('status', 'failed');
      return CancelResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.retry: $e');
      return CancelResult.error;
    }
  }

  /// Update the sendAt time of a pending scheduled message (the
  /// "Edit time" action in the scheduled list). Author-only via RLS.
  Future<CancelResult> updateSendAt({
    required String scheduledId,
    required DateTime newSendAt,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return CancelResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return CancelResult.error;

      // Reject past times client-side; the DB CHECK also rejects.
      if (!newSendAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        return CancelResult.error;
      }

      await client
          .from('ChatScheduledMessage')
          .update({
            'sendAt': newSendAt.toUtc().toIso8601String(),
          })
          .eq('id', scheduledId)
          .eq('authorId', myUserId)
          .eq('status', 'pending');
      return CancelResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.updateSendAt: $e');
      return CancelResult.error;
    }
  }

  /// Update the content of a pending scheduled message (the "Edit
  /// text" action in the scheduled list). Author-only via RLS.
  Future<CancelResult> updateContent({
    required String scheduledId,
    required String newContent,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return CancelResult.error;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return CancelResult.error;

      final trimmed = newContent.trim();
      if (trimmed.isEmpty) return CancelResult.error;

      await client
          .from('ChatScheduledMessage')
          .update({
            'content': trimmed,
          })
          .eq('id', scheduledId)
          .eq('authorId', myUserId)
          .inFilter('status', const ['pending', 'failed']);
      return CancelResult.ok;
    } catch (e) {
      debugPrint('⚠️ ChatScheduledMessageService.updateContent: $e');
      return CancelResult.error;
    }
  }
}

/// Riverpod provider.
final chatScheduledMessageServiceProvider =
    Provider<ChatScheduledMessageService>((ref) {
  return ChatScheduledMessageService(ref);
});
