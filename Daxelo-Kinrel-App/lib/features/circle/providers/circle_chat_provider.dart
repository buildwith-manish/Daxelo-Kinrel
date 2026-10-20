// lib/features/circle/providers/circle_chat_provider.dart
//
// DAXELO KINREL — Circle Chat Provider (Phase 3)
//
// Manages circle messages: loading, sending, realtime delivery,
// reactions, read receipts, pins. Parallel to the existing ChatNotifier
// for family chats but keyed by circleId instead of familyId.
//
// Realtime channel: 'circle:$circleId' (Supabase Realtime Postgres
// Changes on the CircleMessage table, filtered by circleId).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/haptic_service.dart';

/// A single circle chat message (mirrors the CircleMessage table row).
class CircleChatMessage {
  CircleChatMessage({
    required this.id,
    required this.circleId,
    required this.senderId,
    required this.senderName,
    this.senderInitials,
    this.senderPersonId,
    this.senderFamilyId,
    required this.content,
    this.messageType = 'text',
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.isEdited = false,
    this.isDeletedForEveryone = false,
    this.isPinned = false,
    this.pinnedBy,
    this.pinnedAt,
    this.messageStatus = 'sent',
    this.mediaUrl,
    this.mediaType,
    this.mediaFileName,
    this.thumbnailUrl,
    this.voiceMessageDuration,
    this.readBy = const [],
    this.reactions = const {},
    required this.createdAt,
    this.tempId,
  });

  final String id;
  final String circleId;
  final String senderId;
  final String senderName;
  final String? senderInitials;
  final String? senderPersonId;
  final String? senderFamilyId;
  final String content;
  final String messageType;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final bool isEdited;
  final bool isDeletedForEveryone;
  final bool isPinned;
  final String? pinnedBy;
  final DateTime? pinnedAt;
  final String messageStatus;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaFileName;
  final String? thumbnailUrl;
  final int? voiceMessageDuration;
  final List<String> readBy;
  final Map<String, int> reactions; // emoji → count
  final DateTime createdAt;
  final String? tempId; // client-generated optimistic ID

  factory CircleChatMessage.fromJson(Map<String, dynamic> json) {
    return CircleChatMessage(
      id: json['id']?.toString() ?? '',
      circleId: json['circleId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? 'Member',
      senderInitials: json['senderInitials']?.toString(),
      senderPersonId: json['senderPersonId']?.toString(),
      senderFamilyId: json['senderFamilyId']?.toString(),
      content: json['content']?.toString() ?? '',
      messageType: json['messageType']?.toString() ?? 'text',
      replyToId: json['replyToId']?.toString(),
      replyToContent: json['replyToContent']?.toString(),
      replyToSenderName: json['replyToSenderName']?.toString(),
      isEdited: json['isEdited'] as bool? ?? false,
      isDeletedForEveryone: json['isDeletedForEveryone'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      pinnedBy: json['pinnedBy']?.toString(),
      pinnedAt: json['pinnedAt'] != null
          ? DateTime.tryParse(json['pinnedAt'].toString())
          : null,
      messageStatus: json['messageStatus']?.toString() ?? 'sent',
      mediaUrl: json['mediaUrl']?.toString(),
      mediaType: json['mediaType']?.toString(),
      mediaFileName: json['mediaFileName']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      voiceMessageDuration: json['voiceMessageDuration'] as int?,
      readBy: (json['readBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      tempId: json['tempId']?.toString(),
    );
  }

  CircleChatMessage copyWith({
    bool? isEdited,
    bool? isDeletedForEveryone,
    bool? isPinned,
    String? pinnedBy,
    DateTime? pinnedAt,
    String? messageStatus,
    List<String>? readBy,
    Map<String, int>? reactions,
  }) {
    return CircleChatMessage(
      id: id,
      circleId: circleId,
      senderId: senderId,
      senderName: senderName,
      senderInitials: senderInitials,
      senderPersonId: senderPersonId,
      senderFamilyId: senderFamilyId,
      content: content,
      messageType: messageType,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      isEdited: isEdited ?? this.isEdited,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      isPinned: isPinned ?? this.isPinned,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      messageStatus: messageStatus ?? this.messageStatus,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaFileName: mediaFileName,
      thumbnailUrl: thumbnailUrl,
      voiceMessageDuration: voiceMessageDuration,
      readBy: readBy ?? this.readBy,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt,
      tempId: tempId,
    );
  }
}

/// Circle chat state.
class CircleChatState {
  const CircleChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.circleName,
    this.memberCount = 0,
    this.onlyAdminsPost = false,
    this.myRole = 'member',
    this.isMember = true,
    this.pinnedMessage,
  });

  final List<CircleChatMessage> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final String? circleName;
  final int memberCount;
  final bool onlyAdminsPost;
  final String myRole;
  final bool isMember;
  final CircleChatMessage? pinnedMessage;

  CircleChatState copyWith({
    List<CircleChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    String? circleName,
    int? memberCount,
    bool? onlyAdminsPost,
    String? myRole,
    bool? isMember,
    CircleChatMessage? pinnedMessage,
  }) {
    return CircleChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      circleName: circleName ?? this.circleName,
      memberCount: memberCount ?? this.memberCount,
      onlyAdminsPost: onlyAdminsPost ?? this.onlyAdminsPost,
      myRole: myRole ?? this.myRole,
      isMember: isMember ?? this.isMember,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
    );
  }
}

/// Circle chat notifier — manages messages for a single circle.
class CircleChatNotifier extends StateNotifier<CircleChatState> {
  CircleChatNotifier(this._circleId) : super(const CircleChatState(isLoading: true)) {
    _init();
  }

