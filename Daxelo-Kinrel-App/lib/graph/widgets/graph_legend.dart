// lib/graph/widgets/graph_legend.dart
//
// DAXELO KINREL — Graph Legend Panel (V2.1 Blueprint §17.3)
//
// A floating legend panel explaining the visual encoding of the family
// graph. Shows relationship type colors and edge line styles.
//
// v2.2: Now data-driven — the legend shows ONLY the kinship categories
// that are actually present in the current graph (passed in via
// [presentCategories]). This keeps the legend compact for small
// families and comprehensive for large ones.
//
// The legend is wired into the V2.1 engine view
// (family_graph_engine_view.dart) as a collapsible panel toggled by a
// "?" button. It delegates all color/edge-style resolution to the
// KinshipEdgeStyleResolver — the single source of truth for the
// 10-category system that covers all 5,359 Indian kinship types.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/kinship/kinship_edge_style.dart';

// ═══════════════════════════════════════════════════════════════════════
// GRAPH LEGEND
// ═══════════════════════════════════════════════════════════════════════

/// A floating legend panel explaining the visual encoding of the family graph.
///
/// Displays relationship type color swatches and edge line styles for the
/// kinship categories present in the current graph. The user can toggle
/// visibility with the "?" button.
///
/// [presentCategories] — the set of categories that actually appear in
/// the current graph. The legend only shows rows for these categories,
/// keeping the panel compact for small families.
class GraphLegend extends ConsumerWidget {
  /// Creates a graph legend panel.
  const GraphLegend({
    super.key,
    required this.isVisible,
    required this.onToggle,
    this.presentCategories = const <KinshipEdgeCategory>{},
  });

  /// Whether the legend panel is currently visible.
  final bool isVisible;

  /// Callback to toggle legend visibility.
  final VoidCallback onToggle;

