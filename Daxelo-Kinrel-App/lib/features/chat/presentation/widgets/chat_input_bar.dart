// lib/features/chat/presentation/widgets/chat_input_bar.dart
//
// DAXELO KINREL — Shared chat input bar (group + DM) — Chat UI
// Reference D12.
//
// ONE composer for both chat types, matching the reference exactly:
//   • Outer bar: chatBar surface, flat (no gradient/shadow/border).
//   • Text capsule: chatCard fill, radius 20, with the emoji toggle
//     INSIDE on the left and the attach + thinking-of-you heart
//     INSIDE on the right of the field.
//   • Trailing action: a 40 dp accent circle OUTSIDE the capsule that
//     morphs mic -> send as the user types (spinner while a voice
//     message uploads).
//
// The screen owns all state (text controller, focus node, composing
// flag, etc.) and passes it in. This widget is purely visual — it
// renders the bar and fires callbacks. The recording bar variant is
// NOT here; the screen handles the _isRecording branch before
// calling this widget.
//
// The old button row (attach/sticker/poll outside the capsule) is
// gone: the attach menu now carries Stickers + Poll entries, and the
// emoji toggle lives inside the capsule (see chat_meta.dart).

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.isComposing,
    required this.onSend,
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

  /// True when the text field has non-whitespace content -> shows the
  /// send button instead of the mic button.
  final bool isComposing;

  /// Called when the send button is tapped.
  final VoidCallback onSend;

  // ── Visibility flags (kept for API compatibility) ─────────────────
  // Stickers/Poll moved into the attach menu — their flags only
  // control whether the corresponding entries appear there.
  final bool showAttach;
  final bool showEmoji;
  final bool showStickers;
  final bool showPoll;
  final bool showVoice;

  // ── Callbacks ─────────────────────────────────────────────────────
  final VoidCallback? onAttach;
  final VoidCallback? onEmojiToggle;
  final bool emojiActive;
  final VoidCallback? onStickerPacks;
  final VoidCallback? onPoll;
  final VoidCallback? onStartRecording;

  /// True while a voice message is uploading -> shows a spinner.
  final bool isSendingVoice;

  /// Optional LayerLink for the mention-picker overlay (group only).
  final LayerLink? inputLayerLink;

  /// Placeholder text for the input field.
  final String hintText;

  /// D12 — the thinking-of-you heart inside the capsule. Wired to the
  /// app's existing fn_send_thinking_of_you feature.
  final VoidCallback? onThinkingOfYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      // D12: flat chatBar surface — no gradient, no shadow, no border.
      color: ChatUi.chatBar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Text capsule ──────────────────────────────────────
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ChatUi.chatCard,
                    borderRadius: BorderRadius.circular(ChatUi.composerRadius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Emoji toggle — INSIDE the capsule, leading.
                      if (showEmoji && onEmojiToggle != null)
                        _ComposerIcon(
                          icon: emojiActive
                              ? Icons.emoji_emotions
                              : Icons.emoji_emotions_outlined,
                          tooltip: 'Emoji and stickers',
                          onTap: onEmojiToggle!,
                          active: emojiActive,
                        ),
                      // Text field — no decoration of its own.
                      // Wrapped in a CompositedTransformTarget when
                      // inputLayerLink is provided (group mention
                      // picker). DM passes null -> no wrapper.
                      Expanded(child: _buildTextField()),
                      // Attach — INSIDE the capsule, trailing.
                      if (showAttach && onAttach != null)
                        _ComposerIcon(
                          icon: Icons.attach_file,
                          tooltip: 'Attach',
                          onTap: onAttach!,
                        ),
                      // D12 heart — thinking of you.
                      if (onThinkingOfYou != null)
                        _ComposerIcon(
                          icon: Icons.favorite,
                          tooltip: 'Thinking of you',
                          onTap: onThinkingOfYou!,
                          iconColor: ChatUi.accent,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Trailing action — 40 dp accent circle ─────────────
              // Mic -> send morph as the user types; spinner while a
              // voice message uploads.
              _TrailingAction(
                isComposing: isComposing,
                isSendingVoice: isSendingVoice,
                showVoice: showVoice,
                onSend: onSend,
                onStartRecording: onStartRecording,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the TextField, optionally wrapped in a CompositedTransformTarget
  /// for the mention-picker overlay (group only).
  Widget _buildTextField() {
    final textField = TextField(
      controller: textController,
      focusNode: focusNode,
      maxLines: null,
      textInputAction: TextInputAction.newline,
      style: ChatUi.composerText,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: ChatUi.composerHint,
        // The app theme's inputDecorationTheme paints a filled
        // darkElevated (#202338) box on every TextField — disable it so
        // the D12 capsule's chatCard color shows through untouched.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.only(
          left: 10,
          right: 10,
          top: 12,
          bottom: 12,
        ),
      ),
    );

    if (inputLayerLink != null) {
      return CompositedTransformTarget(link: inputLayerLink!, child: textField);
    }
    return textField;
  }
}

// ── Capsule icons (20 dp, 48 dp tap targets) ──────────────────────────

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: SizedBox(
        width: ChatUi.tapTarget * 0.75, // 36 dp inside the capsule
        height: ChatUi.tapTarget * 0.75,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            size: ChatUi.composerIconSize,
            color:
                iconColor ??
                (active ? ChatUi.textPrimary : ChatUi.textSecondary),
          ),
          tooltip: tooltip,
          onPressed: onTap,
        ),
      ),
    );
  }
}

// ── Trailing 40 dp accent circle ──────────────────────────────────────

class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.isComposing,
    required this.isSendingVoice,
    required this.showVoice,
    required this.onSend,
    required this.onStartRecording,
  });

  final bool isComposing;
  final bool isSendingVoice;
  final bool showVoice;
  final VoidCallback onSend;
  final VoidCallback? onStartRecording;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: isSendingVoice
          ? Semantics(
              key: const ValueKey('spinner'),
              label: 'Sending voice message',
              child: const SizedBox(
                width: ChatUi.sendButtonSize,
                height: ChatUi.sendButtonSize,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ChatUi.accent,
                    ),
                  ),
                ),
              ),
            )
          : isComposing
          ? _CircleButton(
              key: const ValueKey('send'),
              tooltip: 'Send message',
              icon: Icons.send,
              onTap: onSend,
            )
          : showVoice && onStartRecording != null
          ? _CircleButton(
              key: const ValueKey('mic'),
              tooltip: 'Record voice message',
              icon: Icons.mic_none,
              onTap: onStartRecording!,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: ChatUi.sendButtonSize,
          height: ChatUi.sendButtonSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ChatUi.accent,
          ),
          child: Icon(icon, size: ChatUi.composerIconSize, color: Colors.white),
        ),
      ),
    );
  }
}
