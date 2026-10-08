// lib/features/chat/presentation/widgets/chat_input_bar.dart
//
// DAXELO KINREL — Shared chat input bar (group + DM)
//
// EXTRACTED from chat_screen.dart's _buildInputBar so the DM screen
// can render the SAME composer: same gradient surface, same elevated
// text capsule, same send button, same colors/sizes/spacing.
//
// The screen owns all state (text controller, focus node, composing
// flag, etc.) and passes it in. This widget is purely visual — it
// renders the bar and fires callbacks. The group chat's recording bar
// variant is NOT here (it's group-only); the screen handles the
// _isRecording branch before calling this widget.
//
// Flags (all default true so the group chat is unchanged):
//   - showAttach: attachment button (paperclip)
//   - showEmoji: emoji/sticker toggle button
//   - showStickers: sticker-pack button (Giphy)
//   - showPoll: poll composer button
//   - showVoice: mic button (trailing, when not composing)
// When false, the button is omitted entirely. The DM passes false for
// all except the text capsule + send button (the DM backend supports
// text only).

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/theme/kinrel_fx.dart';
import 'chat_meta.dart';

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

  // ── Visibility flags ─────────────────────────────────────────────
  final bool showAttach;
  final bool showEmoji;
  final bool showStickers;
  final bool showPoll;
  final bool showVoice;

  // ── Callbacks (null when the corresponding flag is false) ────────
  final VoidCallback? onAttach;
  final VoidCallback? onEmojiToggle;
  final bool emojiActive;
  final VoidCallback? onStickerPacks;
  final VoidCallback? onPoll;
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
              // ── Attachment button ────────────────────────────────
              if (showAttach && onAttach != null) ...[
                AttachmentButton(onTap: onAttach!),
                const SizedBox(width: 6),
              ],
              // ── Sticker / emoji toggle ──────────────────────────
              if (showEmoji && onEmojiToggle != null) ...[
                StickerButton(
                  isActive: emojiActive,
                  onTap: onEmojiToggle!,
                ),
                const SizedBox(width: 6),
              ],
              // ── Sticker packs (Giphy) ───────────────────────────
              if (showStickers && onStickerPacks != null) ...[
                StickerPackButton(onTap: onStickerPacks!),
                const SizedBox(width: 6),
              ],
              // ── Poll composer ────────────────────────────────────
              if (showPoll && onPoll != null) ...[
                PollButton(onTap: onPoll!),
                const SizedBox(width: 8),
              ],
              // ── Unified text capsule ────────────────────────────
              // Contains the TextField + the trailing mic/send button
              // so they feel like one continuous pill.
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    // v133: Elevated capsule surface — slightly
                    // lighter than the outer bar so the capsule
                    // reads as a distinct interactive element.
                    color: const Color(0xFF1A1D2E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: focusNode.hasFocus
                          ? KinrelColors.ember.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                      width: focusNode.hasFocus ? 1.2 : 0.75,
                    ),
                    // PERF (Flat): no shadow in flat mode; rich mode
                    // keeps the focus glow.
                    boxShadow: focusNode.hasFocus
                        ? KinrelFx.shadows([
                            // v133: Focus glow — soft ember ambient
                            // light when the field is active.
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
                      // Text field — no decoration of its own.
                      // Wrapped in a CompositedTransformTarget when
                      // inputLayerLink is provided (group mention
                      // picker). DM passes null → no wrapper.
                      Expanded(
                        child: _buildTextField(),
                      ),
                      // ── Trailing mic/send button ───────────────────
                      // Lives INSIDE the capsule so it feels
                      // connected to the text field. AnimatedSwitcher
                      // smoothly morphs mic → send → spinner.
                      if (showVoice || isComposing || isSendingVoice)
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 5, bottom: 5),
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
                                    : showVoice && onStartRecording != null
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
