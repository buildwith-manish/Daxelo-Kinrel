// lib/features/chat/data/models/chat_message.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.
//
// All field defaults, parsing helpers, getters, copyWith, and toJson
// are byte-identical to the pre-refactor definitions. The parse helpers
// (_parseMentions, _parseStringArray, _parseIntArray, _parseVoterIds,
// _parseMessageType) are private statics on the class itself, unchanged.

import '../../../../core/utils/app_time.dart';
import 'mention_ref.dart';
import 'message_reaction.dart';
import 'message_type.dart';

/// A single chat message in the family group.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    required this.timestamp,
    this.isRead = false,
    this.reactions = const [],
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.isOnline = false,
    this.senderInitials,
    this.durationSeconds, // for voice notes
    this.eventTitle, // for family event sharing
    this.eventDate, // for family event sharing
    // feat(chat): live family event cards — denormalized event fields
    // synced by fn_sync_family_event_chat_cards (migration
    // 20261019120000). The card UI reads these directly; the
    // migration's AFTER UPDATE triggers keep them in sync with the
    // live calendar_events + calendar_event_rsvps state.
    this.eventId,
    this.eventLocation,
    this.eventCategory,
    this.eventRsvpGoing = 0,
    this.eventRsvpMaybe = 0,
    this.eventRsvpNotGoing = 0,
    this.eventDeletedAt,
    this.mediaUrl, // v91: for photo/voice attachments
    // Phase 13 enhancement fields
    this.isStarred = false,
    this.isPinned = false,
    this.isEdited = false,
    this.isDeletedForEveryone = false,
    this.messageStatus = 'sent',
    this.messageSubType,
    this.forwardedFrom,
    this.deletedForMe = const [],
    this.groupId, // v137: for group-scoped messages (null = family-wide chat)
    // Game-invite card fields (messageType == gameInvite)
    this.gameType, // route segment, e.g. 'sos' → '/family/<id>/sos/lobby'
    this.gameId, // id of the <game>_games row the invite points at
    this.roomCode, // 6-char display room code
    this.gameMaxPlayers,
    this.gameCurrentPlayers,
    this.gameInviteStatus, // 'pending' | 'in_progress' | 'completed' | 'expired' | 'cancelled'
                           // (legacy 'accepted' = 'in_progress')
    this.gameWinnerName,    // 5-state lifecycle: winner display name (privacy-gated)
    this.gameCompletedAt,   // 5-state lifecycle: when the game finished
    this.gameSpectatorsEnabled, // Spectator-mode flag (gates Spectate button on
                                // in_progress cards). Null = legacy/unknown,
                                // treated as `true` by the card for backward
                                // compatibility (spectator mode was historically
                                // on by default).
    // Phase 22 / Task 3 — @mention references. Denormalized from the
    // ChatMention table so the bubble renderer can highlight @Name spans
    // without an extra round-trip.
    this.mentions = const [],
    // Phase 22 / Task 5 — poll fields (messageType == poll).
    this.pollQuestion,
    this.pollOptions = const [],
    this.pollVoteCounts = const [],
    this.pollVoterIds = const [],
    this.pollCreatedAt,
  });

  /// Parse a ChatMessage from a Supabase row.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Unknown',
      content: json['content'] as String? ?? '',
      messageType: _parseMessageType(json['messageType'] as String?),
      timestamp: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      reactions: const [],
      replyToId: json['replyToId'] as String?,
      replyToContent: json['replyToContent'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      senderInitials: json['senderInitials'] as String?,
      durationSeconds: (json['durationSeconds'] as int?) ??
          (json['voiceMessageDuration'] as int?),
      eventTitle: json['eventTitle'] as String?,
      eventDate: json['eventDate'] as String?,
      // feat(chat): live family event cards — parse the denormalized
      // event fields (synced by the migration's AFTER UPDATE triggers).
      eventId: json['eventId'] as String?,
      eventLocation: json['eventLocation'] as String?,
      eventCategory: json['eventCategory'] as String?,
      eventRsvpGoing: (json['eventRsvpGoing'] as num?)?.toInt() ?? 0,
      eventRsvpMaybe: (json['eventRsvpMaybe'] as num?)?.toInt() ?? 0,
      eventRsvpNotGoing: (json['eventRsvpNotGoing'] as num?)?.toInt() ?? 0,
      eventDeletedAt: json['eventDeletedAt'] == null
          ? null
          : DateTime.tryParse(json['eventDeletedAt'] as String),
      mediaUrl: json['mediaUrl'] as String?,
      isStarred: json['isStarred'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      isDeletedForEveryone: json['isDeletedForEveryone'] as bool? ?? false,
      messageStatus: json['messageStatus'] as String? ?? 'sent',
      messageSubType: json['messageSubType'] as String?,
      forwardedFrom: json['forwardedFrom'] as String?,
      deletedForMe: json['deletedForMe'] as List<dynamic>? ?? const [],
      groupId: json['groupId'] as String?,
      gameType: json['gameType'] as String?,
      gameId: json['gameId'] as String?,
      roomCode: json['roomCode'] as String?,
      gameMaxPlayers: json['gameMaxPlayers'] as int?,
      gameCurrentPlayers: json['gameCurrentPlayers'] as int?,
      gameInviteStatus: json['gameInviteStatus'] as String?,
      // 5-state lifecycle: winner display name (privacy-gated server-side
      // by fn_sync_game_invite_status — null for non-participants).
      gameWinnerName: json['gameWinnerName'] as String?,
      // 5-state lifecycle: when the game finished (server-set on
      // transition to 'completed').
      gameCompletedAt: json['gameCompletedAt'] == null
          ? null
          : DateTime.tryParse(json['gameCompletedAt'] as String),
      // Spectator-mode flag: denormalized from the game row's
      // spectatorsEnabled column by fn_sync_game_spectators (AFTER UPDATE
      // trigger). Null on legacy rows → treated as `true` by the card.
      gameSpectatorsEnabled: json['gameSpectatorsEnabled'] == null
          ? null
          : (json['gameSpectatorsEnabled'] as bool),
      // Phase 22 / Task 3 — parse the denormalized `mentions` JSONB
      // column. Falls back to [] when the column is null or the row
      // came from a server that didn't have the column yet.
      mentions: _parseMentions(json['mentions']),
      // Phase 22 / Task 5 — poll fields.
      pollQuestion: json['pollQuestion'] as String?,
      pollOptions: _parseStringArray(json['pollOptions']),
      pollVoteCounts: _parseIntArray(json['pollVoteCounts']),
      pollVoterIds: _parseVoterIds(json['pollVoterIds']),
      pollCreatedAt: json['pollCreatedAt'] == null
          ? null
          : DateTime.tryParse(json['pollCreatedAt'] as String),
    );
  }

  /// URL of the attached media (photo or voice note) in Supabase storage.
  final String? mediaUrl;

  /// Unique message identifier.
  final String id;

  /// Sender's user ID.
  final String senderId;

  /// Sender's display name.
  final String senderName;

  /// Message text content (or caption for media).
  final String content;

  /// Type of message.
  final MessageType messageType;

  /// When the message was sent.
  final DateTime timestamp;

  /// Whether the message has been read by the current user.
  final bool isRead;

  /// Emoji reactions on this message.
  final List<MessageReaction> reactions;

  /// ID of the message this is replying to (null if not a reply).
  final String? replyToId;

  /// Snippet of the message being replied to.
  final String? replyToContent;

  /// Sender name of the message being replied to.
  final String? replyToSenderName;

  /// Whether the sender is currently online.
  final bool isOnline;

  /// Sender's initials for avatar.
  final String? senderInitials;

  /// Duration in seconds (for voice notes).
  final int? durationSeconds;

  /// Event title (for family event sharing).
  final String? eventTitle;

  /// Event date string (for family event sharing).
  final String? eventDate;

  // ── feat(chat): live family event cards ─────────────────────────
  // Denormalized event fields. Synced by fn_sync_family_event_chat_cards
  // (migration 20261019120000) — AFTER INSERT/UPDATE/DELETE triggers
  // on calendar_events + calendar_event_rsvps recompute these and
  // UPDATE every ChatMessage row that references the event. The
  // chat_provider's existing realtime UPDATE subscription on
  // ChatMessage then propagates the synced fields to every open chat
  // UI automatically — the cards stay live without any client-side
  // re-fetch.
  /// The id of the calendar_events row this card represents.
  final String? eventId;

  /// Event location (denormalized).
  final String? eventLocation;

  /// Event category — drives the icon + accent color.
  final String? eventCategory;

  /// Live RSVP counts — kept in sync by the migration's triggers.
  final int eventRsvpGoing;
  final int eventRsvpMaybe;
  final int eventRsvpNotGoing;

  /// Set when the underlying calendar_events row is deleted. The card
  /// UI renders "Event no longer available" with disabled RSVP buttons
  /// until the ChatMessage row itself is deleted.
  final DateTime? eventDeletedAt;

  /// Phase 13: Whether the message is starred (bookmarked) by current user.
  final bool isStarred;

  /// Phase 13: Whether the message is pinned by an admin/creator.
  final bool isPinned;

  /// Phase 13: Whether the message was edited after sending.
  final bool isEdited;

  /// Phase 13: Whether the message was deleted for everyone (sender or admin).
  final bool isDeletedForEveryone;

  /// Phase 13: Message delivery status: 'sent' | 'delivered' | 'read'.
  final String messageStatus;

  /// Phase 13: Message subtype: 'text' | 'image' | 'video' | 'audio' |
  /// 'voice' | 'document' | 'sticker' | 'gif' | 'contact' | 'location' | 'system'.
  final String? messageSubType;

  /// Phase 13: Original sender name if message was forwarded.
  final String? forwardedFrom;

  /// Phase 13: List of user IDs who deleted this message for themselves only.
  final List<dynamic> deletedForMe;

  /// v137: Group ID if this message belongs to a sub-group chat.
  /// Null means it's a family-wide chat message.
  final String? groupId;

  /// Game-invite card: the game's route segment (e.g. 'sos'). Used both for
  /// display and to build the lobby join route.
  final String? gameType;

  /// Game-invite card: id of the game room row (`<game>_games`.id).
  final String? gameId;

  /// Game-invite card: the 6-char display room code.
  final String? roomCode;

  /// Game-invite card: maximum players for the room.
  final int? gameMaxPlayers;

  /// Game-invite card: current players in the room. Kept in sync with the
  /// live game state by syncGameInviteChatCards() so the card shows
  /// "2/4 players" / flips to "Full" without reopening the thread.
  final int? gameCurrentPlayers;

  /// Game-invite card lifecycle: 'pending' (waiting/open-to-join lobby
  /// state) | 'in_progress' (game started, players are playing) |
  /// 'completed' (game finished normally) | 'expired' (room never filled /
  /// never started in time) | 'cancelled' (host cancelled — legacy alias
  /// for 'expired'). Null is treated as 'pending'.
  ///
  /// Legacy 'accepted' is a pre-state-machine alias for 'in_progress';
  /// the GameInviteStatusChip classifier handles both.
  ///
  /// Driven by:
  ///   • Per-game Flutter providers calling syncGameInviteChatCards()
  ///   • AFTER UPDATE trigger on each game table → fn_sync_game_invite_status
  ///   • pg_cron-driven fn_sweep_expired_game_rooms() (5-min cadence)
  final String? gameInviteStatus;

  /// 5-state lifecycle: display name of the match winner, written when
  /// the game completes. PRIVACY-GATED — the server-side
  /// fn_sync_game_invite_status RPC only writes this column if the
  /// requesting user (auth.uid()) is a participant of the match (verified
  /// via game_participants). Non-participants see null and the card
  /// renders a generic "Game completed" treatment.
  ///
  /// When the value IS present, it's safe to render — the requesting user
  /// was a participant. The frontend does NOT need to re-validate.
  final String? gameWinnerName;

  /// 5-state lifecycle: server-set completion timestamp. Populated when
  /// gameInviteStatus transitions to 'completed'. Used by the card to
  /// render "Completed · 5m ago" alongside the status chip.
  final DateTime? gameCompletedAt;

  /// Spectator-mode flag denormalized from the game row's `spectatorsEnabled`
  /// column. Kept in sync by `fn_sync_game_spectators` (AFTER UPDATE OF
  /// spectatorsEnabled trigger on every game table) + the initial INSERT
  /// by `sendGameInvite` (which reads the value from the game row at
  /// invite-sent time).
  ///
  /// The chat-invite card uses this to decide whether to render a Spectate
  /// / Watch button for in_progress games:
  ///   • `true`  → Spectate button shown (host allows spectators)
  ///   • `false` → Spectate button hidden (host disabled spectators; only
  ///               the "In Game" / "LIVE NOW" status chip is shown)
  ///   • `null`  → legacy/unknown — treated as `true` for backward
  ///               compatibility (spectator mode was historically on by
  ///               default before this field was added).
  ///
  /// Driven by:
  ///   • ChatNotifier.sendGameInvite(spectatorsEnabled: ...) at insert time
  ///   • fn_sync_game_spectators RPC (called by AFTER UPDATE trigger)
  final bool? gameSpectatorsEnabled;

  /// Convenience: effective spectator-mode flag, defaulting to `true` for
  /// legacy/unknown rows. Use this at render sites instead of the raw
  /// nullable field.
  bool get effectiveSpectatorsEnabled => gameSpectatorsEnabled ?? true;

  /// Phase 22 / Task 3 — @mention refs on this message. Each contains
  /// the userId, display name, and the [start, end) character offsets
  /// into `content` where the `@Name` span lives. Used by the bubble
  /// renderer to highlight mentions and by the notifications UI to
  /// decide whether to show a 'you were mentioned' badge.
  final List<MentionRef> mentions;

  /// Convenience: does this message mention the current user?
  bool mentionsUser(String currentUserId) =>
      mentions.any((m) => m.userId == currentUserId);

  // ── Phase 22 / Task 5 — Poll fields (messageType == poll) ──

  /// The poll question (also mirrored in `content` so the inbox
  /// preview shows it).
  final String? pollQuestion;

  /// Poll options — array of strings, indexed 0..N-1. The voter's
  /// `optionIndex` corresponds to the index in this array.
  final List<String> pollOptions;

  /// Live vote counts — array of ints, indexed the same as [pollOptions].
  /// Updated by fn_vote_poll via a realtime UPDATE on the ChatMessage row.
  final List<int> pollVoteCounts;

  /// Voter refs — array of {userId, optionIndex} objects. Used by the
  /// client to determine the "you voted" state (find my userId in the
  /// array → that's the option I voted for). Stored on the row so the
  /// client doesn't need a separate query per poll.
  final List<Map<String, dynamic>> pollVoterIds;

  /// When the poll was posted (for the "Xh ago" label).
  final DateTime? pollCreatedAt;

  /// Convenience: which option did the current user vote for?
  /// Returns the option index (0-based) or null if they haven't voted.
  int? votedOptionIndex(String currentUserId) {
    for (final v in pollVoterIds) {
      if (v['userId'] == currentUserId) {
        return (v['optionIndex'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Convenience: total votes across all options.
  int get pollTotalVotes =>
      pollVoteCounts.fold(0, (sum, c) => sum + c);

  /// Game-invite card: whether the room is full.
  bool get isGameFull =>
      (gameCurrentPlayers ?? 0) >= (gameMaxPlayers ?? 1) &&
      messageType == MessageType.gameInvite;

  /// Game-invite card: whether the invite is no longer joinable because its
  /// lifecycle ended (in_progress / completed / expired / cancelled) — as
  /// opposed to merely being full.
  bool get isGameInviteClosed =>
      messageType == MessageType.gameInvite &&
      gameInviteStatus != null &&
      gameInviteStatus != 'pending';

  /// 5-state lifecycle: the game has actually started (host pressed "Start"
  /// or the equivalent RPC transitioned the row to in_progress/active).
  /// Legacy 'accepted' (pre-state-machine) is also treated as in-progress.
  bool get isGameInProgress =>
      messageType == MessageType.gameInvite &&
      (gameInviteStatus == 'in_progress' ||
       gameInviteStatus == 'accepted' ||
       gameInviteStatus == 'active');

  /// 5-state lifecycle: the game finished normally (winner determined,
  /// natural completion — NOT expired/cancelled).
  bool get isGameCompleted =>
      messageType == MessageType.gameInvite &&
      gameInviteStatus == 'completed';

  /// 5-state lifecycle: the room expired (never filled or never started in
  /// time) OR was cancelled by the host. Both render the same "expired"
  /// treatment per the spec ("greyed out, clearly inactive").
  bool get isGameExpired =>
      messageType == MessageType.gameInvite &&
      (gameInviteStatus == 'expired' ||
       gameInviteStatus == 'cancelled');

  /// 5-state lifecycle: the room is in a pre-game state (waiting or full)
  /// and is still joinable by other family members. This is the inverse
  /// of [isGameInviteClosed] but semantically clearer at call sites.
  bool get isGameJoinable =>
      messageType == MessageType.gameInvite &&
      (gameInviteStatus == null || gameInviteStatus == 'pending') &&
      !isGameFull;

  /// Convenience: grouped reactions (emoji → count).
  Map<String, int> get groupedReactions {
    final map = <String, int>{};
    for (final r in reactions) {
      map[r.emoji] = (map[r.emoji] ?? 0) + 1;
    }
    return map;
  }

  /// Convenience: whether this message is hidden for the current user
  /// (either soft-deleted-for-me or deleted-for-everyone).
  bool isHiddenFor(String userId) {
    if (isDeletedForEveryone) return true;
    if (deletedForMe.any((u) => u == userId)) return true;
    return false;
  }

  /// Convenience: formatted time string (e.g., "10:30 AM").
  ///
  /// Step 4: Now uses `AppTime.toLocalDisplay(timestamp)` to convert
  /// the server-returned UTC timestamp to the viewer's device-local
  /// timezone before extracting hour/minute. Previously this read
  /// `timestamp.hour` directly, which on a UTC DateTime returned the
  /// UTC hour — meaning non-UTC viewers saw the wrong wall-clock time
  /// for every chat message.
  String get formattedTime {
    final local = AppTime.toLocalDisplay(timestamp);
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  ChatMessage copyWith({
    bool? isRead,
    List<MessageReaction>? reactions,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    bool? isOnline,
    String? mediaUrl,
    bool? isStarred,
    bool? isPinned,
    bool? isEdited,
    bool? isDeletedForEveryone,
    String? messageStatus,
    String? content,
    List<dynamic>? deletedForMe,
    String? gameType,
    String? gameId,
    String? roomCode,
    int? gameMaxPlayers,
    int? gameCurrentPlayers,
    String? gameInviteStatus,
    String? gameWinnerName,
    DateTime? gameCompletedAt,
    bool? gameSpectatorsEnabled,
    List<MentionRef>? mentions,
    String? pollQuestion,
    List<String>? pollOptions,
    List<int>? pollVoteCounts,
    List<Map<String, dynamic>>? pollVoterIds,
    DateTime? pollCreatedAt,
    // feat(chat): live family event cards — copyWith support for the
    // synced event fields (used by the realtime UPDATE handler when
    // the trigger recomputes the denormalized fields).
    String? eventTitle,
    String? eventDate,
    String? eventId,
    String? eventLocation,
    String? eventCategory,
    int? eventRsvpGoing,
    int? eventRsvpMaybe,
    int? eventRsvpNotGoing,
    DateTime? eventDeletedAt,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      content: content ?? this.content,
      messageType: messageType,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      reactions: reactions ?? this.reactions,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      isOnline: isOnline ?? this.isOnline,
      senderInitials: senderInitials,
      durationSeconds: durationSeconds,
      eventTitle: eventTitle ?? this.eventTitle,
      eventDate: eventDate ?? this.eventDate,
      // feat(chat): live family event cards — pass through the synced
      // event fields (default to the existing value when the copyWith
      // caller doesn't override).
      eventId: eventId ?? this.eventId,
      eventLocation: eventLocation ?? this.eventLocation,
      eventCategory: eventCategory ?? this.eventCategory,
      eventRsvpGoing: eventRsvpGoing ?? this.eventRsvpGoing,
      eventRsvpMaybe: eventRsvpMaybe ?? this.eventRsvpMaybe,
      eventRsvpNotGoing: eventRsvpNotGoing ?? this.eventRsvpNotGoing,
      eventDeletedAt: eventDeletedAt ?? this.eventDeletedAt,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      isStarred: isStarred ?? this.isStarred,
      isPinned: isPinned ?? this.isPinned,
      isEdited: isEdited ?? this.isEdited,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      messageStatus: messageStatus ?? this.messageStatus,
      messageSubType: messageSubType,
      forwardedFrom: forwardedFrom,
      deletedForMe: deletedForMe ?? this.deletedForMe,
      gameType: gameType ?? this.gameType,
      gameId: gameId ?? this.gameId,
      roomCode: roomCode ?? this.roomCode,
      gameMaxPlayers: gameMaxPlayers ?? this.gameMaxPlayers,
      gameCurrentPlayers: gameCurrentPlayers ?? this.gameCurrentPlayers,
      gameInviteStatus: gameInviteStatus ?? this.gameInviteStatus,
      gameWinnerName: gameWinnerName ?? this.gameWinnerName,
      gameCompletedAt: gameCompletedAt ?? this.gameCompletedAt,
      gameSpectatorsEnabled: gameSpectatorsEnabled ?? this.gameSpectatorsEnabled,
      mentions: mentions ?? this.mentions,
      pollQuestion: pollQuestion ?? this.pollQuestion,
      pollOptions: pollOptions ?? this.pollOptions,
      pollVoteCounts: pollVoteCounts ?? this.pollVoteCounts,
      pollVoterIds: pollVoterIds ?? this.pollVoterIds,
      pollCreatedAt: pollCreatedAt ?? this.pollCreatedAt,
    );
  }

  /// Parse the `mentions` JSONB column into a List<MentionRef>.
  /// Tolerates null, non-list, and malformed entries (defensive — the
  /// server column is JSONB so we could get anything back).
  static List<MentionRef> _parseMentions(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MentionRef.fromJson)
        .where((m) => m.userId.isNotEmpty)
        .toList();
  }

  /// Parse a JSONB string array (pollOptions) into a List<String>.
  /// Tolerates null and non-list values.
  static List<String> _parseStringArray(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw.map((e) => e?.toString() ?? '').toList();
  }

  /// Parse a JSONB int array (pollVoteCounts) into a List<int>.
  /// Tolerates null, non-list, and non-int entries.
  static List<int> _parseIntArray(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw.map((e) {
      if (e is int) return e;
      if (e is num) return e.toInt();
      return 0;
    }).toList();
  }

  /// Parse a JSONB array of {userId, optionIndex} (pollVoterIds).
  /// Tolerates null, non-list, and malformed entries.
  static List<Map<String, dynamic>> _parseVoterIds(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .where((m) => m['userId'] != null)
        .toList();
  }

  static MessageType _parseMessageType(String? raw) {
    switch (raw) {
      case 'photo':
        return MessageType.photo;
      case 'voiceNote':
        return MessageType.voiceNote;
      case 'familyEvent':
        return MessageType.familyEvent;
      case 'sticker':
        return MessageType.sticker;
      case 'gameInvite':
        return MessageType.gameInvite;
      case 'poll':
        return MessageType.poll;
      case 'gif':
        return MessageType.gif;
      case 'document':
        return MessageType.document;
      case 'location':
        return MessageType.location;
      case 'system':
        return MessageType.system;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  /// Serialize for Supabase insert. Excludes server-managed fields
  /// (id is generated client-side as a CUID-like string; createdAt /
  /// updatedAt are server defaults; isRead is false on insert).
  Map<String, dynamic> toJson({required String familyId}) {
    return {
      'id': id,
      'familyId': familyId,
      'senderId': senderId,
      'senderName': senderName,
      'senderInitials': senderInitials,
      'content': content,
      'messageType': _messageTypeToString(messageType),
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'replyToSenderName': replyToSenderName,
      'durationSeconds': durationSeconds,
      'voiceMessageDuration': durationSeconds,
      'eventTitle': eventTitle,
      'eventDate': eventDate,
      // feat(chat): live family event cards — denormalized event fields
      // on the wire (read by the card UI; written by the migration's
      // fn_sync_family_event_chat_cards trigger function as well as
      // by ChatNotifier.sendFamilyEventCard at insert time).
      if (eventId != null) 'eventId': eventId,
      if (eventLocation != null) 'eventLocation': eventLocation,
      if (eventCategory != null) 'eventCategory': eventCategory,
      'eventRsvpGoing': eventRsvpGoing,
      'eventRsvpMaybe': eventRsvpMaybe,
      'eventRsvpNotGoing': eventRsvpNotGoing,
      if (eventDeletedAt != null)
        'eventDeletedAt': eventDeletedAt!.toUtc().toIso8601String(),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      'isStarred': isStarred,
      'isPinned': isPinned,
      'isEdited': isEdited,
      'isDeletedForEveryone': isDeletedForEveryone,
      'messageStatus': messageStatus,
      if (messageSubType != null) 'messageSubType': messageSubType,
      if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
      if (groupId != null) 'groupId': groupId,
      if (gameType != null) 'gameType': gameType,
      if (gameId != null) 'gameId': gameId,
      if (roomCode != null) 'roomCode': roomCode,
      if (gameMaxPlayers != null) 'gameMaxPlayers': gameMaxPlayers,
      if (gameCurrentPlayers != null) 'gameCurrentPlayers': gameCurrentPlayers,
      if (gameInviteStatus != null) 'gameInviteStatus': gameInviteStatus,
      // 5-state lifecycle: only sent on the wire when set (e.g. when the
      // host sends a completed-state card via sendGameInvite — rare; usually
      // these are server-set by fn_sync_game_invite_status trigger).
      if (gameWinnerName != null) 'gameWinnerName': gameWinnerName,
      if (gameCompletedAt != null)
        'gameCompletedAt': gameCompletedAt!.toUtc().toIso8601String(),
      // Spectator-mode flag: only sent on the wire when explicitly set
      // (host invite-time). Server-side fn_sync_game_spectators RPC keeps
      // it in sync afterwards via AFTER UPDATE trigger on each game table.
      if (gameSpectatorsEnabled != null)
        'gameSpectatorsEnabled': gameSpectatorsEnabled,
      // Phase 22 / Task 3 — mentions are stored as a JSONB array on the
      // row. Empty list → '[]' which the server treats as "no mentions".
      'mentions': mentions.map((m) => m.toJson()).toList(),
      // Phase 22 / Task 5 — poll fields. Null on non-poll rows.
      if (pollQuestion != null) 'pollQuestion': pollQuestion,
      if (pollOptions.isNotEmpty) 'pollOptions': pollOptions,
      if (pollVoteCounts.isNotEmpty) 'pollVoteCounts': pollVoteCounts,
      if (pollVoterIds.isNotEmpty) 'pollVoterIds': pollVoterIds,
      if (pollCreatedAt != null)
        'pollCreatedAt': pollCreatedAt!.toIso8601String(),
    };
  }

  static String _messageTypeToString(MessageType t) {
    switch (t) {
      case MessageType.photo:
        return 'photo';
      case MessageType.voiceNote:
        return 'voiceNote';
      case MessageType.familyEvent:
        return 'familyEvent';
      case MessageType.sticker:
        return 'sticker';
      case MessageType.gameInvite:
        return 'gameInvite';
      case MessageType.poll:
        return 'poll';
      case MessageType.gif:
        return 'gif';
      case MessageType.document:
        return 'document';
      case MessageType.location:
        return 'location';
      case MessageType.system:
        return 'system';
      case MessageType.text:
        return 'text';
    }
  }
}
