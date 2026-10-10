// lib/features/chat/presentation/widgets/chat_message_list.dart
//
// DAXELO KINREL — Shared chat message list (group + DM + direct group)
//
// The reversed ListView that renders chat messages with date separators,
// sender-grouping (first/last in group), SwipeToReply wrapping, and a
// RepaintBoundary per bubble. EXTRACTED (moved, not rewritten) from
// chat_screen.dart's _buildMessagesList so every chat type renders the
// SAME list with the same scroll/cache/repaint behavior.
//
// Kin Thread additions (one shared implementation, both chat types):
//   • System notices (MessageType.system) render as centered
//     ChatSystemNotice pills — never bubbles — and BREAK clustering:
//     a system row always starts a new cluster for the next message.
//   • Floating date chip while scrolling (FloatingDateIndicator).
//   • Unread divider (PR2 Task 3): a centered "N unread messages" pill
//     above the FIRST unread message, captured before read-marking,
//     scrolled into view on open, persistent until the chat closes.
//   • Terminal game invites collapse (PR2 Task 5): 3+ consecutive
//     expired/completed invites render as one "N game invites ·
//     expired" row with an expand control (CollapsedGameInvites).
//
// Inputs:
//   - messages: newest-first List<ChatMessage> (the same shape both
//     chat_provider and the DM adapter produce).
//   - currentUserId: used to compute isMe per message.
//   - familyId: nullable. Group chat passes the family id (enables the
//     relationship label + group chatProvider actions + "View in tree"
//     on system notices). DM passes null (skips the relationship label
//     + group-only actions).
//   - isDirectChat: passed through to MessageBubble (hides avatar +
//     sender name in DMs).
//   - inviteFamilyId: passed through to MessageBubble (DM game invites
//     pass the host's family id from the payload so the Join button
//     works; group passes null and lets the bubble fall back to
//     familyId).
//   - unreadDividerMessageId / unreadDividerCount: the snapshot
//     captured by the provider BEFORE messages were marked read.
//   - scrollController: the screen's ScrollController (the screen owns
//     it for scroll-to-bottom / scroll-FAB logic).
//   - onReply / onReact / onLongPress / onReplyPreviewTap: per-message
//     callbacks (the screen wires these to its own state/providers).
//   - onRetryFailed / onDeleteFailed: per-message failed-send actions.
//   - onLoadOlder: optional callback when the user scrolls to the top.
//   - enableSwipeReply / showReactions: legacy capability flags.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/theme/kinrel_fx.dart';
import '../../../../core/utils/app_time.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../graph/interaction/graph_focus_state.dart';
import '../../providers/chat_provider.dart';
import 'chat_meta.dart';
import 'message_bubble.dart';
import 'chat_system_notice.dart';
import 'floating_date_indicator.dart';
import 'game_invite_card.dart';

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
    this.unreadDividerMessageId,
    this.unreadDividerCount = 0,
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
    /// v6.0 — Selection mode state (Image 3 reference).
    this.selectionMode = false,
    this.selectedMessageIds = const <String>{},
    this.onToggleSelection,
  });

  /// Newest-first list of messages (the same shape chat_provider and
  /// the DM adapter produce).
  final List<ChatMessage> messages;

  /// The current user's id — used to compute isMe per message.
  final String? currentUserId;

  /// Family id for the group chat (enables relationship label + group
  /// chatProvider actions + "View in tree" on system notices). Null for
  /// DMs.
  final String? familyId;

  /// True when rendering inside a DM (hides avatar + sender name).
  final bool isDirectChat;

  /// The family id to use for game-invite Join/Spectate routes (DM
  /// invites pass the host's family id from the payload). Null for the
  /// group chat (the bubble falls back to familyId).
  final String? inviteFamilyId;

  /// Kin Thread / PR2 Task 3 — id of the first unread message (the
  /// unread divider pill renders above it). Null = no divider.
  final String? unreadDividerMessageId;

  /// Kin Thread / PR2 Task 3 — unread count shown on the divider pill.
  final int unreadDividerCount;

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

  /// When false, the onReact callback is not invoked (legacy flag).
  final bool showReactions;

  /// v3.5 — Retry a failed message (the failed-message sheet's Retry
  /// action). Null = the group path (chatProvider.retryMessage).
  final void Function(String messageId)? onRetryFailed;

  /// v3.5 — Delete a failed message (the failed-message sheet's Delete
  /// action). Null = the group path (chatProvider.deleteFailedMessage).
  final void Function(String messageId)? onDeleteFailed;

  /// v6.0 — When true, bubbles render in selection mode (checkbox +
  /// ring). Tapping a bubble toggles selection instead of opening the
  /// action sheet.
  final bool selectionMode;

  /// v6.0 — The set of currently selected message ids. Bubbles whose
  /// id is in this set render as selected (orange ring + filled checkbox).
  final Set<String> selectedMessageIds;

  /// v6.0 — Callback to toggle a message's selection state.
  final void Function(String messageId)? onToggleSelection;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  // ── Phase 2 / memoization ───────────────────────────────────────
  // Cache the date grouping so it doesn't re-run on every rebuild. The
  // cache key is the IDENTITY of the messages list (chat_provider's
  // ChatState.messages is immutable — any state change creates a fresh
  // List, so identical() is a perfect invalidation signal).
  List<DateGroup> _groupedCache = const [];
  List<ChatMessage>? _groupedCacheKey;

  // Key on the ListView so the floating date chip can find the rendered
  // sliver children cheaply (see FloatingDateIndicator).
  final GlobalKey _listViewKey = GlobalKey();

  // Key on the unread divider pill so the list can scroll it into view
  // on open (Scrollable.ensureVisible).
  final GlobalKey _unreadDividerKey = GlobalKey();
  bool _scrolledToUnreadDivider = false;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(widget.messages);

    // v130: Bottom padding reserves space for the scroll-to-bottom FAB
    // (40px tall, 8px from bottom = 48px footprint) plus a 16px buffer
    // so the most recent message is never obscured by the FAB. In a
    // reversed ListView, padding.bottom is applied at the visual bottom.
    const fabClearance = 64.0;

    return Stack(
      children: [
        ListView.builder(
      key: _listViewKey,
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
      // tree. Reducing to 800px (~1 screen of headroom) halves the
      // steady-state render-tree size without visible scroll pop-in for
      // typical message heights (~80-120px).
      cacheExtent: 800,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          children: [
            // Date separator pill
            _buildDateSeparator(group.dateLabel),
            const SizedBox(height: 8),
            // Messages for this date — with sender grouping, system
            // notice short-circuit, unread divider, and terminal invite
            // collapse. Index-based loop so runs can be collapsed.
            ..._buildGroupRows(group),
          ],
        );
      },
        ), // close ListView.builder
        // Floating date indicator overlay — shows the date of the
        // topmost visible message while scrolling, fades out ~1.2s
        // after scrolling stops. Same styling as the inline separator.
        FloatingDateIndicator(
          scrollController: widget.scrollController,
          listViewKey: _listViewKey,
          itemCount: grouped.length,
          dateLabelForIndex: (index) =>
              index >= 0 && index < grouped.length
                  ? grouped[index].dateLabel
                  : null,
        ),
      ], // close Stack children
    ); // close Stack
  }

  // ── Row building (per date group) ─────────────────────────────────

  /// Builds the message rows for one date group. Handles:
  ///   • collapsing runs of 3+ consecutive terminal game invites,
  ///   • system notice rows (no bubble, break clustering),
  ///   • the unread divider pill above the first unread message,
  ///   • normal bubbles with first/last-in-group flags.
  List<Widget> _buildGroupRows(DateGroup group) {
    final msgs = group.messages;
    final rows = <Widget>[];
    var i = 0;
    while (i < msgs.length) {
      final msg = msgs[i];

      // ── Collapsed invite run (PR2 Task 5) ──────────────────────────
      // Three or more CONSECUTIVE expired/completed invites collapse
      // into one quiet row with an expand control.
      if (_isTerminalInvite(msg) &&
          i + 2 < msgs.length &&
          _isTerminalInvite(msgs[i + 1]) &&
          _isTerminalInvite(msgs[i + 2])) {
        final run = <ChatMessage>[msg];
        var j = i + 1;
        while (j < msgs.length && _isTerminalInvite(msgs[j])) {
          run.add(msgs[j]);
          j++;
        }
        rows.add(CollapsedGameInvites(
          messages: run,
          isMe: msg.senderId == widget.currentUserId,
          routeFamilyId: widget.inviteFamilyId ?? widget.familyId,
        ));
        i = j;
        continue;
      }

      final isMe = msg.senderId == widget.currentUserId;

      // ── System notice (PR 1): no bubble, breaks clustering ─────────
      if (msg.messageType == MessageType.system) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChatSystemNotice(
            content: msg.content,
            onViewInTree:
                widget.familyId != null && !widget.isDirectChat
                    ? () => _openGraphFocusedOnMember(msg)
                    : null,
          ),
        ));
        i++;
        continue;
      }

      // ── Clustering flags (with system-row breaks) ─────────────────
      // Same sender AND ≤60s gap continues a cluster. A system notice
      // ALWAYS breaks the cluster on both sides, so the message after a
      // join notice starts a fresh cluster (its sender name shows).
      final prev = i > 0 ? msgs[i - 1] : null;
      final next = i < msgs.length - 1 ? msgs[i + 1] : null;
      final bool isFirstInGroup = _clusterBreakBefore(msg, prev);
      final bool isLastInGroup = _clusterBreakAfter(msg, next);

      // Tighter spacing within groups (2px) vs between groups (8px).
      final bottomPadding = isLastInGroup ? 8.0 : 2.0;

      // ── Unread divider (PR2 Task 3) ───────────────────────────────
      // Rendered above the first unread message; persists until the
      // chat is closed (the id comes from the provider's snapshot).
      final showUnreadDivider =
          widget.unreadDividerMessageId == msg.id &&
              widget.unreadDividerCount > 0;
      if (showUnreadDivider) {
        rows.add(_buildUnreadDivider());
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
        // v6.0 — Selection mode state (Image 3 reference).
        selectionMode: widget.selectionMode,
        isSelected: widget.selectedMessageIds.contains(msg.id),
        onToggleSelection: widget.onToggleSelection != null
            ? () => widget.onToggleSelection!(msg.id)
            : null,
      );

      // RepaintBoundary per bubble so a single new/updated
      // message doesn't trigger a repaint of the entire visible
      // list. MOVED verbatim from chat_screen.dart.
      final bounded = RepaintBoundary(child: bubble);

      // SwipeToReply wrapper — v3.4: BOTH the group chat and
      // the DM wrap every bubble (the DM table persists reply
      // columns now, so swipe-to-reply works identically in
      // both chat types).
      // v6.0 — Skip SwipeToReply in selection mode so taps don't
      // conflict with the selection toggle gesture.
      final wrapped = widget.enableSwipeReply && !widget.selectionMode
          ? SwipeToReply(
              key: ValueKey(msg.id),
              messageId: msg.id,
              isMe: isMe,
              onReply: () => widget.onReply(msg),
              child: bounded,
            )
          : bounded;

      rows.add(Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: wrapped,
      ));
      i++;
    }
    return rows;
  }

  /// Whether the cluster breaks between [prev] and [msg] (different
  /// sender, >60s gap, or the previous row is a system notice).
  bool _clusterBreakBefore(ChatMessage msg, ChatMessage? prev) {
    if (prev == null) return true;
    if (prev.messageType == MessageType.system) return true;
    return prev.senderId != msg.senderId ||
        msg.timestamp.difference(prev.timestamp).inSeconds.abs() > 60;
  }

  /// Whether the cluster breaks between [msg] and [next] (different
  /// sender, >60s gap, or the next row is a system notice).
  bool _clusterBreakAfter(ChatMessage msg, ChatMessage? next) {
    if (next == null) return true;
    if (next.messageType == MessageType.system) return true;
    return next.senderId != msg.senderId ||
        next.timestamp.difference(msg.timestamp).inSeconds.abs() > 60;
  }

  /// A terminal game invite (expired / cancelled / completed).
  bool _isTerminalInvite(ChatMessage msg) {
    if (msg.messageType != MessageType.gameInvite) return false;
    final s = msg.gameInviteStatus ?? 'pending';
    return s == 'expired' || s == 'cancelled' || s == 'completed';
  }

  // ── Unread divider pill (PR2 Task 3) ──────────────────────────────

  Widget _buildUnreadDivider() {
    final count = widget.unreadDividerCount;
    return RepaintBoundary(
      key: _unreadDividerKey,
      child: Semantics(
        label: '$count unread messages',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 12,
                    color: KinrelColors.orange,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$count unread message${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── View in tree (PR 1c) ──────────────────────────────────────────

  /// Opens the family graph focused on the member who joined (the
  /// system notice's senderId). No route/parameter exists today to
  /// open the graph focused on a person, so this resolves the sender's
  /// Person id from the cached family detail, focuses the (global)
  /// graphFocusProvider — which the graph nodes watch — and then opens
  /// the graph route. If the person can't be resolved, the graph still
  /// opens (unfocused). No graph code is modified.
  void _openGraphFocusedOnMember(ChatMessage msg) {
    final famId = widget.familyId;
    if (famId == null) return;
    try {
      final detail =
          ref.read(familyDetailProvider(famId)).valueOrNull;
      if (detail != null) {
        String? personId;
        String? personName;
        for (final p in detail.members) {
          if (p.linkedUserId == msg.senderId) {
            personId = p.id;
            personName = p.name;
            break;
          }
        }
        if (personId != null && personId.isNotEmpty) {
          ref.read(graphFocusProvider.notifier).focus(
                personId: personId,
                personName: personName ?? msg.senderName,
                edges: const [],
              );
        }
      }
    } catch (_) {
      // Best-effort focus — if it fails, still open the graph.
    }
    context.go('/family/$famId/graph?tab=tree');
  }

  // ── Scroll the unread divider into view on open (PR2 Task 3) ──────

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScrollToUnreadDivider();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScrollToUnreadDivider();
  }

  void _maybeScrollToUnreadDivider() {
    if (_scrolledToUnreadDivider) return;
    if (widget.unreadDividerMessageId == null ||
        widget.unreadDividerCount <= 0) {
      return;
    }
    // The divider must actually be built before it can be scrolled to.
    final hasDivider = widget.messages
        .any((m) => m.id == widget.unreadDividerMessageId);
    if (!hasDivider) return;
    _scrolledToUnreadDivider = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _unreadDividerKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
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
  ///
  /// Kin Thread label format (unified for separators AND the floating
  /// date chip): Today / Yesterday / weekday name within 6 days /
  /// otherwise "Month D, YYYY".
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

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    for (final msg in messages) {
      // Convert the server-returned UTC timestamp to the viewer's
      // device-local timezone before extracting year/month/day.
      final local = AppTime.toLocalDisplay(msg.timestamp);
      final msgDate = DateTime(local.year, local.month, local.day);

      String label;
      final daysAgo = today.difference(msgDate).inDays;
      if (msgDate == today) {
        label = 'Today';
      } else if (msgDate == yesterday) {
        label = 'Yesterday';
      } else if (daysAgo >= 2 && daysAgo <= 6) {
        // Weekday name within 6 days (matches the Kin Thread mockups:
        // "Monday"), same format the floating date chip shows.
        label = weekdays[local.weekday - 1];
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
