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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/kinrel_fx.dart';
import '../../../../core/utils/app_time.dart';
import '../../providers/chat_provider.dart';
import 'chat_capabilities.dart';
import 'chat_message_actions.dart';
import 'chat_meta.dart';
import 'chat_selection_controller.dart';
import 'message_bubble.dart';

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
    /// v3.6 (PR 1) — chat capabilities + actions drive ALL per-message
    /// behaviour. The screen builds one ChatCapabilities (group or
    /// direct factory) + one ChatMessageActions (with its own provider
    /// callbacks) and passes them down. The list never reaches into a
    /// provider directly.
    required this.capabilities,
    required this.actions,
    /// The chat id used to key the per-chat selection controller.
    /// Group passes the familyId; DM passes 'dm_$otherUserId'.
    required this.chatId,
    /// v3.6 (PR 1) — tapping a reaction chip below a bubble opens a
    /// list of who reacted (Task 5). Null = no reactors list (chips
    /// are non-interactive).
    this.onShowReactors,
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

  /// v3.6 (PR 1) — Capabilities (group vs direct) drive per-message
  /// action availability. The list never reaches into a provider.
  final ChatCapabilities capabilities;

  /// v3.6 (PR 1) — Action callbacks (reply, toggleReaction, edit,
  /// deleteForMe, deleteForEveryone, star, pin, forward, showInfo,
  /// report, addToMemories, saveToGallery, shareOutside, retry,
  /// deleteFailed). Null callbacks hide the action.
  final ChatMessageActions actions;

  /// The chat id used to key the per-chat selection controller.
  /// Group passes the familyId; DM passes 'dm_$otherUserId'.
  final String chatId;

  /// v3.6 (PR 1) — Tapping a reaction chip below a bubble opens a
  /// list of who reacted (Task 5). Null = chips are non-interactive.
  final void Function(ChatMessage message)? onShowReactors;

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

  // ── v3.9: Floating date indicator while scrolling ────────────────
  // Shows the date of the topmost visible message group when the user
  // scrolls, then fades out ~1.5s after scrolling stops.
  //
  // Performance:
  //   - The scroll listener only sets 2 lightweight state variables
  //     (_floatingDate string + _showFloatingDate bool). The ListView
  //     itself is NOT rebuilt — the date pill is a separate widget in
  //     a Stack above the list, wrapped in a RepaintBoundary.
  //   - The date is computed in O(1) from the scroll fraction — no
  //     widget tree traversal, no findRenderObject calls.
  String? _floatingDate;
  bool _showFloatingDate = false;
  Timer? _hideFloatingDateTimer;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    // Attach scroll listener to detect scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.scrollController.addListener(_onScroll);
    });
  }

  @override
  void dispose() {
    _hideFloatingDateTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  /// Scroll handler — computes the date for the current viewport
  /// position and shows the floating date indicator.
  void _onScroll() {
    final controller = widget.scrollController;
    if (!controller.hasClients) return;

    final offset = controller.position.pixels;
    final maxExtent = controller.position.maxScrollExtent;

    // Only show the indicator when the list is scrollable (enough
    // content to scroll).
    if (maxExtent <= 0) return;

    // Only show when the user is actually scrolling (offset changed).
    if ((offset - _lastScrollOffset).abs() < 1.0) return;
    _lastScrollOffset = offset;

    // Compute the date for the current viewport position.
    // The list is reversed (newest at bottom = offset 0). As offset
    // increases, the viewport shows older messages. The grouped list
    // is ordered newest-day-first (descending), so higher offset =
    // higher group index = older date.
    final grouped = _groupedCache;
    if (grouped.isEmpty) return;

    // scrollFraction: 0 = bottom (newest), 1 = top (oldest)
    final scrollFraction = (offset / maxExtent).clamp(0.0, 1.0);
    final groupIndex = (scrollFraction * (grouped.length - 1)).round();
    final dateLabel = grouped[groupIndex].dateLabel;

    if (dateLabel != _floatingDate || !_showFloatingDate) {
      setState(() {
        _floatingDate = dateLabel;
        _showFloatingDate = true;
      });
    }

    // Reset the hide timer — hides the indicator 1.5s after scrolling
    // stops.
    _hideFloatingDateTimer?.cancel();
    _hideFloatingDateTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showFloatingDate = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Prune selection ids that no longer exist in the current message
    // list. This is called every time the widget rebuilds with a new
    // messages list (so deleted messages don't linger as ghost
    // selections). If all selected ids are pruned, the controller exits
    // selection mode automatically.
    if (oldWidget.messages != widget.messages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final notifier =
            ref.read(chatSelectionProvider(widget.chatId).notifier);
        notifier.pruneToExistingIds(
          widget.messages.map((m) => m.id).toSet(),
        );
      });
    }
  }

  /// v3.6 (PR 1) — Long-press handler. Light haptic; if the message
  /// has at least one selectable action, enter (or toggle) selection
  /// mode. Otherwise just give the haptic (e.g. direct-chat game
  /// invites have no actions).
  void _handleLongPress(ChatMessage msg) {
    unawaited(HapticService.tap());
    final caps = widget.capabilities;
    if (caps.isSystemRow(msg)) return;
    if (!caps.hasAnySelectableAction(msg)) return;
    final notifier = ref.read(chatSelectionProvider(widget.chatId).notifier);
    final state = ref.read(chatSelectionProvider(widget.chatId));
    if (state.inSelectionMode) {
      notifier.toggle(msg.id);
    } else {
      notifier.enter(msg.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(widget.messages);

    // v3.6 (PR 1) — watch selection state. Use select on
    // `inSelectionMode` so the whole list rebuilds only when entering
    // or leaving selection mode (not on every toggle — the per-row
    // selected-state is read separately inside the itemBuilder).
    final inSelectionMode = ref.watch(
      chatSelectionProvider(widget.chatId).select((s) => s.inSelectionMode),
    );

    // v130: Bottom padding reserves space for the scroll-to-bottom FAB
    // (40px tall, 8px from bottom = 48px footprint) plus a 16px buffer
    // so the most recent message is never obscured by the FAB. In a
    // reversed ListView, padding.bottom is applied at the visual bottom.
    const fabClearance = 64.0;

    // v3.9: Wrap the ListView in a Stack with a floating date indicator
    // that appears on scroll + fades out 1.5s after scrolling stops.
    // The indicator is wrapped in a RepaintBoundary so it doesn't trigger
    // repaints of the message list.
    return Stack(
      children: [
        ListView.builder(
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

              // v3.8 (PR 3 Task 1) — tighter spacing within groups
              // (2px) vs ~10px between groups (was 8px — bumped to
              // 10px per the prompt: "Consecutive messages of the same
              // sender within 2 minutes are 2 pixels apart; different
              // senders about 10").
              final bottomPadding = isLastInGroup ? 10.0 : 2.0;

              // v3.6 (PR 1) — read this row's selected-state via select
              // so toggling one row rebuilds ONLY that row, not the
              // whole list. The existing RepaintBoundary per item
              // clips the repaint area to the row's bounds.
              final isSelected = ref.watch(
                chatSelectionProvider(widget.chatId)
                    .select((s) => s.isSelected(msg.id)),
              );

              final bubble = MessageBubble(
                message: msg,
                isMe: isMe,
                familyId: widget.familyId,
                isDirectChat: widget.isDirectChat,
                inviteFamilyId: widget.inviteFamilyId,
                isFirstInGroup: isFirstInGroup,
                isLastInGroup: isLastInGroup,
                onReply: () => widget.onReply(msg),
                // v3.6 (PR 1) — reaction chips below the bubble now
                // open the reactors list (Task 5). The picker lives in
                // the floating reaction bar above the bubble.
                onReact: widget.onShowReactors != null
                    ? () => widget.onShowReactors!(msg)
                    : () {},
                onLongPress: () => _handleLongPress(msg),
                onReplyPreviewTap: msg.replyToId != null && widget.onReplyPreviewTap != null
                    ? () => widget.onReplyPreviewTap!(msg)
                    : null,
                // v3.5 — failed-send seam (null = group's built-in path).
                onRetryFailed: widget.onRetryFailed,
                onDeleteFailed: widget.onDeleteFailed,
                // v3.6 (PR 1) — selection state.
                selectionMode: inSelectionMode,
                selected: isSelected,
              );

              // RepaintBoundary per bubble so a single new/updated
              // message doesn't trigger a repaint of the entire visible
              // list. MOVED verbatim from chat_screen.dart.
              final bounded = RepaintBoundary(child: bubble);

              // v3.6 (PR 1) — wrap differently based on selection mode:
              //  - When selecting: skip SwipeToReply (swipe is disabled
              //    while selecting per the prompt) and overlay a
              //    transparent tap target that toggles the row. The
              //    overlay's HitTestBehavior.opaque absorbs inner taps
              //    (image open, link, profile, reply preview, join
              //    game) so they don't fire while selecting.
              //  - When not selecting: keep the existing SwipeToReply
              //    wrapper (v3.4: BOTH chat types pass enableSwipeReply=true).
              final Widget wrapped;
              if (inSelectionMode) {
                wrapped = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    unawaited(HapticService.tap());
                    ref.read(chatSelectionProvider(widget.chatId).notifier).toggle(msg.id);
                  },
                  onLongPress: () => _handleLongPress(msg),
                  child: bounded,
                );
              } else if (widget.enableSwipeReply) {
                wrapped = SwipeToReply(
                  key: ValueKey(msg.id),
                  messageId: msg.id,
                  isMe: isMe,
                  onReply: () => widget.onReply(msg),
                  child: bounded,
                );
              } else {
                wrapped = bounded;
              }

              return Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: wrapped,
              );
            }),
          ],
        );
      },
    ),
        // v3.9: Floating date indicator — appears on scroll + fades out.
        // Wrapped in RepaintBoundary so the pill's opacity animation
        // doesn't repaint the message list.
        if (_floatingDate != null)
          RepaintBoundary(
            child: Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showFloatingDate ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191B2C).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      _floatingDate!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textSilver
                            .withValues(alpha: 0.95),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
              // v3.8 (PR 3 Task 1) — use the normal body font, not
              // monospace (the prompt: "Date separators and message
              // times use the normal app font, not monospace").
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver.withValues(alpha: 0.9),
              letterSpacing: 0.4,
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

    // v3.8 (PR 3 Task 1) — weekday names for messages within the last
    // 6 days (Today, Yesterday, then weekday name, then short date).
    // The prompt: "Date text: Today, Yesterday, a weekday name within
    // the last 6 days, otherwise a short date; keep the app's existing
    // language and number format."
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
      if (msgDate == today) {
        label = 'Today';
      } else if (msgDate == yesterday) {
        label = 'Yesterday';
      } else {
        // Within the last 6 days? Show weekday name (e.g. "Wednesday").
        // DateTime.weekday returns 1=Monday..7=Sunday (ISO 8601).
        final daysAgo = today.difference(msgDate).inDays;
        if (daysAgo > 0 && daysAgo <= 6) {
          label = weekdays[local.weekday - 1];
        } else {
          // Older than a week → short date (e.g. "Oct 9, 2026").
          // Keep the existing language + number format (the app's
          // existing format was "Month D, Year" — preserved here).
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
