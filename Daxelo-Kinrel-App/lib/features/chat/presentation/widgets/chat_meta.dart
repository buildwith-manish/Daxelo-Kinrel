// lib/features/chat/presentation/widgets/chat_meta.dart
//
// DAXELO KINREL — Chat meta widgets extracted from chat_screen.dart (v5.184)
//
// Leaf widgets that have zero dependencies on _ChatScreenState:
//   - ReadReceipt (done / done_all ticks, D7)
//   - RecordingDot (pulsing red dot while recording)
//   - ReactionOverlay (D15 reaction bar pill)
//   - DateGroup (helper class for date separators)
//   - Tier3SwipeToReply (swipe-to-reply Dismissible wrapper)
//   - ScrollToBottomFab (scroll-to-bottom FAB)
//   - kinshipCategoryColor (helper function for edge colors)
//
// Chat UI Reference: composer buttons (Send/Mic/Attach/Sticker/Poll)
// moved into the D12 ChatInputBar capsule; the header actions live in
// chat_header_bar.dart (ChatHeaderBar).
//
// Pure mechanical extraction — every class keeps its exact API.
// chat_screen.dart imports this file instead of defining them inline.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/kinship/kinship_edge_style.dart';
import '../chat_ui_tokens.dart';
import '../../providers/chat_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Read Receipt (single/double tick)
// ═══════════════════════════════════════════════════════════════════════

class ReadReceipt extends StatelessWidget {
  const ReadReceipt({super.key, required this.isRead, this.messageStatus});

  final bool isRead;
  final String? messageStatus;

