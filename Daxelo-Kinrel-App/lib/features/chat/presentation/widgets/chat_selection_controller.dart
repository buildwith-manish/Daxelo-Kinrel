// lib/features/chat/presentation/widgets/chat_selection_controller.dart
//
// DAXELO KINREL — Selection mode state for chat.
//
// Holds the set of selected message ids, in the order they were
// selected (LinkedHashSet preserves insertion order — we expose it
// as an ordered iterable so the selection bar shows N in selection
// order, not message-time order).
//
// Why a provider, not a ValueNotifier? Because Riverpod selectors let
// each row listen to ONLY its own selected-state without rebuilding
// the whole list. The list rebuilds when `inSelectionMode` flips, but
// individual row tint toggles use `select` on the controller's state.
//
// Lifecycle:
//   - One provider instance per open chat (autoDispose + family on
//     a chat-id string so group + DM don't share state).
//   - On entry: add the first message id, set mode = true.
//   - On toggle: add/remove the id; if the set becomes empty, exit mode.
//   - On clear: empty the set, exit mode.
//   - On message list update: prune ids that no longer exist in the
//     list (so a deleted message doesn't linger as a "ghost selection"
//     — and if all selected were deleted, exit mode automatically).
//
// Per-row selected state is exposed via `isSelected(messageId)`. The
// MessageBubble uses a `select` selector on this so toggling one row's
// state rebuilds ONLY that row, not the whole list. The existing
// `RepaintBoundary` per item keeps the repaint area clipped.
//
// The "count" is exposed as a separate selector for the selection bar.
//
// Accessibility: every change to the count announces it to screen
// readers (e.g. "2 selected"). The announcement is delivered via
// the `semanticsLabel` field, which the selection bar mounts as a
// `Semantics(liveRegion: true)` text.

import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';

/// The state of one chat's selection mode.
@immutable
class ChatSelectionState {
  /// Ordered set of selected message ids.
  final LinkedHashSet<String> selectedIds;

  /// True while in selection mode (header is swapped for the selection bar).
  final bool inSelectionMode;

  /// The id of the message that should anchor the floating reaction pill
  /// (only set when exactly ONE message is selected and `canReact`).
  /// Null otherwise.
  final String? reactionBarAnchorId;

  /// Monotonic counter so listeners using `select` on `count` rebuild
  /// only when the count actually changes.
  final int count;

  /// Optional semantics announcement — the selection bar mounts a
  /// `Semantics(liveRegion: true)` text node that mirrors this string.
  /// Empty string when no announcement is needed.
  final String semanticsLabel;

  const ChatSelectionState({
    this.selectedIds = const LinkedHashSet.empty(),
    this.inSelectionMode = false,
    this.reactionBarAnchorId,
    this.count = 0,
    this.semanticsLabel = '',
  });

  bool isSelected(String messageId) => selectedIds.contains(messageId);

  ChatSelectionState copyWith({
    LinkedHashSet<String>? selectedIds,
    bool? inSelectionMode,
    String? reactionBarAnchorId,
    int? count,
    String? semanticsLabel,
    bool clearReactionAnchor = false,
  }) {
    return ChatSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      inSelectionMode: inSelectionMode ?? this.inSelectionMode,
      reactionBarAnchorId:
          clearReactionAnchor ? null : (reactionBarAnchorId ?? this.reactionBarAnchorId),
      count: count ?? this.count,
      semanticsLabel: semanticsLabel ?? this.semanticsLabel,
    );
  }
}

/// StateNotifier for one chat's selection. Per chat-id so two open
/// chats (group + DM) keep separate selection state.
class ChatSelectionNotifier extends StateNotifier<ChatSelectionState> {
  ChatSelectionNotifier() : super(const ChatSelectionState());

  /// Enter selection mode with the given message selected.
  /// Gives a light haptic. Idempotent if already in selection mode.
  void enter(String messageId) {
    final ids = LinkedHashSet<String>.from(state.selectedIds);
    ids.add(messageId);
    final count = ids.length;
    _announce(count);
    state = ChatSelectionState(
      selectedIds: ids,
      inSelectionMode: true,
      reactionBarAnchorId: count == 1 ? messageId : null,
      count: count,
      semanticsLabel: _labelForCount(count),
    );
  }

  /// Toggle a message id in / out of selection. If we were not in
  /// selection mode, this enters it (with the message selected).
  /// If the set becomes empty after removal, exit selection mode.
  void toggle(String messageId) {
    final ids = LinkedHashSet<String>.from(state.selectedIds);
    if (ids.contains(messageId)) {
      ids.remove(messageId);
    } else {
      ids.add(messageId);
    }
    if (ids.isEmpty) {
      exit();
      return;
    }
    final count = ids.length;
    _announce(count);
    state = ChatSelectionState(
      selectedIds: ids,
      inSelectionMode: true,
      reactionBarAnchorId: count == 1 ? ids.first : null,
      count: count,
      semanticsLabel: _labelForCount(count),
    );
  }

  /// Leave selection mode and clear the set.
  void exit() {
    state = const ChatSelectionState();
  }

  /// Prune ids that no longer exist in the current message list.
  /// Called by the list widget whenever the message list rebuilds
  /// (so deleted messages don't linger as ghost selections).
  /// If the set becomes empty, exit selection mode.
  void pruneToExistingIds(Set<String> existingIds) {
    if (!state.inSelectionMode) return;
    final ids = LinkedHashSet<String>.from(state.selectedIds);
    ids.removeWhere((id) => !existingIds.contains(id));
    if (ids.length == state.selectedIds.length) return;  // no change
    if (ids.isEmpty) {
      exit();
      return;
    }
    final count = ids.length;
    state = ChatSelectionState(
      selectedIds: ids,
      inSelectionMode: true,
      reactionBarAnchorId: count == 1 ? ids.first : null,
      count: count,
      semanticsLabel: _labelForCount(count),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Announce the new count to screen readers. Fire-and-forget.
  void _announce(int count) {
    if (kIsWeb) return;
    // SemanticsService.announce requires a TextDirection; use the
    // ambient direction (the caller's screen reads LTR by default).
    try {
      SemanticsService.announce(_labelForCount(count), TextDirection.ltr);
    } catch (_) {
      // Screen reader not available — silent.
    }
  }

  String _labelForCount(int count) {
    if (count == 0) return '';
    if (count == 1) return '1 message selected';
    return '$count messages selected';
  }
}

/// One provider per chat (group or DM). Pass the chat-id string
/// (`familyId` for group, `'dm_$otherUserId'` for direct).
final chatSelectionProvider = StateNotifierProvider.autoDispose
    .family<ChatSelectionNotifier, ChatSelectionState, String>(
  (ref, chatId) => ChatSelectionNotifier(),
);
