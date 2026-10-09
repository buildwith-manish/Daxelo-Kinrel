// lib/features/chat/presentation/widgets/chat_capabilities.dart
//
// DAXELO KINREL — Chat capability descriptor.
//
// Single source of truth for what a chat screen can do. Built once when
// the screen mounts (group factory) or hardcoded for direct chat. Every
// shared widget (selection bar, reaction bar, input bar, header bar,
// delete sheet) reads from this object — NEVER from `if (isDirectChat)`
// branches scattered through the widget tree.
//
// The two chat types stay separate at the data layer:
//   - chatProvider (group)          — full feature set
//   - directChatProvider (direct)   — text + reactions + reply only
// Differences in the UI come ONLY from ChatCapabilities fields.
//
// Per the Shared First rule: a feature that needs backend support the
// direct chat does NOT have is set to false here and the UI is hidden
// from direct chat. We never fake or stub backend behaviour.
//
// Failed-message Retry + Delete is available in BOTH chat types for the
// user's OWN failed messages; it is handled at the row level (existing
// `onRetryFailed` / `onDeleteFailed` seams) and at the selection-bar
// level (Delete is offered in direct chat ONLY when every selected
// message is an own failed one).
//
// Fields:
//   isDirect                — true for direct chat
//   canReply                 — Reply action (1 selected)
//   canReact                 — floating reaction pill (1 selected, has reactions)
//   canCopy                  — overflow Copy
//   canShareOutside          — overflow "Share outside Kinrel"
//   canForward               — selection-bar Forward arrow
//   canStar                  — overflow Star/Unstar
//   canShowMessageInfo       — overflow "Message info" (1 selected)
//   canReport                 — overflow Report — false until a real
//                              report-message backend exists
//   canAddToMemories         — overflow "Add to Memories" — false until
//                              a real memory-vault-from-chat flow exists
//   supportsAttachments      — composer attach button
//   supportsVoice             — composer mic button
//   supportsPoll             — composer poll button
//   supportsGifAndStickers   — composer emoji-panel GIF + Stickers tabs
//   supportsMentions          — composer @ mention picker
//   showsPinnedBar            — mount PinnedMessagesBar above the list
//
// Message-dependent rules (methods so they can read ChatMessage fields):
//   canEdit(m)               — own text messages, group only
//   canDeleteForMe(m)         — group: any non-deleted-for-everyone row;
//                              direct: false at the capability level
//                              (the selection bar special-cases own
//                              failed messages in direct chat)
//   canDeleteForEveryone(m)  — own messages, group only
//   canPin(m)                — admin / family creator, group only
//
// `hasAnySelectableAction(m)` returns true if the row has at least one
// action available — used to decide whether long-press enters selection
// mode (it does NOT for rows with zero actions, e.g. a direct-chat
// game invite).

import '../../providers/chat_provider.dart';
import 'package:flutter/foundation.dart';

@immutable
class ChatCapabilities {
  final bool isDirect;
  final String currentUserId;
  final bool isAdminOrCreator;

  final bool canReply;
  final bool canReact;
  final bool canCopy;
  final bool canShareOutside;
  final bool canForward;
  final bool canStar;
  final bool canShowMessageInfo;
  final bool canReport;
  final bool canAddToMemories;
  final bool supportsAttachments;
  final bool supportsVoice;
  final bool supportsPoll;
  final bool supportsGifAndStickers;
  final bool supportsMentions;
  final bool showsPinnedBar;

  const ChatCapabilities({
    required this.isDirect,
    required this.currentUserId,
    this.isAdminOrCreator = false,
    required this.canReply,
    required this.canReact,
    required this.canCopy,
    required this.canShareOutside,
    required this.canForward,
    required this.canStar,
    required this.canShowMessageInfo,
    required this.canReport,
    required this.canAddToMemories,
    required this.supportsAttachments,
    required this.supportsVoice,
    required this.supportsPoll,
    required this.supportsGifAndStickers,
    required this.supportsMentions,
    required this.showsPinnedBar,
  });

  /// Group chat capabilities. Everything the group chat supports today.
  ///
  /// [isAdminOrCreator] gates the Pin action (existing rule: admin or
  /// family creator only).
  factory ChatCapabilities.group({
    required String currentUserId,
    required bool isAdminOrCreator,
  }) {
    return ChatCapabilities(
      isDirect: false,
      currentUserId: currentUserId,
      isAdminOrCreator: isAdminOrCreator,
      canReply: true,
      canReact: true,
      canCopy: true,
      canShareOutside: true,
      canForward: true,
      canStar: true,
      canShowMessageInfo: true,
      // No "report message" feature exists in the codebase today.
      // Set to false and listed in the report. When a real report flow
      // (moderation queue, etc.) lands, flip this and wire the action.
      canReport: false,
      // No "add chat message to memories" flow exists today.
      // Set to false and listed in the report.
      canAddToMemories: false,
      supportsAttachments: true,
      supportsVoice: true,
      supportsPoll: true,
      supportsGifAndStickers: true,
      supportsMentions: true,
      showsPinnedBar: true,
    );
  }