  @override
  Widget build(BuildContext context) {
    final status = messageStatus ?? (isRead ? 'read' : 'sent');

    // Feature 1: 'sending' shows a small clock icon (no ticks yet — the
    // message hasn't reached the server). 'failed' shows a red error
    // icon; retry affordance is handled by the bubble (tapping the
    // whole bubble retries, not just the receipt).
    //
    // D7/C: ticks render as the Material done_all glyph at 13 dp (the
    // existing tick COLORS and states stay exactly as they were).
    if (status == 'sending') {
      return SizedBox(
        width: 13,
        height: 13,
        child: Icon(
          Icons.access_time,
          size: 13,
          color: KinrelColors.textDim.withValues(alpha: 0.7),
        ),
      );
    }
    if (status == 'failed') {
      return SizedBox(
        width: 13,
        height: 13,
        child: Icon(
          Icons.error_outline,
          size: 13,
          color: Colors.red.shade400,
        ),
      );
    }

    final Color color;
    final bool showDouble;

    if (status == 'read' || isRead) {
      color = KinrelColors.gold;
      showDouble = true;
    } else if (status == 'delivered') {
      color = KinrelColors.textDim;
      showDouble = true;
    } else {
      // 'sent' — single tick
      color = KinrelColors.textDim;
      showDouble = false;
    }

    return SizedBox(
      width: 13,
      height: 13,
      child: Icon(
        showDouble ? Icons.done_all : Icons.done,
        size: 13,
        color: color,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Kinship Category Color helper
// ═══════════════════════════════════════════════════════════════════════

Color? kinshipCategoryColor(KinshipEdgeCategory category) {
  switch (category) {
    case KinshipEdgeCategory.parent:
      return KinshipEdgeColors.parent;
    case KinshipEdgeCategory.child:
      return KinshipEdgeColors.child;
    case KinshipEdgeCategory.sibling:
      return KinshipEdgeColors.sibling;
    case KinshipEdgeCategory.spouse:
      return KinshipEdgeColors.spouseEdge;
    case KinshipEdgeCategory.grandparent:
      return KinshipEdgeColors.grandparent;
    case KinshipEdgeCategory.auntUncle:
      return KinshipEdgeColors.auntUncle;
    case KinshipEdgeCategory.cousin:
      return KinshipEdgeColors.cousin;
    case KinshipEdgeCategory.inLaw:
      return KinshipEdgeColors.inLaw;
    case KinshipEdgeCategory.extended:
      return KinshipEdgeColors.extended;
    case KinshipEdgeCategory.self:
    case KinshipEdgeCategory.indirect:
      return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording Dot
// ═══════════════════════════════════════════════════════════════════════

class RecordingDot extends StatefulWidget {
  const RecordingDot({super.key});

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.error.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.error.withValues(alpha: _animation.value * 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reaction Overlay
// ═══════════════════════════════════════════════════════════════════════

class ReactionOverlay extends StatelessWidget {
  const ReactionOverlay({
    super.key,
    required this.onEmojiSelected,
    required this.onDismiss,
    this.onMoreTap,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onDismiss;
  final VoidCallback? onMoreTap;

  static const _emojis = ['❤️', '😂', '👍', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    // D15: pill, radius full, background chatMenu, margin 4 vertical /
    // 12 horizontal, padding 8 vertical / 12 horizontal, six reaction
    // glyphs of size 22 evenly spaced and a plus button last.
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ChatUi.chatMenu,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final emoji in _emojis)
                        GestureDetector(
                          onTap: () => onEmojiSelected(emoji),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ),
                      if (onMoreTap != null)
                        GestureDetector(
                          onTap: onMoreTap,
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                Icons.add,
                                color: ChatUi.reactionPlus,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Date Group Helper
// ═══════════════════════════════════════════════════════════════════════

class DateGroup {
  DateGroup({required this.dateLabel, required this.messages});

  final String dateLabel;
  final List<ChatMessage> messages;
}

// ═══════════════════════════════════════════════════════════════════════
// Tier 3 / Swipe-to-Reply
// ═══════════════════════════════════════════════════════════════════════

class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.messageId,
    required this.isMe,
    required this.onReply,
    required this.child,
  });

  final String messageId;
  final bool isMe;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// The bubble travels at most this fraction of the row width.
  static const double _maxFraction = 0.20;
  static const double _maxPixels = 80;

  /// Reply fires when released after passing this fraction of max travel.
  static const double _triggerFraction = 0.7;

  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  double _maxDrag = 64;
  double _raw = 0;
  double _releaseFrom = 0;
  bool _armed = false;

  // Received bubbles move right, your own bubbles move left, so a bubble
  // always moves toward empty space and never leaves the screen.
  double get _dir => widget.isMe ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      _offset.value =
          _releaseFrom * (1 - Curves.easeOutCubic.transform(_back.value));
    });
  }

  @override
  void dispose() {
    _back.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails d) {
    _back.stop();
    _raw = _offset.value;
    _armed = _offset.value >= _maxDrag * _triggerFraction;
  }

  void _onUpdate(DragUpdateDetails d) {
    _raw = math.max(0.0, _raw + d.delta.dx * _dir);
    // Follow the finger up to _maxDrag, then resist hard.
    final shown =
        _raw <= _maxDrag ? _raw : _maxDrag + (_raw - _maxDrag) * 0.08;
    _offset.value = math.min(shown, _maxDrag * 1.1);

    final armedNow = _offset.value >= _maxDrag * _triggerFraction;
    if (armedNow && !_armed) {
      HapticFeedback.lightImpact();
    }
    _armed = armedNow;
  }

  void _release({required bool allowReply}) {
    if (allowReply && _armed) {
      widget.onReply();
    }
    _armed = false;
    _raw = 0;
    _releaseFrom = _offset.value;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = math.min(constraints.maxWidth * _maxFraction, _maxPixels);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: (_) => _release(allowReply: true),
          onHorizontalDragCancel: () => _release(allowReply: false),
          child: ValueListenableBuilder<double>(
            valueListenable: _offset,
            // The bubble is built once and only moved, not rebuilt or repainted.
            child: RepaintBoundary(child: widget.child),
            builder: (context, offset, child) {
              final progress =
                  (offset / (_maxDrag * _triggerFraction)).clamp(0.0, 1.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (offset > 2)
                    Positioned.fill(
                      child: Align(
                        alignment: widget.isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * progress,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: KinrelColors.ember
                                    .withValues(alpha: 0.15 * progress),
                              ),
                              child: Icon(
                                Icons.reply_rounded,
                                size: 20,
                                color: KinrelColors.ember
                                    .withValues(alpha: progress),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(_dir * offset, 0),
                    child: child,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Scroll-to-bottom FAB (shared group + DM)
// ═════════════════════════════════════════════════════════════════

class ScrollToBottomFab extends StatelessWidget {
  const ScrollToBottomFab({super.key, required this.onTap});

  /// Scrolls the chat list back to the bottom (offset 0 in the
  /// reversed ListView).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 8,
      // Phase 6 — RepaintBoundary isolates the FAB so it doesn't repaint
      // when the message list repaints (and vice versa).
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ChatUi.chatCard,
              border: Border.all(
                  color: ChatUi.chatMenuBorder, width: ChatUi.menuBorderWidth),
            ),
            child: const Icon(
              Icons.keyboard_arrow_down,
              color: ChatUi.textSecondary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