  final String _circleId;
  RealtimeChannel? _channel;
  static const int _pageSize = 50;

  Future<void> _init() async {
    await Future.wait([
      _loadCircleMeta(),
      _loadMessages(),
    ]);
    _subscribeToRealtime();
  }

  /// Loads the circle metadata (name, member count, settings, my role).
  Future<void> _loadCircleMeta() async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return;

      // Load circle + my membership in one query
      final resp = await client
          .from('Circle')
          .select(
              'id, name, onlyAdminsPost, anyoneCanAdd, members:CircleMember(userId, role, isArchived)')
          .eq('id', _circleId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (resp == null) {
        state = state.copyWith(isMember: false, isLoading: false);
        return;
      }

      final members = resp['members'] as List? ?? [];
      final myMembership = members.firstWhere(
        (m) => m['userId'] == myUserId,
        orElse: () => <String, dynamic>{},
      );

      if (myMembership.isEmpty) {
        state = state.copyWith(
          isMember: false,
          isLoading: false,
          circleName: resp['name']?.toString(),
        );
        return;
      }

      state = state.copyWith(
        circleName: resp['name']?.toString(),
        memberCount: members.length,
        onlyAdminsPost: resp['onlyAdminsPost'] as bool? ?? false,
        myRole: myMembership['role']?.toString() ?? 'member',
        isMember: true,
      );
    } catch (e) {
      debugPrint('⚠️ CircleChat: loadCircleMeta failed: $e');
      state = state.copyWith(error: 'Could not load circle.', isLoading: false);
    }
  }