  /// Which kinship categories are present in the current graph.
  /// If empty, all 10 categories are shown (the full reference legend).
  final Set<KinshipEdgeCategory> presentCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            // Toggle button (? icon) — 48×48 tap target (WCAG 2.5.5).
            if (!isVisible)
              Semantics(
                label: 'Toggle legend',
                button: true,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: GestureDetector(
                    onTap: onToggle,
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
            if (isVisible)
              Container(
                width: 260,
                constraints: const BoxConstraints(maxHeight: 420),
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
                            onPressed: onToggle,
                            padding: EdgeInsets.zero,
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
                          children: _buildLegendRows(),
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

  /// Builds the legend rows — node colors + edge styles for each
  /// present category (or all 10 if [presentCategories] is empty).
  List<Widget> _buildLegendRows() {
    final categories = presentCategories.isEmpty
        ? KinshipEdgeCategory.values
        : KinshipEdgeCategory.values
            .where((c) => presentCategories.contains(c))
            .toList();

    final rows = <Widget>[];

    // ── Node Colors section ──
    rows.add(_buildSectionTitle('Node Colors'));
    rows.add(const SizedBox(height: 8));
    for (final cat in categories) {
      if (cat == KinshipEdgeCategory.self) continue; // self is the viewer
      rows.add(_buildColorRow(
        _categoryLabel(cat),
        _categoryNodeColor(cat),
      ));
    }
    rows.add(const SizedBox(height: 16));

    // ── Edge Styles section ──
    rows.add(_buildSectionTitle('Edge Styles'));
    rows.add(const SizedBox(height: 8));
    for (final cat in categories) {
      if (cat == KinshipEdgeCategory.self) continue;
      final style = KinshipEdgeStyleResolver.styleForCategory(cat);
      rows.add(_buildEdgeRow(
        _categoryLabel(cat),
        _lineShapeLabel(style.lineShape),
        style.color,
        style.lineShape,
        style.dashPattern,
      ));
    }

    return rows;
  }

  /// Human-readable label for a kinship edge category.
  String _categoryLabel(KinshipEdgeCategory cat) {
    switch (cat) {
      case KinshipEdgeCategory.self:
        return 'Self';
      case KinshipEdgeCategory.parent:
        return 'Parent';
      case KinshipEdgeCategory.child:
        return 'Child';
      case KinshipEdgeCategory.sibling:
        return 'Sibling';
      case KinshipEdgeCategory.spouse:
        return 'Spouse';
      case KinshipEdgeCategory.grandparent:
        return 'Grandparent';
      case KinshipEdgeCategory.auntUncle:
        return 'Aunt / Uncle';
      case KinshipEdgeCategory.cousin:
        return 'Cousin';
      case KinshipEdgeCategory.inLaw:
        return 'In-Law';
      case KinshipEdgeCategory.extended:
        return 'Extended / Step';
      case KinshipEdgeCategory.indirect:
        return 'Indirect';
    }
  }

  /// Node color for a category (matches RelationshipColors in graph_node.dart).
  Color _categoryNodeColor(KinshipEdgeCategory cat) {
    switch (cat) {
      case KinshipEdgeCategory.self:
        return KinshipEdgeColors.self;
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
      case KinshipEdgeCategory.indirect:
        return KinshipEdgeColors.indirect;
    }
  }

  /// Human-readable label for a line shape.
  String _lineShapeLabel(KinshipLineShape shape) {
    switch (shape) {
      case KinshipLineShape.solidBezier:
        return 'Solid';
      case KinshipLineShape.solidExtendedBezier:
        return 'Solid';
      case KinshipLineShape.dashedArc:
        return 'Dashed Arc';
      case KinshipLineShape.dashedStraight:
        return 'Dashed';
      case KinshipLineShape.dashedShallowS:
        return 'Dashed S';
      case KinshipLineShape.wideArcBezier:
        return 'Wide Arc';
      case KinshipLineShape.dashedDefault:
        return 'Dashed';
    }
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

  Widget _buildEdgeRow(
    String label,
    String styleLabel,
    Color color,
    KinshipLineShape lineShape,
    List<double> dashPattern,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Line preview
          SizedBox(
            width: 28,
            height: 12,
            child: CustomPaint(
              painter: _EdgeStylePreviewPainter(
                color: color,
                lineShape: lineShape,
                dashPattern: dashPattern,
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
            styleLabel,
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
///
/// v2.2: Now uses the actual [KinshipLineShape] + [dashPattern] from the
/// KinshipEdgeStyleResolver so the preview matches the real edge rendering
/// exactly.
class _EdgeStylePreviewPainter extends CustomPainter {
  _EdgeStylePreviewPainter({
    required this.color,
    required this.lineShape,
    required this.dashPattern,
  });

  final Color color;
  final KinshipLineShape lineShape;
  final List<double> dashPattern;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;

    switch (lineShape) {
      case KinshipLineShape.solidBezier:
      case KinshipLineShape.solidExtendedBezier:
        // Solid S-curve
        final path = Path()
          ..moveTo(0, centerY)
          ..cubicTo(
            size.width * 0.3, centerY - 3,
            size.width * 0.7, centerY + 3,
            size.width, centerY,
          );
        canvas.drawPath(path, paint);
        break;

      case KinshipLineShape.dashedArc:
        // Dashed arc that bows above
        _drawDashedPath(
          canvas,
          paint,
          Path()
            ..moveTo(0, centerY + 2)
            ..quadraticBezierTo(
              size.width / 2, centerY - 6,
              size.width, centerY + 2,
            ),
        );
        break;

      case KinshipLineShape.dashedStraight:
        // Dashed horizontal line
        _drawDashedLine(canvas, paint, Offset(0, centerY), Offset(size.width, centerY));
        break;

      case KinshipLineShape.dashedShallowS:
        // Dashed shallow S-curve
        _drawDashedPath(
          canvas,
          paint,
          Path()
            ..moveTo(0, centerY)
            ..cubicTo(
              size.width * 0.3, centerY - 2,
              size.width * 0.7, centerY + 2,
              size.width, centerY,
            ),
        );
        break;

      case KinshipLineShape.wideArcBezier:
        // Wide-arc cubic bezier (solid)
        final path = Path()
          ..moveTo(0, centerY)
          ..cubicTo(
            size.width * 0.1, centerY - 8,
            size.width * 0.9, centerY + 8,
            size.width, centerY,
          );
        canvas.drawPath(path, paint);
        break;

      case KinshipLineShape.dashedDefault:
        // Standard dashed line
        _drawDashedLine(canvas, paint, Offset(0, centerY), Offset(size.width, centerY));
        break;
    }

    // Draw midpoint symbol for spouse (heart) and other categories (dot)
    // We can't know the category here without the full style, so we
    // skip the midpoint in the preview — the color + line shape is
    // enough to identify the category.
  }

  void _drawDashedLine(Canvas canvas, Paint paint, Offset start, Offset end) {
    if (dashPattern.isEmpty || dashPattern.length < 2) {
      canvas.drawLine(start, end, paint);
      return;
    }
    final dashWidth = dashPattern[0];
    final dashGap = dashPattern[1];
    final totalLen = (end - start).distance;
    final dx = (end.dx - start.dx) / totalLen;
    final dy = (end.dy - start.dy) / totalLen;
    double pos = 0;
    while (pos < totalLen) {
      final segEnd = (pos + dashWidth).clamp(0.0, totalLen);
      canvas.drawLine(
        Offset(start.dx + dx * pos, start.dy + dy * pos),
        Offset(start.dx + dx * segEnd, start.dy + dy * segEnd),
        paint,
      );
      pos += dashWidth + dashGap;
    }
  }

  void _drawDashedPath(Canvas canvas, Paint paint, Path path) {
    if (dashPattern.isEmpty || dashPattern.length < 2) {
      canvas.drawPath(path, paint);
      return;
    }
    // For curved paths, use PathMetrics to dash along the path.
    for (final metric in path.computeMetrics()) {
      double pos = 0;
      while (pos < metric.length) {
        final dashWidth = dashPattern[0];
        final dashGap = dashPattern[1];
        final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
        final extract = metric.extractPath(pos, segEnd);
        canvas.drawPath(extract, paint);
        pos += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeStylePreviewPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.lineShape != lineShape ||
        oldDelegate.dashPattern != dashPattern;
  }
}