  /// Direct chat capabilities. Reply + React + Copy + Share outside only.
  /// Everything else is false — no forward, edit, delete (except the
  /// own-failed-message exception handled by the selection bar), star,
  /// pin, message info, report, memories, attachments, voice, poll,
  /// gif, stickers, mentions, pinned bar.
  factory ChatCapabilities.direct({required String currentUserId}) {
    return ChatCapabilities(
      isDirect: true,
      currentUserId: currentUserId,
      isAdminOrCreator: false,
      canReply: true,
      canReact: true,
      canCopy: true,
      canShareOutside: true,
      canForward: false,
      canStar: false,
      canShowMessageInfo: false,
      canReport: false,
      canAddToMemories: false,
      supportsAttachments: false,
      supportsVoice: false,
      supportsPoll: false,
      supportsGifAndStickers: false,
      supportsMentions: false,
      showsPinnedBar: false,
    );
  }

  // ── Message-dependent rules ────────────────────────────────────────

  /// Edit only the user's own text messages, group only.
  /// Keeps the existing rule from the old `_showMessageActions` sheet.
  bool canEdit(ChatMessage m) {
    if (isDirect) return false;
    if (m.senderId != currentUserId) return false;
    if (m.messageType != MessageType.text) return false;
    if (m.isDeletedForEveryone) return false;
    return true;
  }

  /// "Delete for me" — group: any non-deleted-for-everyone row.
  /// Direct chat returns false at the capability level; the selection
  /// bar still offers Delete when EVERY selected message is an own
  /// failed one (see `ChatSelectionBar.canDeleteSelection`).
  bool canDeleteForMe(ChatMessage m) {
    if (isDirect) return false;
    if (m.isDeletedForEveryone) return false;
    return true;
  }

  /// "Delete for everyone" — own messages, group only.
  bool canDeleteForEveryone(ChatMessage m) {
    if (isDirect) return false;
    if (m.senderId != currentUserId) return false;
    if (m.isDeletedForEveryone) return false;
    return true;
  }

  /// Pin — admin or family creator, group only.
  bool canPin(ChatMessage m) {
    if (isDirect) return false;
    if (!isAdminOrCreator) return false;
    if (m.isDeletedForEveryone) return false;
    // System events cannot be pinned (no meaningful content).
    if (m.messageType == MessageType.familyEvent) return false;
    return true;
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// True when the row has at least one selectable action.
  /// Used by the long-press handler to decide whether to enter selection
  /// mode. A direct-chat game invite, for instance, has no actions
  /// (no reply, no react in DM game invites, no copy/forward/etc.) so
  /// long-pressing it should NOT enter selection mode — it just gives
  /// a light haptic.
  ///
  /// The own-failed-message exception is handled here: a failed message
  /// always has at least Retry + Delete so it IS selectable.
  bool hasAnySelectableAction(ChatMessage m) {
    if (_isOwnFailed(m)) return true;
    if (canReply) return true;
    if (canReact) return true;
    if (canCopy && m.content.isNotEmpty) return true;
    if (canShareOutside && (m.content.isNotEmpty || m.mediaUrl != null)) return true;
    if (canForward && _isForwardable(m)) return true;
    if (canEdit(m)) return true;
    if (canDeleteForMe(m)) return true;
    if (canDeleteForEveryone(m)) return true;
    if (canStar) return true;
    if (canPin(m)) return true;
    if (canShowMessageInfo) return true;
    if (canReport) return true;
    if (canAddToMemories) return true;
    return false;
  }

  /// Own failed message: senderId is me AND status is 'failed'.
  bool _isOwnFailed(ChatMessage m) {
    return m.senderId == currentUserId && m.messageStatus == 'failed';
  }

  /// Forwardable: not deleted, not a system event, not a game invite
  /// (game invites are tied to a room and can't be replayed elsewhere).
  bool _isForwardable(ChatMessage m) {
    if (m.isDeletedForEveryone) return false;
    if (m.messageType == MessageType.familyEvent) return false;
    if (m.messageType == MessageType.gameInvite) return false;
    return true;
  }

  /// True for date separators / system events / typing indicator rows
  /// (not selectable). We treat familyEvent + gameInvite as user content
  /// — only the row kinds explicitly drawn by the list as "system" rows
  /// (date headers, typing indicator) are excluded; here we approximate
  /// by excluding any ChatMessage whose messageType is familyEvent AND
  /// whose content is empty (a pure event row).
  ///
  /// Note: this is called by the list on every message to decide whether
  /// to render the long-press overlay; it must be fast.
  bool isSystemRow(ChatMessage m) {
    return m.messageType == MessageType.familyEvent && m.content.trim().isEmpty;
  }
}