  /// Loads the latest page of messages (newest first).
  Future<void> _loadMessages() async {
    try {
      final client = Supabase.instance.client;
      final resp = await client
          .from('CircleMessage')
          .select()
          .eq('circleId', _circleId)
          .eq('isDeletedForEveryone', false)
          .order('createdAt', ascending: false)
          .limit(_pageSize)
          .timeout(const Duration(seconds: 10));

      final messages = (resp as List)
          .map((j) => CircleChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();

      // Find the pinned message (if any)
      final pinned = messages.firstWhere(
        (m) => m.isPinned,
        orElse: () => messages.isNotEmpty ? messages.last : CircleChatMessage(id: '', circleId: _circleId, senderId: '', senderName: '', content: '', createdAt: DateTime.now()),
      );

      state = state.copyWith(
        messages: messages.reversed.toList(), // oldest first for display
        isLoading: false,
        hasMore: messages.length >= _pageSize,
        pinnedMessage: pinned.id.isNotEmpty ? pinned : null,
      );
    } catch (e) {
      debugPrint('⚠️ CircleChat: loadMessages failed: $e');
      state = state.copyWith(isLoading: false, error: 'Could not load messages.');
    }
  }

  /// Subscribes to realtime changes on the CircleMessage table.
  void _subscribeToRealtime() {
    try {
      final client = Supabase.instance.client;
      _channel = client.channel('circle:$_circleId');

      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'CircleMessage',
        
        callback: (payload) {
          final newMsg = CircleChatMessage.fromJson(payload.newRecord);
          if (newMsg.circleId != _circleId) return; // downstream filter
          if (!state.messages.any((m) => m.id == newMsg.id)) {
            state = state.copyWith(messages: [...state.messages, newMsg]);
          }
        },
      );

      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'CircleMessage',
        
        callback: (payload) {
          final updated = CircleChatMessage.fromJson(payload.newRecord);
          if (updated.circleId != _circleId) return; // downstream filter
          final msgs = state.messages.map((m) {
            if (m.id == updated.id) return updated;
            return m;
          }).toList();
          state = state.copyWith(
            messages: msgs,
            pinnedMessage: updated.isPinned ? updated : null,
          );
        },
      );

      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'CircleMessage',
        
        callback: (payload) {
          final deletedId = payload.oldRecord['id']?.toString();
          final deletedCircleId = payload.oldRecord['circleId']?.toString();
          if (deletedCircleId != _circleId) return; // downstream filter
          if (deletedId != null) {
            state = state.copyWith(
              messages: state.messages.where((m) => m.id != deletedId).toList(),
            );
          }
        },
      );

      // Also listen for CircleMember changes (removal = lose access)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'CircleMember',
        
