// lib/features/chat/presentation/widgets/chat_input_bar.dart
//
// DAXELO KINREL — Shared chat input bar (group + DM) — v3.7 (PR 2).
//
// EXTRACTED from chat_screen.dart's _buildInputBar so the DM screen
// can render the SAME composer: same gradient surface, same elevated
// text capsule, same send button, same colors/sizes/spacing.
//
// v3.7 (PR 2) — simplified layout per the WhatsApp/Telegram-style
// composer spec:
//   ┌─────────────────────────────────────────────────────┐
//   │  [emoji]  ┌──────────────────────────────────┐  [mic/send]  │
//   │           │ TextField (grows up to 5 lines)  │              │
//   │           │              [attach]            │              │
//   │           └──────────────────────────────────┘              │
//   └─────────────────────────────────────────────────────┘
//
// Changes vs. v3.6:
//   - Emoji button moved INSIDE the capsule (left side). Was OUTSIDE
//     (left of the capsule).
//   - Attach button moved INSIDE the capsule (right side). Was OUTSIDE
//     (left of the capsule).
//   - Removed the StickerPackButton (Giphy separate button — was the
//     "second smiley button"). GIF is now a tab in the emoji panel
//     (which the screen supplies) OR an option in the attach sheet.
//   - Removed the separate PollButton. Poll is now an option in the
//     attach sheet.
//   - maxLines: 5 (was null = unlimited with maxHeight cap).
//   - Drives button visibility from [capabilities] — group shows
//     everything; direct shows only the emoji button (emoji tab only)
//     + text field + Send.
//
// The screen owns all state (text controller, focus node, composing
// flag, etc.) and passes it in. This widget is purely visual — it
// renders the bar and fires callbacks. The group chat's recording bar
// variant is NOT here (it's group-only); the screen handles the
 // _isRecording branch before calling this widget.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/theme/kinrel_fx.dart';
import 'chat_capabilities.dart';
import 'chat_meta.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.isComposing,
    required this.onSend,
    required this.capabilities,
    this.onAttach,
    this.onEmojiToggle,
    this.emojiActive = false,
    this.onStartRecording,
    this.isSendingVoice = false,
    this.inputLayerLink,
    this.hintText = 'Message',
  });

  /// Owned by the parent screen — the text field writes to this.
  final TextEditingController textController;

  /// Owned by the parent screen — controls focus + the focus glow.
  final FocusNode focusNode;

  /// True when the text field has non-whitespace content → shows the
  /// send button instead of the mic button.
  final bool isComposing;

  /// Called when the send button is tapped.
  final VoidCallback onSend;

  /// v3.7 (PR 2) — Capabilities drive button visibility.
  ///   - supportsAttachments → show the attach button (right inside the capsule)
  ///   - supportsVoice → show the mic button (outside, right)
  ///   - canReact → show the emoji button (left inside the capsule)
  ///     (canReact is the closest capability for "this chat supports emoji
  ///     panel"; in direct chat it's true so the emoji button shows but
  ///     only the Emoji tab is shown — the screen's onEmojiToggle handler
  ///     decides which tabs to render)
  final ChatCapabilities capabilities;

  // ── Callbacks ──────────────────────────────────────────────────────
  /// Open the attach sheet (Photo, Camera, Document, Location, GIF, Poll).
  /// Only called when capabilities.supportsAttachments is true.
  final VoidCallback? onAttach;

  /// Toggle the emoji panel open/closed. The panel itself (with Emoji,
  /// GIF, Stickers tabs in group; Emoji tab only in DM) is rendered by
  /// the screen above this bar.
  final VoidCallback? onEmojiToggle;
  final bool emojiActive;

  /// Start a voice recording. Only called when capabilities.supportsVoice
  /// is true.
  final VoidCallback? onStartRecording;

  /// True while a voice message is uploading → shows a spinner.
  final bool isSendingVoice;

  /// Optional LayerLink for the mention-picker overlay (group only).
  /// When null, the text field is not wrapped in a CompositedTransformTarget.
  final LayerLink? inputLayerLink;

  /// Placeholder text for the input field.
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final caps = capabilities;
    final showEmojiButton = caps.canReact; // emoji panel available
    final showAttachButton = caps.supportsAttachments && onAttach != null;
    final showMicOrSend =
        caps.supportsVoice || isComposing || isSendingVoice;

    return Container(
      // PERF (Flat): solid color in flat mode; gradient in rich mode.
      decoration: BoxDecoration(
        color: KinrelFx.rich ? null : const Color(0xFF0A0B16),
        gradient: KinrelFx.gradient(
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0E0F1C),
              Color(0xFF0A0B16),
            ],
          ),
        ),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
        // PERF (Flat): no shadow in flat mode.
        boxShadow: KinrelFx.shadows([
          // v133: Subtle top shadow lifts the composer off the chat
          // content. 18% alpha, 8 blur — felt, not seen.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ]),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Unified text capsule ────────────────────────────
              // v3.7: emoji button (left inside) + attach button
              // (right inside) live INSIDE the capsule so the whole
              // thing reads as one continuous pill.
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  // v3.7: maxHeight 5 lines × 1.45 line-height × 15px
                  // font + 26px vertical padding ≈ 135px. Cap at 140
                  // to keep a 5px buffer.
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D2E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: focusNode.hasFocus
                          ? KinrelColors.ember.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                      width: focusNode.hasFocus ? 1.2 : 0.75,
                    ),
                    boxShadow: focusNode.hasFocus
                        ? KinrelFx.shadows([
                            BoxShadow(
                              color: KinrelColors.ember
                                  .withValues(alpha: 0.10),
                              blurRadius: 12,
                              offset: const Offset(0, 0),
                            ),
                          ])
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // ── Emoji button INSIDE the capsule (left) ──
                      if (showEmojiButton && onEmojiToggle != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 4, bottom: 5),
                          child: StickerButton(
                            isActive: emojiActive,
                            onTap: onEmojiToggle!,
                          ),
                        ),
                      ],
                      // Text field
                      Expanded(
                        child: _buildTextField(),
                      ),
                      // ── Attach button INSIDE the capsule (right) ──
                      if (showAttachButton) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 4, bottom: 5),
                          child: AttachmentButton(onTap: onAttach!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // ── Mic / Send button OUTSIDE the capsule (right) ──
              // Lives outside the capsule so it doesn't resize with
              // the field. AnimatedSwitcher morphs mic → send → spinner.
              if (showMicOrSend)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(
                      scale: Tween<double>(begin: 0.6, end: 1.0)
                          .animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      )),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                    child: isSendingVoice
                        ? const SizedBox(
                            key: ValueKey('spinner'),
                            width: 38,
                            height: 38,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: KinrelColors.orange,
                                ),
                              ),
                            ),
                          )
                        : isComposing
                            ? SendButton(
                                key: const ValueKey('send'),
                                isActive: true,
                                onTap: onSend,
                              )
                            : caps.supportsVoice && onStartRecording != null
                                ? MicButton(
                                    key: const ValueKey('mic'),
                                    onTap: onStartRecording!,
                                  )
                                : const SizedBox.shrink(),
                  ),
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
      // v3.7: maxLines 5 (was null = unlimited). The field grows up
      // to 5 lines then scrolls internally. The maxHeight: 140 cap
      // on the AnimatedContainer clips the visual height to ~5 lines.
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: KinrelColors.textWhite,
        height: 1.45,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: KinrelColors.textDim.withValues(alpha: 0.7),
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.only(
          left: 18,
          right: 12,
          top: 13,
          bottom: 13,
        ),
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
