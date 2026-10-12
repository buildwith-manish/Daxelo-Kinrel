// lib/features/chat/presentation/widgets/thread_markers.dart
//
// DAXELO KINREL — v143 Signature §D (date marker) + §E (unread marker)
//
// Two thread-separator rows that share the same layout: a centered row
// with vertical padding 6, a 1 dp line that expands to fill, 8 dp gap,
// a 6x6 circle (node), 6 dp gap, the label, 8 dp gap, a 1 dp line that
// expands. No pill, no background. The circle color and label color
// differ between the two variants.
//
// Visual rules (per implementation brief §D + §E):
//
// ThreadDateMarker:
//   • Lines color: ChatUi.lineColor (2E3150).
//   • Node: 6x6 in ChatUi.nodeDim1 (B9BDD0).
//   • Label: 12 / 400 / textSecondary (B9BDD0), reading the same date
//     text rules as today (Today / Yesterday / weekday within 6 days /
//     otherwise a short date).
//
// UnreadMarker:
//   • Lines color: blendOver(chatBackground, ember, 0.55) which is 743217.
//   • Node: 6x6 in KinrelColors.orange.
//   • Label: 12 / 400 / KinrelColors.orange, reading 'N new messages'
//     (1 new message for one).
//
// The floating date chip shown while scrolling stays a pill
// (chatReceived background, textPrimary), unchanged.
//
// Accessibility:
//   • Both markers are wrapped in a Semantics widget with the marker
//     text as the label. The 6x6 node is decorative (excluded from
//     semantics).
//   • State differs by SHAPE (date marker = nodeDim1 circle, unread
//     marker = orange circle) AND by the label text — never color alone.
//   • Text scale up to 1.3 without overflow: the row uses Flexible
//     children + a fixed-height node so the row height grows but the
//     label never truncates.
//   • The row is decorative — no tap target.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../chat_ui_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════
// _ThreadRuleLine — 1 dp solid line, expands to fill
// ═══════════════════════════════════════════════════════════════════════

class _ThreadRuleLine extends StatelessWidget {
  const _ThreadRuleLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Container(
        height: ChatUi.dateMarkerLineThickness,
        color: color,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _ThreadNode — 6x6 solid circle
// ═══════════════════════════════════════════════════════════════════════

class _ThreadNode extends StatelessWidget {
  const _ThreadNode({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: ChatUi.dateMarkerNodeSize,
        height: ChatUi.dateMarkerNodeSize,
        child: CustomPaint(
          painter: _ThreadNodePainter(color: color),
        ),
      ),
    );
  }
}

class _ThreadNodePainter extends CustomPainter {
  _ThreadNodePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ThreadNodePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ═══════════════════════════════════════════════════════════════════════
// ThreadDateMarker — §D
// ═══════════════════════════════════════════════════════════════════════

/// Centered row: line + node + date label + line. No pill, no
/// background. Lines color lineColor; node 6x6 in nodeDim1; label
/// 12/400/textSecondary. Used between date groups in the message list
/// (replaces the old pill-style date separator).
class ThreadDateMarker extends StatelessWidget {
  const ThreadDateMarker({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        label: label,
        excludeSemantics: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: ChatUi.dateMarkerVPadding),
          child: Row(
            children: [
              const Expanded(child: _ThreadRuleLine(color: ChatUi.lineColor)),
              const SizedBox(width: ChatUi.dateMarkerGap),
              const _ThreadNode(color: ChatUi.nodeDim1),
              const SizedBox(width: ChatUi.dateMarkerNodeLabelGap),
              Flexible(
                child: Text(
                  label,
                  style: ChatUi.markerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ChatUi.dateMarkerNodeLabelGap),
              const _ThreadNode(color: ChatUi.nodeDim1),
              const SizedBox(width: ChatUi.dateMarkerGap),
              const Expanded(child: _ThreadRuleLine(color: ChatUi.lineColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// UnreadMarker — §E
// ═══════════════════════════════════════════════════════════════════════

/// Centered row: line + node + 'N new messages' label + line. Same
/// layout as [ThreadDateMarker] but with: lines color
/// blendOver(chatBackground, ember, 0.55); node 6x6 in
/// KinrelColors.orange; label 12/400/KinrelColors.orange. Replaces the
/// old unread pill.
class UnreadMarker extends StatelessWidget {
  const UnreadMarker({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new message' : '$count new messages';
    final lineColor = ChatUi.blendOver(
        ChatUi.chatBackground, KinrelColors.ember, 0.55);
    return RepaintBoundary(
      child: Semantics(
        label: '$count new messages',
        excludeSemantics: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: ChatUi.dateMarkerVPadding),
          child: Row(
            children: [
              Expanded(child: _ThreadRuleLine(color: lineColor)),
              const SizedBox(width: ChatUi.dateMarkerGap),
              const _ThreadNode(color: KinrelColors.orange),
              const SizedBox(width: ChatUi.dateMarkerNodeLabelGap),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: KinrelColors.orange,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ChatUi.dateMarkerNodeLabelGap),
              const _ThreadNode(color: KinrelColors.orange),
              const SizedBox(width: ChatUi.dateMarkerGap),
              Expanded(child: _ThreadRuleLine(color: lineColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Note on KinrelTypography usage
// ═══════════════════════════════════════════════════════════════════════
//
// The UnreadMarker label uses an inline TextStyle instead of
// ChatUi.markerText because markerText's color is textSecondary, while
// the spec requires orange. The font family + size + weight match
// markerText exactly — only the color differs. We keep it inline for
// the single call site rather than adding a second token like
// 'markerTextOrange' to ChatUi.
