// lib/features/chat/presentation/widgets/typing_indicator.dart
//
// DAXELO KINREL — Shared typing indicator (group + DM)
//
// v143 / Signature §H — redesigned. Replaces the old "small avatar +
// bouncing dots" indicator with a small received-style bubble
// containing a CustomPainter that draws three linked nodes + two
// connecting edges. An AnimationController (1.2 s loop) rotates which
// node is brightest (nodeDim1 moves to the next node each third of
// the loop), wrapped in a RepaintBoundary so only the small painter
// re-paints on each tick.
//
// Visual rules (per implementation brief §H):
//   • Bubble: chatReceived fill, radius 14, padding 8 vertical /
//     14 left in group chat (12 left in direct chat), 12 right.
//   • Group chat only: a 3 dp wide band on the left in the typist's
//     kinship color (blended at 0.55 over chatBackground — same
//     treatment as the ghost bubble + received bubble's band).
//   • Inside: Row with 10 dp gap:
//     - Painter 46x12 dp with three nodes of radius 2.6 at x=5, 23,
//       41 (y=6) and two 1 dp lines between them in edgeDim.
//     - Text 12/400/textSubtitle: 'NAME is typing' (relationship label
//       or name), 'NAME and NAME are typing', 'Several people are
//       typing'; in direct chat just 'typing'.
//   • Animation: 1.2 s loop, rotates which node is brightest. The
//     brightest node uses nodeDim1 (the brightest of the three
//     static colors); the other two use nodeDim2 and nodeDim3 in
//     their static positions. Wrapped in a RepaintBoundary and
//     listened to only by the small painter.
//   • Start the controller only while the indicator is visible (the
//     screens gate this widget on someone-typing — same as before).
//   • When DeviceTierCache.instance.lowRam is true OR reduce motion
//     is on, draw the static frame and never start the controller.
//
// Backward compatibility: the existing `name` + `label` API is kept
// (the chat_screen + DM callers use it). New optional fields let the
// widget resolve the kinship band color + relationship label itself
// when the caller passes the typist's senderId + familyId.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/kinship/kinship_edge_style.dart';
import '../../../../core/utils/device_tier.dart';
import '../../../../core/utils/motion_preference.dart';
import '../../../family/data/relationship_label_provider.dart';
import '../chat_ui_tokens.dart';
import 'chat_meta.dart' show kinshipCategoryColor;

/// v143 / Signature §H — Typing indicator with linked-nodes painter.
///
/// Renders a small received-style bubble with a 46x12 painter of three
/// linked nodes + two edges. The brightest node rotates around the
/// three positions every 400 ms (1.2 s total loop). The painter is
/// wrapped in a RepaintBoundary so only it re-paints on each tick.
class TypingIndicator extends ConsumerStatefulWidget {
  const TypingIndicator({
    super.key,
    required this.name,
    required this.label,
    this.isDirectChat = false,
    this.familyId,
    this.typistSenderId,
  });

  /// Display name of the (primary) typist. Used for the kinship band
  /// color lookup when [familyId] + [typistSenderId] are set, and as
  /// the fallback label when [label] is empty.
  final String name;

  /// Rendered label text. The caller computes this (locale-aware) —
  /// e.g. 'NAME is typing', 'NAME and NAME are typing', 'Several
  /// people are typing', or just 'typing' in direct chat.
  final String label;

  /// Whether this is a 1-on-1 direct chat. When true: no kinship band,
  /// narrower left padding (12 vs 14).
  final bool isDirectChat;

  /// The family id used to resolve the typist's kinship color + label.
  /// Null (DM) → no band, plain received-bubble look.
  final String? familyId;

  /// The typist's auth.users.id (text). Used to resolve the kinship
  /// color + relationship label when [familyId] is set.
  final String? typistSenderId;

