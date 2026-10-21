// lib/features/chat/presentation/widgets/chat_input_bar.dart
//
// DAXELO KINREL — Shared chat input bar (group + DM)
//
// D12 (Chat UI Reference):
//   • Bar background chatBar, padding 8, row with 8 gap.
//   • Field: minimum height 40, grows to 5 lines, radius 20, background
//     chatCard, horizontal padding 12, row with 10 gap: emoji icon 20 in
//     textHint, the text field (hint "Message" 14 textHint), attach icon
//     20 in textHint, and (when wired) the thinking-of-you icon 20 in
//     orange.
//   • Right of the field a 40×40 circle, orange background, white icon
//     20: mic when empty and send when there is text.
//
// The screen owns all state (text controller, focus node, composing
// flag, etc.) and passes it in. This widget is purely visual — it
// renders the bar and fires callbacks. The group chat's recording bar
// variant is NOT here (it's screen-owned); the screen handles the
// _isRecording branch before calling this widget.
//
// Flat style: solid colors only — no gradients, no shadows, no blur.
// Icon buttons are 48 dp tap targets with Semantics labels.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_typography.dart';
import '../chat_ui_tokens.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.isComposing,
    required this.onSend,
    // feat(chat): scheduled messages — long-press the send button opens
    // the schedule sheet. Null = scheduling not available.
    this.onSchedule,
    this.showAttach = true,
    this.showEmoji = true,
    this.showStickers = true,
    this.showPoll = true,
    this.showVoice = true,
    this.onAttach,
    this.onEmojiToggle,
    this.emojiActive = false,
    this.onStickerPacks,
    this.onPoll,
    this.onStartRecording,
    this.isSendingVoice = false,
    this.inputLayerLink,
    this.hintText = 'Message',
    this.onThinkingOfYou,
  });

  /// Owned by the parent screen — the text field writes to this.
  final TextEditingController textController;

  /// Owned by the parent screen — controls focus.
  final FocusNode focusNode;

  /// True when the text field has non-whitespace content → shows the
  /// send button instead of the mic button.
  final bool isComposing;

  /// Called when the send button is tapped.
  final VoidCallback onSend;

  // feat(chat): scheduled messages — long-press the send button opens
  // the schedule sheet. Null = scheduling not available (e.g. empty
  // text — the send button is hidden when not composing, so this
  // callback is only invoked from the active send button).
  final VoidCallback? onSchedule;

  // ── Visibility flags ─────────────────────────────────────────────
  final bool showAttach;
  final bool showEmoji;
  final bool showStickers;
  final bool showPoll;
  final bool showVoice;

  // ── Callbacks (null when the corresponding feature is off) ────────
  final VoidCallback? onAttach;
  final VoidCallback? onEmojiToggle;
  final bool emojiActive;
  final VoidCallback? onStickerPacks;
  final VoidCallback? onPoll;
  final VoidCallback? onStartRecording;

  /// True while a voice message is uploading → shows a spinner.
  final bool isSendingVoice;

  /// Optional LayerLink for the mention-picker overlay. Used by all
  /// chat kinds (family-wide, group, direct — Phase A opens the picker
  /// in groups + family-wide; Phase B opens it in DMs for reference
  /// mentions). When null, the text field is not wrapped in a
  /// CompositedTransformTarget (e.g. tests that don't render the
  /// picker).
  final LayerLink? inputLayerLink;

  /// Placeholder text for the input field.
  final String hintText;

  /// D12: when wired, the thinking-of-you heart icon 20 in orange
  /// shows at the end of the field row (the app's existing
  /// fn_send_thinking_of_you feature).
  final VoidCallback? onThinkingOfYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ChatUi.chatBar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Unified text capsule (D12) ─────────────────────────
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                    // Grows to ~5 lines (40 + 4 × 20) + caps there.
                    maxHeight: 140,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ChatUi.chatCard,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Emoji toggle — inside the field, leading.
                      if (showEmoji && onEmojiToggle != null)
                        _ComposerIconButton(
                          icon: emojiActive
                              ? Icons.mood
                              : Icons.mood_outlined,
                          semanticsLabel: 'Emoji and stickers',
                          color: emojiActive
                              ? ChatUi.accent
                              : ChatUi.textHint,
                          onTap: onEmojiToggle,
                        ),
                      // Text field — no decoration of its own.
                      // Wrapped in a CompositedTransformTarget when
                      // inputLayerLink is provided (group mention picker).
                      Expanded(
                        child: _buildTextField(),
                      ),
                      // Attach — inside the field, trailing.
                      if (showAttach && onAttach != null)
                        _ComposerIconButton(
                          icon: Icons.attach_file,
                          semanticsLabel: 'Attach',
                          color: ChatUi.textHint,
                          onTap: onAttach,
                        ),
                      // Thinking of you — inside the field, trailing,
                      // orange (only where the feature is wired).
                      if (onThinkingOfYou != null)
                        _ComposerIconButton(
                          icon: Icons.favorite,
                          semanticsLabel: 'Thinking of you',
                          color: ChatUi.accent,
                          onTap: onThinkingOfYou,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Right circle: 40×40, orange, white icon 20 ────────
              // mic when empty, send when there is text. AnimatedSwitcher
              // smoothly morphs mic → send → spinner.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: isSendingVoice
                    ? const SizedBox(
                        key: ValueKey('spinner'),
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ChatUi.accent,
                            ),
                          ),
                        ),
                      )
                    : isComposing
                        ? _RoundActionCircle(
                            key: const ValueKey('send'),
                            icon: Icons.send,
                            semanticsLabel: 'Send message',
                            onTap: onSend,
                            onLongPress: onSchedule,
                          )
                        : (showVoice && onStartRecording != null)
                            ? _RoundActionCircle(
                                key: const ValueKey('mic'),
                                icon: Icons.mic,
                                semanticsLabel: 'Record voice message',
                                onTap: onStartRecording,
                              )
                            : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the TextField, optionally wrapped in a CompositedTransformTarget
  /// for the mention-picker overlay (used by family-wide, group, and —
  /// in Phase B — direct chats for reference mentions).
  Widget _buildTextField() {
    final textField = TextField(
      controller: textController,
      focusNode: focusNode,
      maxLines: null,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
        color: ChatUi.textPrimary,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: ChatUi.composerHint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        // Vertically centers the first line inside the 40 dp capsule;
        // the 48 dp leading/trailing icon buttons define the min height.
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
      ),
    );

    if (inputLayerLink != null) {
      return CompositedTransformTarget(
        link: inputLayerLink!,
        child: textField,
      );
    }
    return textField;
  }
}

/// A flat icon button inside the composer capsule: 48 dp tap target,
/// 20 dp glyph, Semantics label.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.semanticsLabel,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: ChatUi.tapTarget,
          height: ChatUi.tapTarget,
          child: Center(
            child: Icon(icon, size: ChatUi.iconComposerEmoji, color: color),
          ),
        ),
      ),
    );
  }
}

/// D12 right circle: 40×40, orange background, white icon 20.
class _RoundActionCircle extends StatelessWidget {
  const _RoundActionCircle({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback? onTap;
  // feat(chat): scheduled messages — long-press the send button opens
  // the ScheduleMessageSheet (so the user can pick "Later today",
  // "Tomorrow morning", or a custom date+time).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ChatUi.accent,
          ),
          child: Center(
            child: Icon(
              icon,
              size: ChatUi.iconComposerSend,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
