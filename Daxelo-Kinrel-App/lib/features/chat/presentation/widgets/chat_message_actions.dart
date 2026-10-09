// lib/features/chat/presentation/widgets/chat_message_actions.dart
//
// DAXELO KINREL — Per-screen action callbacks.
//
// Holds nullable callbacks for every action the shared widgets might
// trigger. The group chat supplies implementations that call
// `chatProvider` / `chatEnhancementServiceProvider`; the direct chat
// supplies only the ones its provider supports (Reply, React, Copy,
// Share outside, Retry, Delete-failed).
//
// A NULL callback means "this action is not available in this chat
// type" — the shared widget HIDES the corresponding UI. This is the
// one-to-one correspondence with `ChatCapabilities` flags: if
// `canForward` is false, `forward` is also null (and vice versa).
//
// Why callbacks (not providers)? The two chat types use DIFFERENT
// providers (`chatProvider` vs `directChatProvider`). A shared widget
// can't `ref.read` either of them without knowing which. Passing
// callbacks through the widget tree lets the screen own its provider
// and expose only the operations the shared UI needs.
//
// The screen constructs one `ChatMessageActions` instance and passes
// it down through `ChatMessageList` to `MessageBubble` and to the
// selection bar. The screen rebuilds the instance when the current
// user changes (rare).
//
// All callbacks are async-fire-and-forget from the widget's POV:
// the widget calls them and may close the selection mode immediately
// (the screen's responsibility to handle errors via snackbars).
//
// Callbacks:
//   reply(message)               — set the reply-to state in the composer
//   toggleReaction(message, emoji) — apply or remove an emoji reaction
//   edit(message)                — open the edit dialog (group only)
//   deleteForMe(messages)        — soft-delete (per-user) the messages
//   deleteForEveryone(messages)  — hard-delete (all participants) — group own only
//   star(message, starred)       — toggle star
//   pin(message, pinned)         — toggle pin
//   forward(messages)            — open the ForwardPickerSheet (extended
//                                  to accept a list) and send to targets
//   showInfo(message)            — open MessageInfoSheet
//   report(message)              — open report flow (NOT IMPLEMENTED — null)
//   addToMemories(message)       — open add-to-memories flow (NOT IMPLEMENTED — null)
//   saveToGallery(messages)      — save all media messages to device gallery
//   shareOutside(messages)       — share_plus share texts + media files
//
// `copyTexts(messages)` is a pure function (not async) — it joins the
// message texts in time order, one per line; with >1 selected in a
// group chat it prepends the sender name before each line. Used by
// the Copy overflow row and the keyboard-copy semantics.
//
// `shareTexts(messages)` is the same join but used for share_plus.
//
// The `copyTexts` / `shareTexts` helpers are static methods so they
// can be tested in isolation.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../providers/chat_provider.dart';

@immutable
class ChatMessageActions {
  /// Reply — set the composer's reply-to state.
  final void Function(ChatMessage message) reply;

  /// Toggle a reaction emoji on/off for a message.
  final Future<void> Function(ChatMessage message, String emoji) toggleReaction;

  /// Open the edit dialog (group own-text only).
  final void Function(ChatMessage message)? edit;

  /// Soft-delete (per-user) the messages.
  /// For direct chat this is only ever called with own failed messages
  /// (the selection bar gates the Delete action accordingly).
  final Future<void> Function(List<ChatMessage> messages) deleteForMe;

  /// Hard-delete (all participants) the messages — group own only.
  final Future<void> Function(List<ChatMessage> messages)? deleteForEveryone;

  /// Toggle star on/off.
  final Future<void> Function(ChatMessage message, bool starred)? star;

  /// Toggle pin on/off.
  final Future<void> Function(ChatMessage message, bool pinned)? pin;

  /// Open the ForwardPickerSheet (extended to accept a list) and
  /// send to the chosen targets in time order. The sheet handles the
  /// 20-message limit + progress UI.
  final Future<void> Function(List<ChatMessage> messages)? forward;

  /// Open MessageInfoSheet.
  final Future<void> Function(ChatMessage message)? showInfo;

  /// Open the report flow. NULL until a real report backend exists.
  final Future<void> Function(ChatMessage message)? report;

  /// Open the add-to-memories flow. NULL until a real flow exists.
  final Future<void> Function(ChatMessage message)? addToMemories;

  /// Save all media messages to device gallery.
  final Future<void> Function(List<ChatMessage> messages)? saveToGallery;

  /// Share via share_plus — texts joined + media files.
  final Future<void> Function(List<ChatMessage> messages)? shareOutside;

  /// Retry sending an own failed message.
  final Future<void> Function(ChatMessage message)? retry;

  /// Delete an own failed message (the per-row Delete action).
  final Future<void> Function(ChatMessage message)? deleteFailed;

  const ChatMessageActions({
    required this.reply,
    required this.toggleReaction,
    this.edit,
    required this.deleteForMe,
    this.deleteForEveryone,
    this.star,
    this.pin,
    this.forward,
    this.showInfo,
    this.report,
    this.addToMemories,
    this.saveToGallery,
    this.shareOutside,
    this.retry,
    this.deleteFailed,
  });

  // ── Pure helpers ───────────────────────────────────────────────────

  /// Join the message texts in time order, one per line.
  /// For group chat with >1 selected, prepend the sender name before
  /// each line so the paste is readable.
  ///
  /// Messages without text content (e.g. photo only) are skipped.
  /// The order is ascending by [ChatMessage.timestamp].
  static String copyTexts({
    required List<ChatMessage> messages,
    required bool isDirect,
  }) {
    if (messages.isEmpty) return '';
    final sorted = [...messages]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final lines = <String>[];
    final prependSender = !isDirect && sorted.length > 1;
    for (final m in sorted) {
      final text = m.content.trim();
      if (text.isEmpty) continue;
      if (prependSender) {
        lines.add('${m.senderName}: $text');
      } else {
        lines.add(text);
      }
    }
    return lines.join('\n');
  }
}
