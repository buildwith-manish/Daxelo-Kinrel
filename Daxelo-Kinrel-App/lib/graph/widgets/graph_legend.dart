// lib/graph/widgets/graph_legend.dart
//
// DAXELO KINREL — Graph Legend Panel (V2.1 Blueprint §17.3)
//
// A floating legend panel explaining the visual encoding of the family
// graph. Shows relationship type colors and edge line styles.
// Positioned bottom-left, collapsible via a "?" icon button. Dark theme.
// Wrapped in RepaintBoundary.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import 'graph_node.dart' show RelationshipColors;

// ═══════════════════════════════════════════════════════════════════════
// GRAPH LEGEND
// ═══════════════════════════════════════════════════════════════════════

/// A floating legend panel explaining the visual encoding of the family graph.
///
/// Displays relationship type color swatches and edge line styles.
/// Auto-opens for 5 seconds on first visit only, then collapses.
/// The user can toggle visibility with the "?" button.
class GraphLegend extends ConsumerStatefulWidget {
  /// Creates a graph legend panel.
  const GraphLegend({
    super.key,
    required this.isVisible,
    required this.onToggle,
  });

  /// Whether the legend panel is currently visible.
  final bool isVisible;

  /// Callback to toggle legend visibility.
  final VoidCallback onToggle;

  @override
  ConsumerState<GraphLegend> createState() => _GraphLegendState();
}

class _GraphLegendState extends ConsumerState<GraphLegend> {
  // Auto-open on first visit removed — legend only opens via user tap on "?" button.

  @override
  Widget build(BuildContext context) {
    // Directional positioning so the legend hugs the leading edge in LTR
    // (left:16) and the trailing edge in RTL (right:16). Must stay a direct
    // child of Stack — Positioned only works as an immediate child.
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;
    return Positioned(
      bottom: 80,
      left: isRtl ? null : 16,
      right: isRtl ? 16 : null,
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle button (? icon)
            // Accessibility: 48×48 tap target (WCAG 2.5.5) wrapped in a
            // Semantics button so screen readers announce "Toggle legend".
            if (!widget.isVisible)
              Semantics(
                label: 'Toggle legend',
                button: true,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: GestureDetector(
                    onTap: widget.onToggle,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: KinrelColors.darkCard.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: KinrelColors.border),
                      ),
                      child: const Center(
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Legend panel
            if (widget.isVisible)
              Container(
                width: 240,
                constraints: const BoxConstraints(maxHeight: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: KinrelColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    // Directional padding so RTL layouts mirror correctly.
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 14,
                        top: 12,
                        end: 8,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Legend',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                          const Spacer(),

                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: KinrelColors.textDim,
                            ),
                            onPressed: widget.onToggle,
                            padding: EdgeInsets.zero,
                            // 48×48 minimum tap target (WCAG 2.5.5).
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: KinrelColors.border),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Node colors section
                            _buildSectionTitle('Node Colors'),
                            const SizedBox(height: 8),
                            _buildColorRow('Self', RelationshipColors.self),
                            _buildColorRow('Parent', RelationshipColors.parent),
                            _buildColorRow('Sibling', RelationshipColors.sibling),
                            _buildColorRow('Child', RelationshipColors.child),
                            _buildColorRow('Spouse', RelationshipColors.spouse),
                            _buildColorRow('Grandparent', RelationshipColors.grandparent),
                            _buildColorRow('Aunt/Uncle', RelationshipColors.auntUncle),
                            _buildColorRow('Cousin', RelationshipColors.cousin),
                            _buildColorRow('In-Law', RelationshipColors.inLaw),
                            _buildColorRow('Extended', RelationshipColors.extended),
                            const SizedBox(height: 16),

                            // Edge styles section
                            _buildSectionTitle('Edge Styles'),
                            const SizedBox(height: 8),
                            _buildEdgeRow('Parent-Child', 'Solid', KinrelColors.graphEdgeOrange),
                            _buildEdgeRow('Sibling', 'Dashed', KinrelColors.nodeSibling),
                            _buildEdgeRow('Marriage', 'Connector', KinrelColors.spouseHeartColor),
                            _buildEdgeRow('Extended', 'Curved', KinrelColors.nodeExtended),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: KinrelColors.textDim,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildColorRow(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeRow(String label, String style, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Line preview
          SizedBox(
            width: 24,
            height: 2,
            child: CustomPaint(
              painter: _EdgeStylePreviewPainter(
                color: color,
                style: style,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          Text(
            style,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE STYLE PREVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// Small CustomPainter that renders a preview of an edge line style.
class _EdgeStylePreviewPainter extends CustomPainter {
  _EdgeStylePreviewPainter({
    required this.color,
    required this.style,
  });

  final Color color;
  final String style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (style == 'Dashed') {
      // Draw dashed line
      const dashWidth = 3.0;
      const dashGap = 2.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
          paint,
        );
        x += dashWidth + dashGap;
      }
    } else if (style == 'Connector') {
      // Draw marriage connector with small ring
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width * 0.4, size.height / 2),
        paint,
      );
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height / 2),
        2.5,
        paint,
      );
      canvas.drawLine(
        Offset(size.width * 0.6, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    } else if (style == 'Curved') {
      // Draw curved line
      final path = Path()
        ..moveTo(0, size.height)
        ..quadraticBezierTo(
          size.width / 2, 0,
          size.width, size.height,
        );
      canvas.drawPath(path, paint);
    } else {
      // Solid line
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeStylePreviewPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.style != style;
  }
}