        callback: (payload) {
          final deletedUserId = payload.oldRecord['userId']?.toString();
          final deletedCircleId = payload.oldRecord['circleId']?.toString();
          if (deletedCircleId != _circleId) return; // downstream filter
          final myUserId = client.auth.currentUser?.id;
          if (deletedUserId == myUserId) {
            // I was removed!
            state = state.copyWith(isMember: false);
          }
        },
      );

      _channel!.subscribe();
    } catch (e) {
      debugPrint('⚠️ CircleChat: realtime subscribe failed: $e');
    }
  }

  /// Sends a text message.
  Future<bool> sendMessage({
    required String content,
    String messageType = 'text',
    String? replyToId,
    String? senderPersonId,
    String? senderFamilyId,
    String? senderInitials,
    String? mediaUrl,
    String? mediaType,
    String? mediaFileName,
    String? tempId,
  }) async {
    if (content.trim().isEmpty && mediaUrl == null) return false;

    // Check onlyAdminsPost
    if (state.onlyAdminsPost && state.myRole != 'admin') {
      state = state.copyWith(error: 'Only admins can post in this circle.');
      return false;
    }

    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return false;

      final msgId = tempId ?? 'cmsg_${DateTime.now().millisecondsSinceEpoch}';

      // Optimistic insert
      final optimistic = CircleChatMessage(
        id: msgId,
        circleId: _circleId,
        senderId: myUserId,
        senderName: state.myRole == 'admin' ? 'You' : 'You',
        senderInitials: senderInitials,
        senderPersonId: senderPersonId,
        senderFamilyId: senderFamilyId,
        content: content,
        messageType: messageType,
        replyToId: replyToId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        mediaFileName: mediaFileName,
        messageStatus: 'sent',
        createdAt: DateTime.now(),
        tempId: tempId,
      );
      state = state.copyWith(messages: [...state.messages, optimistic]);

      // Insert to DB
      await client.from('CircleMessage').insert({
        'id': msgId,
        'circleId': _circleId,
        'senderId': myUserId,
        'senderName': 'You',
        'senderInitials': senderInitials,
        'senderPersonId': senderPersonId,
        'senderFamilyId': senderFamilyId,
        'content': content,
        'messageType': messageType,
        if (replyToId != null) 'replyToId': replyToId,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (mediaFileName != null) 'mediaFileName': mediaFileName,
      });

      // Bump circle lastActivityAt
      await client
          .from('Circle')
          .update({'lastActivityAt': DateTime.now().toIso8601String()})
          .eq('id', _circleId);

      HapticService.success();
      return true;
    } catch (e) {
      debugPrint('⚠️ CircleChat: sendMessage failed: $e');
      // Mark the optimistic message as failed
      state = state.copyWith(error: 'Failed to send. Tap to retry.');
      HapticService.error();
      return false;
    }
  }

  /// Marks a message (or all unread) as read.
  Future<void> markAsRead({String? messageId}) async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return;

      if (messageId != null) {
        await client.from('CircleReadReceipt').upsert({
          'messageId': messageId,
          'userId': myUserId,
        });
      }
    } catch (e) {
      debugPrint('⚠️ CircleChat: markAsRead failed: $e');
    }
  }

  /// Adds a reaction to a message.
  Future<void> addReaction(String messageId, String emoji) async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return;

      await client.from('CircleReaction').upsert({
        'messageId': messageId,
        'userId': myUserId,
        'emoji': emoji,
      });
    } catch (e) {
      debugPrint('⚠️ CircleChat: addReaction failed: $e');
    }
  }

  /// Removes a reaction.
  Future<void> removeReaction(String messageId, String emoji) async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return;

      await client
          .from('CircleReaction')
          .delete()
          .eq('messageId', messageId)
          .eq('userId', myUserId)
          .eq('emoji', emoji);
    } catch (e) {
      debugPrint('⚠️ CircleChat: removeReaction failed: $e');
    }
  }

  /// Pins a message (admin only).
  Future<void> pinMessage(String messageId) async {
    if (state.myRole != 'admin') return;
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      await client.from('CircleMessage').update({
        'isPinned': true,
        'pinnedBy': myUserId,
        'pinnedAt': DateTime.now().toIso8601String(),
      }).eq('id', messageId);
    } catch (e) {
      debugPrint('⚠️ CircleChat: pinMessage failed: $e');
    }
  }

  /// Unpins a message (admin only).
  Future<void> unpinMessage(String messageId) async {
    if (state.myRole != 'admin') return;
    try {
      final client = Supabase.instance.client;
      await client.from('CircleMessage').update({
        'isPinned': false,
        'pinnedBy': null,
        'pinnedAt': null,
      }).eq('id', messageId);
    } catch (e) {
      debugPrint('⚠️ CircleChat: unpinMessage failed: $e');
    }
  }

  /// Loads more messages (pagination).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final client = Supabase.instance.client;
      final oldest = state.messages.isNotEmpty
          ? state.messages.first.createdAt
          : DateTime.now();

      final resp = await client
          .from('CircleMessage')
          .select()
          .eq('circleId', _circleId)
          .eq('isDeletedForEveryone', false)
          .lt('createdAt', oldest.toIso8601String())
          .order('createdAt', ascending: false)
          .limit(_pageSize)
          .timeout(const Duration(seconds: 10));

      final newMsgs = (resp as List)
          .map((j) => CircleChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        messages: [...newMsgs.reversed, ...state.messages],
        isLoadingMore: false,
        hasMore: newMsgs.length >= _pageSize,
      );
    } catch (e) {
      debugPrint('⚠️ CircleChat: loadMore failed: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

/// Provider keyed by circleId.
final circleChatProvider =
    StateNotifierProvider.family<CircleChatNotifier, CircleChatState, String>(
  (ref, circleId) => CircleChatNotifier(circleId),
);
