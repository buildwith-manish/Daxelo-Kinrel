// lib/features/chat/providers/chat_selection_provider.dart
//
// DAXELO KINREL — WhatsApp-style Message Selection State
//
// Tracks the selection mode + the set of selected message IDs. Uses
// stable message IDs (not list indices) so the selection stays correct
// when messages are inserted, removed, reordered, or refreshed.
//
// The selection state is SEPARATE from the persistent message data —
// it's ephemeral UI state that resets when the user exits selection
// mode (pressing Back, tapping the close button, or pressing ESC).
//
// The provider is family-scoped (keyed by familyId) so each chat
// screen has its own independent selection state. This prevents a
// selection in one chat from leaking into another when the user
// navigates between conversations.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The ephemeral selection state for a single chat screen.
@immutable
class ChatSelectionState {
  const ChatSelectionState({
    this.selectionMode = false,
    this.selectedMessageIds = const <String>{},
  });

  /// True when the user has entered selection mode (long-pressed a
  /// message). When true, tapping a message toggles its selection
  /// instead of opening a preview / triggering a reply.
  final bool selectionMode;

  /// The set of selected message IDs. Uses stable IDs (cm_...) so
  /// the selection survives message list refreshes / re-ordering.
  /// Order is NOT preserved (it's a Set) — the UI reads the count
  /// from `selectedCount`, not from the iteration order.
  final Set<String> selectedMessageIds;

  /// The number of selected messages. Convenience getter so the
  /// toolbar can display "N selected" without a separate .length call.
  int get selectedCount => selectedMessageIds.length;

  /// True when a specific message ID is currently selected.
  bool isSelected(String messageId) => selectedMessageIds.contains(messageId);

  ChatSelectionState copyWith({
    bool? selectionMode,
    Set<String>? selectedMessageIds,
  }) {
    return ChatSelectionState(
      selectionMode: selectionMode ?? this.selectionMode,
      selectedMessageIds: selectedMessageIds ?? this.selectedMessageIds,
    );
  }
}

/// StateNotifier managing the selection state for a single chat.
class ChatSelectionNotifier extends StateNotifier<ChatSelectionState> {
  ChatSelectionNotifier() : super(const ChatSelectionState());

  /// Enter selection mode + select the given message. Called when the
  /// user long-presses a message (replaces the old bottom-sheet behavior).
  void enterSelection(String messageId) {
    state = ChatSelectionState(
      selectionMode: true,
      selectedMessageIds: {messageId},
    );
  }

  /// Toggle the selection of a message. If in selection mode, tapping
  /// a message calls this. When the last message is deselected,
  /// selection mode is automatically exited.
  void toggleSelection(String messageId) {
    if (!state.selectionMode) return;

    final newIds = Set<String>.from(state.selectedMessageIds);
    if (newIds.contains(messageId)) {
      newIds.remove(messageId);
    } else {
      newIds.add(messageId);
    }

    if (newIds.isEmpty) {
      // Exit selection mode when the last message is deselected.
      exitSelection();
    } else {
      state = state.copyWith(selectedMessageIds: newIds);
    }
  }

  /// Clear all selections but stay in selection mode (used by a
  /// "Clear selection" action if added to the toolbar).
  void clearSelection() {
    state = state.copyWith(selectedMessageIds: <String>{});
  }

  /// Exit selection mode entirely. Called when the user presses Back,
  /// taps the close button, or navigates away.
  void exitSelection() {
    state = const ChatSelectionState();
  }
}

/// Family-scoped provider so each chat screen has independent selection
/// state. The familyId parameter is the family chat ID.
final chatSelectionProvider =
    StateNotifierProvider.family<ChatSelectionNotifier, ChatSelectionState, String>(
  (ref, familyId) => ChatSelectionNotifier(),
);
