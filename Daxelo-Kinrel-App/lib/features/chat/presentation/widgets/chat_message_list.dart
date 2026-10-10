// lib/features/chat/presentation/widgets/chat_message_list.dart
//
// DAXELO KINREL — Shared chat message list (group + DM)
//
// The reversed ListView that renders chat messages with date separators,
// sender-grouping (first/last in group), SwipeToReply wrapping, and a
// RepaintBoundary per bubble. EXTRACTED (moved, not rewritten) from
// chat_screen.dart's _buildMessagesList so the DM screen can render
// the SAME list with the same scroll/cache/repaint behavior.
//
// Inputs:
//   - messages: newest-first List<ChatMessage> (the same shape both
//     chat_provider and the DM adapter produce).
//   - currentUserId: used to compute isMe per message.
//   - familyId: nullable. Group chat passes the family id (enables the
//     relationship label + group chatProvider actions). DM passes null
//     (skips the relationship label + group-only actions).
//   - isDirectChat: passed through to MessageBubble (hides avatar +
//     sender name in DMs).
//   - inviteFamilyId: passed through to MessageBubble (DM game invites
//     pass the host's family id from the payload so the Join button
//     works; group passes null and lets the bubble fall back to
//     familyId).
//   - scrollController: the screen's ScrollController (the screen owns
//     it for scroll-to-bottom / scroll-FAB logic).
//   - onReply / onReact / onLongPress / onReplyPreviewTap: per-message
//     callbacks (the screen wires these to its own state/providers).
//   - onRetryFailed / onDeleteFailed: per-message failed-send actions
//     (the group passes null — MessageBubble falls back to its built-in
//     chatProvider calls; the DM passes its own provider's methods so
//     the SAME failed-message sheet works in both chat types).
//   - onLoadOlder: optional callback when the user scrolls to the top
//     (the group chat wires this to loadOlderMessages; DM passes null
//     since the DM provider doesn't paginate).
//   - enableSwipeReply: when false, the SwipeToReply wrapper is
//     skipped. v3.4: BOTH chat types now pass true — the DM table
//     persists reply columns (migration 20261007080000), so the group
//     and the DM share the SAME swipe-to-reply behavior.
//   - showReactions: when false, the onReact callback is not invoked
//     (DM passes false — the DM backend doesn't support reactions yet;
//     next parity pass will add a DM reactions table).
//
// What was MOVED vs KEPT in chat_screen.dart:
//   - MOVED: the ListView.builder, date grouping, first/last-in-group
//     computation, SwipeToReply wrapping, RepaintBoundary per bubble,
//     MessageBubble construction, date separator pill rendering.
//   - KEPT in chat_screen.dart: the typing indicator, scroll-to-bottom
//     FAB, and unread-count logic. These are tightly coupled to the
//     group chat's engagement provider + scroll controller state and
//     would risk regressions if moved. They live ABOVE the message list
//     in the group chat's Column; the DM screen has its own (simpler)
//     equivalents and doesn't need them.
//
// The group chat calls this widget with enableSwipeReply=true,
// showReactions=true, and all callbacks wired — so the group chat
// behaves EXACTLY as before. v3.4: the DM now ALSO passes
// enableSwipeReply=true (with onReply wired to its own setReplyTo) —
// the same wrapper, the same drag physics, in both chat types.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/theme/kinrel_fx.dart';
import '../../../../core/utils/app_time.dart';
import '../../providers/chat_provider.dart';
import 'chat_meta.dart';
import 'message_bubble.dart';
import 'chat_system_notice.dart';

/// A single date group (label + the messages for that day). The class
/// DateGroup already exists in chat_meta.dart; we just use it directly.