  @override
  ConsumerState<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends ConsumerState<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Start conditionally in didChangeDependencies so we can read
    // DeviceTierCache + MediaQuery first.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartOrStop();
  }

  void _maybeStartOrStop() {
    final lowRam = DeviceTierCache.instance.lowRam;
    final reduceMotion = MotionPreference.isReducedMotion(context);
    if (lowRam || reduceMotion) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      // Hold at frame 0 (nodeDim1 on the first node).
      if (!_controller.isCompleted) {
        _controller.value = 0.0;
      }
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowRam = DeviceTierCache.instance.lowRam;
    final reduceMotion = MotionPreference.isReducedMotion(context);
    final animate = !lowRam && !reduceMotion;

    // Resolve the typist's kinship band color + relationship label for
    // group chat. Skipped for DMs (no band).
    Color? bandColor;
    String? relationshipLabel;
    if (widget.familyId != null &&
        widget.typistSenderId != null &&
        !widget.isDirectChat) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: widget.familyId!, senderUserId: widget.typistSenderId!),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        final color = kinshipCategoryColor(category);
        if (color != null) {
          bandColor = color;
        }
      }
      if (bandColor == null) {
        // D3 unresolved — extended color.
        bandColor = KinrelColors.nodeExtended;
      }
      relationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: widget.familyId!, senderUserId: widget.typistSenderId!),
      ));
    }
    final blendedBand = bandColor == null
        ? null
        : ChatUi.blendOver(ChatUi.chatBackground, bandColor, 0.55);

    // The label prefers the relationship label when set (e.g. "Papa is
    // typing"); otherwise falls back to the caller-supplied [label].
    final String labelText;
    if (relationshipLabel != null && relationshipLabel.isNotEmpty) {
      // If the caller's label already starts with the name, replace it
      // with the relationship label.
      final name = widget.name;
      if (name.isNotEmpty && widget.label.startsWith(name)) {
        labelText = '$relationshipLabel${widget.label.substring(name.length)}';
      } else {
        labelText = widget.label; // caller's label is fine as-is
      }
    } else {
      labelText = widget.label;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          // Simpler layout: a Container with a BoxDecoration that
          // includes a 3 dp left Border in the band color. Achieves
          // the band-on-left look without an IntrinsicHeight+Row+
          // CrossAxisAlignment.stretch structure (which can blow up
          // inside the unbounded-height parent the typing indicator
          // is rendered in — the chat screen's Column gives its
          // non-flex children unbounded height, and the stretch +
          // width-only band Container has no intrinsic height for
          // IntrinsicHeight to read).
          padding: EdgeInsets.only(
            left: widget.isDirectChat
                ? 12
                : (blendedBand != null ? 14 : 14),
            right: 12,
            top: 8,
            bottom: 8,
          ),
          decoration: BoxDecoration(
            color: ChatUi.chatReceived,
            borderRadius: BorderRadius.circular(ChatUi.bubbleRadius),
            border: blendedBand != null
                ? Border(
                    left: BorderSide(
                      color: blendedBand,
                      width: ChatUi.bandWidth,
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The 46x12 linked-nodes painter. RepaintBoundary
              // so only the painter re-paints on each tick.
              RepaintBoundary(
                child: SizedBox(
                  width: ChatUi.typingPainterWidth,
                  height: ChatUi.typingPainterHeight,
                  child: CustomPaint(
                    painter: _LinkedNodesPainter(
                      controller: _controller,
                      animate: animate,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ChatUi.typingGap),
              Text(
                labelText,
                style: ChatUi.typingText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _LinkedNodesPainter — three nodes + two edges
// ═══════════════════════════════════════════════════════════════════════

class _LinkedNodesPainter extends CustomPainter {
  _LinkedNodesPainter({
    required this.controller,
    required this.animate,
  }) : super(repaint: animate ? controller : null);

  final Animation<double> controller;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    // Node positions per §H: x=5, 23, 41; y=6; radius 2.6.
    const nodeY = 6.0;
    const nodeR = 2.6;
    final xs = [5.0, 23.0, 41.0];

    // Edges between adjacent nodes — 1 dp line in edgeDim.
    final edgePaint = Paint()
      ..color = ChatUi.edgeDim
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (var i = 0; i < xs.length - 1; i++) {
      canvas.drawLine(
        Offset(xs[i] + nodeR, nodeY),
        Offset(xs[i + 1] - nodeR, nodeY),
        edgePaint,
      );
    }

    // Node colors — static palette nodeDim1, nodeDim2, nodeDim3 left to
    // right. The brightest (nodeDim1) ROTATES around the three positions
    // every 400 ms (1.2 s loop / 3 phases).
    final brightestIdx = animate ? ((controller.value * 3).floor() % 3) : 0;
    final nodeColors = [
      ChatUi.nodeDim2,
      ChatUi.nodeDim3,
      ChatUi.nodeDim1,
    ];
    // Re-arrange so the brightest is at position [brightestIdx].
    final arranged = <Color>[];
    for (var i = 0; i < 3; i++) {
      arranged.add(i == brightestIdx ? ChatUi.nodeDim1 : nodeColors[i]);
    }

    final nodePaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (var i = 0; i < xs.length; i++) {
      nodePaint.color = arranged[i];
      canvas.drawCircle(Offset(xs[i], nodeY), nodeR, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_LinkedNodesPainter oldDelegate) =>
      oldDelegate.animate != animate;
}
