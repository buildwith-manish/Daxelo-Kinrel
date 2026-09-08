// lib/features/chat/presentation/widgets/chat_meta.dart
//
// DAXELO KINREL — Chat meta widgets extracted from chat_screen.dart (v5.184)
//
// Leaf widgets that have zero dependencies on _ChatScreenState:
//   - ReadReceipt (single/double tick)
//   - DoubleTickPainter (CustomPaint for tick marks)
//   - SendButton (Ignite gradient circle)
//   - HeaderActionButton (video/voice call buttons)
//   - AttachmentButton (attach file icon)
//   - MicButton (voice message trigger)
//   - StickerButton (emoji panel toggle)
//   - StickerPackButton (Giphy stickers)
//   - PollButton (poll composer)
//   - RecordingDot (pulsing red dot while recording)
//   - ReactionOverlay (emoji reaction popup)
//   - DateGroup (helper class for date separators)
//   - Tier3SwipeToReply (swipe-to-reply Dismissible wrapper)
//   - _kinshipCategoryColor (helper function for edge colors)
//
// Pure mechanical extraction — every class keeps its exact API.
// chat_screen.dart imports this file instead of defining them inline.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/kinship/kinship_edge_style.dart';
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
    final Color color;
    final bool showDouble;

    if (status == 'read' || isRead) {
      color = KinrelColors.gold;
      showDouble = true;
    } else if (status == 'delivered') {
      color = KinrelColors.textDim;
      showDouble = true;
    } else {
      color = KinrelColors.textDim;
      showDouble = false;
    }

    return SizedBox(
      width: showDouble ? 16 : 10,
      height: 10,
      child: CustomPaint(painter: DoubleTickPainter(color: color, showDouble: showDouble)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Double Tick Painter
// ═══════════════════════════════════════════════════════════════════════

class DoubleTickPainter extends CustomPainter {
  const DoubleTickPainter({required this.color, this.showDouble = true});

  final Color color;
  final bool showDouble;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (showDouble) {
      final path1 = Path();
      path1.moveTo(0, size.height * 0.55);
      path1.lineTo(size.width * 0.2, size.height * 0.85);
      path1.lineTo(size.width * 0.42, size.height * 0.15);

      final path2 = Path();
      path2.moveTo(size.width * 0.35, size.height * 0.55);
      path2.lineTo(size.width * 0.55, size.height * 0.85);
      path2.lineTo(size.width * 0.95, size.height * 0.15);

      canvas.drawPath(path1, paint);
      canvas.drawPath(path2, paint);
    } else {
      final path = Path();
      path.moveTo(0, size.height * 0.55);
      path.lineTo(size.width * 0.25, size.height * 0.85);
      path.lineTo(size.width * 0.95, size.height * 0.15);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DoubleTickPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.showDouble != showDouble;
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
// Send Button
// ═══════════════════════════════════════════════════════════════════════

class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isActive
              ? KinrelGradients.igniteGradient
              : LinearGradient(
                  colors: [const Color(0xFF202338), const Color(0xFF202338)],
                ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          size: 18,
          color: isActive ? Colors.white : KinrelColors.textDim,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header Action Button
// ═══════════════════════════════════════════════════════════════════════

class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Icon(
          icon,
          size: size,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Attachment Button
// ═══════════════════════════════════════════════════════════════════════

class AttachmentButton extends StatelessWidget {
  const AttachmentButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1D2E),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.75,
          ),
        ),
        child: Icon(
          Icons.attach_file_rounded,
          size: 21,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mic Button
// ═══════════════════════════════════════════════════════════════════════

class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: Icon(
          Icons.mic_rounded,
          size: 19,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sticker Button
// ═══════════════════════════════════════════════════════════════════════

class StickerButton extends StatelessWidget {
  const StickerButton({super.key, required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? KinrelColors.ember.withValues(alpha: 0.15)
              : const Color(0xFF1A1D2E),
          border: isActive
              ? Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.4),
                  width: 1)
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.75,
                ),
        ),
        child: Icon(
          Icons.emoji_emotions_rounded,
          size: 21,
          color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sticker Pack Button
// ═══════════════════════════════════════════════════════════════════════

class StickerPackButton extends StatelessWidget {
  const StickerPackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1D2E),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.75,
          ),
        ),
        child: Icon(
          Icons.emoji_emotions_outlined,
          size: 21,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Poll Button
// ═══════════════════════════════════════════════════════════════════════

class PollButton extends StatelessWidget {
  const PollButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1D2E),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.75,
          ),
        ),
        child: Icon(
          Icons.poll_rounded,
          size: 21,
          color: KinrelColors.textSilver,
        ),
      ),
    );
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
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          SizedBox.expand(),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202338),
                    borderRadius: BorderRadius.circular(KinrelRadius.xxl),
                    border: Border.all(
                      color: const Color(0xFF3A3A4A),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._emojis.map((emoji) {
                        return GestureDetector(
                          onTap: () => onEmojiSelected(emoji),
                          child: Container(
                            width: 42,
                            height: 42,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(shape: BoxShape.circle),
                            child: Center(
                              child: Text(emoji, style: TextStyle(fontSize: 24)),
                            ),
                          ),
                        );
                      }),
                      if (onMoreTap != null)
                        GestureDetector(
                          onTap: onMoreTap,
                          child: Container(
                            width: 42,
                            height: 42,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KinrelColors.darkElevated,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add,
                                color: KinrelColors.textSilver,
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

class SwipeToReply extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final direction = isMe
        ? DismissDirection.endToStart
        : DismissDirection.startToEnd;

    return Dismissible(
      key: ValueKey('swipe_reply_$messageId'),
      direction: direction,
      confirmDismiss: (dir) {
        onReply();
        return Future.value(false);
      },
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      background: _buildBackground(isMe),
      secondaryBackground: _buildBackground(isMe),
      child: child,
    );
  }

  Widget _buildBackground(bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 0 : 16,
          right: isMe ? 16 : 0,
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.ember.withValues(alpha: 0.15),
          ),
          child: Icon(
            Icons.reply_rounded,
            size: 22,
            color: KinrelColors.ember,
          ),
        ),
      ),
    );
  }
}