class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.currentUserId,
    this.familyId,
    this.isDirectChat = false,
    this.inviteFamilyId,
    required this.scrollController,
    required this.onReply,
    required this.onReact,
    required this.onLongPress,
    this.onReplyPreviewTap,
    this.onLoadOlder,
    this.enableSwipeReply = true,
    this.showReactions = true,
    /// v3.5 — failed-send actions (null = the group's built-in
    /// chatProvider retry/delete; the DM passes its own provider's).
    this.onRetryFailed,
    this.onDeleteFailed,
  });

  /// Newest-first list of messages (the same shape chat_provider and
  /// the DM adapter produce).
  final List<ChatMessage> messages;

  /// The current user's id — used to compute isMe per message.
  final String? currentUserId;

  /// Family id for the group chat (enables relationship label + group
  /// chatProvider actions). Null for DMs.
  final String? familyId;

  /// True when rendering inside a DM (hides avatar + sender name).
  final bool isDirectChat;

  /// The family id to use for game-invite Join/Spectate routes (DM
  /// invites pass the host's family id from the payload). Null for the
  /// group chat (the bubble falls back to familyId).
  final String? inviteFamilyId;

  /// The screen's ScrollController (the screen owns it for scroll-to-
  /// bottom / scroll-FAB logic).
  final ScrollController scrollController;

  /// Per-message reply callback (the screen wires this to setReplyTo).
  final void Function(ChatMessage message) onReply;

  /// Per-message react callback (the screen shows its reaction picker).
  final void Function(ChatMessage message) onReact;

  /// Per-message long-press callback (the screen shows its action sheet).
  final void Function(ChatMessage message) onLongPress;

  /// Per-message reply-preview-tap callback (scroll to the original
  /// message). Null = no tap handler.
  final void Function(ChatMessage message)? onReplyPreviewTap;

  /// Optional scroll-to-top callback (group chat wires loadOlderMessages;
  /// DM passes null).
  final VoidCallback? onLoadOlder;

  /// When false, the SwipeToReply wrapper is skipped (legacy flag —
  /// both chat types now pass true; kept for API stability).
  final bool enableSwipeReply;

  /// When false, the onReact callback is not invoked (legacy flag —
  /// v3.5: BOTH chat types now pass true; the DM reactions table exists
  /// (migration 20261007100000) and DirectChatNotifier.toggleReaction
  /// implements the group's exact optimistic + realtime flow).
  final bool showReactions;

  /// v3.5 — Retry a failed message (the failed-message sheet's Retry
  /// action). Null = the group path (chatProvider.retryMessage).
  final void Function(String messageId)? onRetryFailed;

  /// v3.5 — Delete a failed message (the failed-message sheet's Delete
  /// action). Null = the group path (chatProvider.deleteFailedMessage).
  final void Function(String messageId)? onDeleteFailed;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  // ── Phase 2 / memoization ───────────────────────────────────────
  // Cache the date grouping so it doesn't re-run on every rebuild. The
  // cache key is the IDENTITY of the messages list (chat_provider's
  // ChatState.messages is immutable — any state change creates a fresh
  // List, so identical() is a perfect invalidation signal). MOVED
  // verbatim from chat_screen.dart's _groupedCache.
  List<DateGroup> _groupedCache = const [];
  List<ChatMessage>? _groupedCacheKey;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(widget.messages);

    // v130: Bottom padding reserves space for the scroll-to-bottom FAB
    // (40px tall, 8px from bottom = 48px footprint) plus a 16px buffer
    // so the most recent message is never obscured by the FAB. In a
    // reversed ListView, padding.bottom is applied at the visual bottom.
    const fabClearance = 64.0;

    return ListView.builder(
      controller: widget.scrollController,
      // reverse: true means the visual BOTTOM of the viewport shows
      // index 0 (the newest message) and scrolling UP increases the
      // scroll offset (toward older messages at the end of the list).
      // This eliminates the need for a post-render scroll-to-bottom
      // animation on screen entry — the list naturally opens at offset
      // 0 = the most recent message, exactly like WhatsApp.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, fabClearance),
      itemCount: grouped.length,
      // PERF (Tier K4): cacheExtent reduced from 1500 → 800.
      // 1500px kept ~2 screens of offscreen content alive in the render
      // tree. On the invite-list screen with 10+ game-invite cards
      // stacked vertically, this meant ~10-22 bubble subtrees were
      // simultaneously mounted (each with its own GameIcon Image.asset
      // + status chip + decoration). Reducing to 800px (~1 screen of
      // headroom) halves the steady-state render-tree size without
      // visible scroll pop-in for typical message heights (~80-120px).
      // Saves ~5-10 ms/frame on the invite-list screen by reducing
      // the number of concurrently-cached GPU textures and painter
      // allocations.
      cacheExtent: 800,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          children: [
            // Date separator pill
            _buildDateSeparator(group.dateLabel),
            const SizedBox(height: 8),
            // Messages for this date — with sender grouping
            ...group.messages.asMap().entries.map((entry) {
              final i = entry.key;
              final msg = entry.value;
              final isMe = msg.senderId == widget.currentUserId;

              // isFirstInGroup: first message OR previous message is
              // from a different sender OR >60s gap.
              final isFirstInGroup = i == 0 ||
                  group.messages[i - 1].senderId != msg.senderId ||
                  msg.timestamp
                      .difference(group.messages[i - 1].timestamp)
                      .inSeconds
                      .abs() > 60;

              // isLastInGroup: last message OR next message is from a
              // different sender OR >60s gap.
              final isLastInGroup = i == group.messages.length - 1 ||
                  group.messages[i + 1].senderId != msg.senderId ||
                  group.messages[i + 1].timestamp
                      .difference(msg.timestamp)
                      .inSeconds
                      .abs() > 60;

              // Tighter spacing within groups (2px) vs between groups (8px).
              final bottomPadding = isLastInGroup ? 8.0 : 2.0;

              // System notices (join notices, etc.) render as a centered
              // muted pill instead of a normal message bubble. No sender
              // label, no avatar, no bubble, no rail, no ticks, no reactions,
              // no reply, no swipe, not selectable. Breaks message clustering.
              if (msg.messageType == MessageType.system) {
                final notice = ChatSystemNotice(content: msg.content);
                return Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  child: notice,
                );
              }

              final bubble = MessageBubble(
                message: msg,
                isMe: isMe,
                familyId: widget.familyId,
                isDirectChat: widget.isDirectChat,
                inviteFamilyId: widget.inviteFamilyId,
                isFirstInGroup: isFirstInGroup,
                isLastInGroup: isLastInGroup,
                onReply: () => widget.onReply(msg),
                onReact: widget.showReactions ? () => widget.onReact(msg) : () {},
                onLongPress: () => widget.onLongPress(msg),
                onReplyPreviewTap: msg.replyToId != null && widget.onReplyPreviewTap != null
                    ? () => widget.onReplyPreviewTap!(msg)
                    : null,
                // v3.5 — failed-send seam (null = group's built-in path).
                onRetryFailed: widget.onRetryFailed,
                onDeleteFailed: widget.onDeleteFailed,
              );

              // RepaintBoundary per bubble so a single new/updated
              // message doesn't trigger a repaint of the entire visible
              // list. MOVED verbatim from chat_screen.dart.
              final bounded = RepaintBoundary(child: bubble);

              // SwipeToReply wrapper — v3.4: BOTH the group chat and
              // the DM wrap every bubble (the DM table persists reply
              // columns now, so swipe-to-reply works identically in
              // both chat types).
              final wrapped = widget.enableSwipeReply
                  ? SwipeToReply(
                      key: ValueKey(msg.id),
                      messageId: msg.id,
                      isMe: isMe,
                      onReply: () => widget.onReply(msg),
                      child: bounded,
                    )
                  : bounded;

              return Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: wrapped,
              );
            }),
          ],
        );
      },
    );
  }

  /// Date separator pill — MOVED verbatim from chat_screen.dart's
  /// _buildDateSeparator. Frosted-glass pill with the day label.
  Widget _buildDateSeparator(String label) {
    return RepaintBoundary(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF13141E).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
            // PERF (Flat): no shadow in flat mode. The 0.5px hairline
            // border already provides separation against the wallpaper.
            boxShadow: KinrelFx.shadows([
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver.withValues(alpha: 0.9),
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  /// Group messages by date — MOVED verbatim from chat_screen.dart's
  /// _groupByDate (O(n) algorithm with O(1) label lookups via a Map
  /// index, plus identity-based memoization so it doesn't re-run on
  /// every rebuild).
  List<DateGroup> _groupByDate(List<ChatMessage> messages) {
    // ── Phase 2 / memoization ───────────────────────────────────────
    // Return the cached grouping if the input list is the same instance
    // as last time. chat_provider's ChatState.messages is immutable —
    // any state change creates a fresh List, so identical() comparison
    // is a perfect invalidation signal (O(1), no false hits).
    if (identical(_groupedCacheKey, messages)) {
      return _groupedCache;
    }

    final orderedLabels = <String>[];
    final byLabel = <String, DateGroup>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final msg in messages) {
      // Convert the server-returned UTC timestamp to the viewer's
      // device-local timezone before extracting year/month/day.
      final local = AppTime.toLocalDisplay(msg.timestamp);
      final msgDate = DateTime(local.year, local.month, local.day);

      String label;
      if (msgDate == today) {
        label = 'Today';
      } else if (msgDate == yesterday) {
        label = 'Yesterday';
      } else {
        const months = [
          '',
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        label = '${months[local.month]} ${local.day}, ${local.year}';
      }

      final existing = byLabel[label];
      if (existing != null) {
        existing.messages.add(msg);
      } else {
        final g = DateGroup(dateLabel: label, messages: [msg]);
        byLabel[label] = g;
        orderedLabels.add(label);
      }
    }

    final groups = <DateGroup>[];
    for (final label in orderedLabels) {
      groups.add(byLabel[label]!);
    }

    // Within each date group, sort messages ascending (oldest first,
    // newest last) so they render top-to-bottom correctly inside that
    // day's Column. The day-groups themselves remain in descending
    // order (newest day first) for correct placement in the reversed
    // ListView — only the intra-day order is fixed here.
    for (final g in groups) {
      g.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    // Cache the result for next time.
    _groupedCacheKey = messages;
    _groupedCache = groups;
    return groups;
  }
}
