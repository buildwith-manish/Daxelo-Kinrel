// lib/features/chat/data/scheduled_messages_provider.dart
//
// DAXELO KINREL — Tier 1 Feature 1.2: Scheduled Messages — Provider
//
// Calls the NestJS endpoints exposed by ScheduledMessagesController:
//   • POST   /chat/scheduled          — schedule a message
//   • GET    /chat/scheduled           — list pending + failed
//   • GET    /chat/scheduled/:id      — fetch one
//   • DELETE /chat/scheduled/:id      — cancel (only pending rows)
//
// The actual dispatch happens server-side: a @Cron in
// ScheduledMessagesService fires every minute + a pg_cron job
// (fn_send_scheduled_messages) acts as a DB-side fallback. The
// Flutter client just reads the row state and reflects it in the UI.
//
// Used by:
//   - ScheduleMessageSheet (composer long-press send → schedule)
//   - ScheduledTraySheet (inbox → "Scheduled: N" badge)
//   - chat_screen.dart (renders a "scheduled at <time>" hint in the
//     composer when a draft is staged for scheduling)

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/dio_client.dart';

/// One scheduled-message row. Mirrors the Prisma ScheduledMessage model.
@immutable
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.senderId,
    this.familyId,
    this.receiverId,
    required this.content,
    required this.messageType,
    this.mediaUrl,
    this.mediaType,
    required this.mentions,
    this.replyToId,
    required this.scheduledFor,
    required this.status,
    this.sentMessageId,
    this.failureReason,
    required this.createdAt,
    this.sentAt,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) {
    return ScheduledMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      familyId: json['familyId'] as String?,
      receiverId: json['receiverId'] as String?,
      content: json['content'] as String? ?? '',
      messageType: json['messageType'] as String? ?? 'text',
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String?,
      mentions: (json['mentions'] as List?)?.cast<dynamic>() ?? const [],
      replyToId: json['replyToId'] as String?,
      scheduledFor: DateTime.tryParse(json['scheduledFor'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'pending',
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
  final String senderId;
  final String? familyId;
  final String? receiverId;
  final String content;
  final String messageType;
  final String? mediaUrl;
  final String? mediaType;
  final List<dynamic> mentions;
  final String? replyToId;
  final DateTime scheduledFor;
  final String status; // pending | sent | cancelled | failed
  final String? sentMessageId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? sentAt;

  /// True when the row is still waiting to fire (pending or transient
  /// failure that the cron will retry). Sent + cancelled are terminal.
  bool get isActive => status == 'pending' || status == 'failed';

  /// True when this row targets a family group (vs a DM).
  bool get isFamilyMessage => familyId != null && receiverId == null;

  /// A short label like "Family: hello..." or "To Mama: ..." used by the
  /// scheduled tray sheet.
  String previewLabel() {
    final truncated = content.length > 40
        ? '${content.substring(0, 40)}...'
        : content;
    return truncated.isEmpty ? '(no preview)' : truncated;
  }
}

/// The state exposed by ScheduledMessagesProvider.
class ScheduledMessagesState {
  const ScheduledMessagesState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  final List<ScheduledMessage> items;
  final bool isLoading;
  final String? error;

  ScheduledMessagesState copyWith({
    List<ScheduledMessage>? items,
    bool? isLoading,
    String? error,
  }) {
    return ScheduledMessagesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ScheduledMessagesNotifier extends StateNotifier<ScheduledMessagesState> {
  ScheduledMessagesNotifier(this._dio) : super(const ScheduledMessagesState());

  final Dio _dio;

  /// Refresh the caller's pending + failed scheduled messages. Called
  /// on app startup + on a manual pull-to-refresh in the scheduled tray.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.dio.get('/chat/scheduled');
      final data = response.data;
      final list = (data as List<dynamic>?)
              ?.map((e) => ScheduledMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      state = ScheduledMessagesState(items: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load scheduled messages: $e',
      );
    }
  }

  /// Schedule a new message. Pass either familyId (group) or receiverId
  /// (DM). Returns the created ScheduledMessage or throws on error.
  Future<ScheduledMessage> schedule({
    String? familyId,
    String? receiverId,
    required String content,
    required DateTime scheduledFor,
    String messageType = 'text',
    String? mediaUrl,
    String? mediaType,
    String? replyToId,
    String? clientScheduleId,
  }) async {
    final response = await _dio.dio.post('/chat/scheduled', data: {
      if (familyId != null) 'familyId': familyId,
      if (receiverId != null) 'receiverId': receiverId,
      'content': content,
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      'messageType': messageType,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (replyToId != null) 'replyToId': replyToId,
      if (clientScheduleId != null) 'clientScheduleId': clientScheduleId,
    });
    final created = ScheduledMessage.fromJson(
      response.data as Map<String, dynamic>,
    );
    // Optimistic state update — prepend the new row.
    state = state.copyWith(items: [created, ...state.items]);
    return created;
  }

  /// Cancel a pending scheduled message. Returns true on success.
  Future<bool> cancel(String scheduledId) async {
    try {
      await _dio.dio.delete('/chat/scheduled/$scheduledId');
      // Optimistically remove the row from the local state.
      state = state.copyWith(
        items: state.items.where((m) => m.id != scheduledId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to cancel: $e');
      return false;
    }
  }
}

final scheduledMessagesProvider =
    StateNotifierProvider<ScheduledMessagesNotifier, ScheduledMessagesState>(
  (ref) => ScheduledMessagesNotifier(ref.read(dioProvider)),
);
