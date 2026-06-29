// lib/graph/widgets/graph_legend.dart
//
// DAXELO KINREL — Graph Legend Panel (V2.1 Blueprint §17.3)
//
// 8-section card grid + spouse cross-section row.
//
// Each section card shows:
//   - A filled circle in the section's node color
//   - An EdgeSamplePainter rendering the edge line style
//   - The hex color value + edge label
//
// The spouse row is a full-width card below the grid showing the
// dashed orange edge with a pink heart midpoint.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/kinship/kinship_edge_style.dart';
import '../rendering/node_render_coordinator.dart' show KeyStrategy;

// ═══════════════════════════════════════════════════════════════════════
// GRAPH LEGEND
// ═══════════════════════════════════════════════════════════════════════

/// A floating legend panel explaining the visual encoding of the family graph.
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
  /// If empty, all 8 sections + spouse are shown (full reference legend).
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
            // Toggle button (? icon)
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
                key: KeyStrategy.legendKey(),
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
                          children: [
                            // Section title
                            Text(
                              'V2.1 Sections',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.textDim,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 8-section card grid
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _buildSectionCards(),
                            ),
                            const SizedBox(height: 8),

                            // Spouse cross-section row
                            // BUG 3 FIX: Only show the spouse row when
                            // spouse edges are present in the graph (or
                            // when presentCategories is empty = full
                            // reference legend mode).
                            if (presentCategories.isEmpty ||
                                presentCategories
                                    .contains(KinshipEdgeCategory.spouse))
                              _buildSpouseRow(),
                            const SizedBox(height: 8),

                            // Footer note
                            Text(
                              'Dot opacity reflects edge alpha. '
                              'Core has no edge — it\'s the ego node '
                              'every other section radiates from.',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 9,
                                color: KinrelColors.textDim,
                                height: 1.3,
                              ),
                            ),
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

  /// Builds the 8 section cards.
  List<Widget> _buildSectionCards() {
    final sections = _sections;
    // Filter by presentCategories if non-empty.
    final visibleSections = presentCategories.isEmpty
        ? sections
        : sections
            .where((s) =>
                presentCategories.contains(s.category) ||
                s.category == KinshipEdgeCategory.self)
            .toList();

    return visibleSections.map((s) => _buildSectionCard(s)).toList();
  }

  /// Builds a single section card.
  Widget _buildSectionCard(_LegendSection section) {
    final cardWidth = (240 - 24 - 6) / 2.0; // ~105px
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: circle + section name
          Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: section.nodeColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: edge sample painter
          // BUG 1 FIX: ClipRect prevents the cousins arc (control point
          // at virtual y=-12) from overflowing into the title text above.
          ClipRect(
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(
                painter: _EdgeSamplePainter(section: section),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Row 3: hex color
          Text(
            _colorToHex(section.nodeColor),
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              color: KinrelColors.textDim,
            ),
          ),
          // Row 4: edge label
          if (section.edgeLabel != null)
            Text(
              section.edgeLabel!,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                color: KinrelColors.border,
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the spouse cross-section row (full-width card below the grid).
  Widget _buildSpouseRow() {
    final spouseSection = _LegendSection(
      name: 'spouse',
      category: KinshipEdgeCategory.spouse,
      nodeColor: KinrelColors.nodeSpouse,
      edgeColor: KinrelColors.nodeSpouse,
      edgeOpacity: 1.0,
      strokeWidth: 2.0,
      isDashed: true,
      dashLength: 6.0,
      gapLength: 4.0,
      isStraight: true,
      isCore: false,
      isHeart: true,
      midpointColor: KinrelColors.spouseHeartColor,
      midpointOpacity: 1.0,
      edgeLabel: 'dashedStraight',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          // Label
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'spouse',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                ),
              ),
              Text(
                '(cross-section)',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Edge sample
          // BUG 1 FIX: ClipRect for consistency + safety.
          Expanded(
            child: ClipRect(
              child: SizedBox(
                height: 30,
                child: CustomPaint(
                  painter: _EdgeSamplePainter(section: spouseSection),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Hex label
          Text(
            '#F97316 · #EC4899',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  /// Converts a Color to a hex string like "#0D9488".
  String _colorToHex(Color color) {
    final hex = color.toARGB32().toRadixString(16).toUpperCase();
    // Skip the alpha channel (first 2 chars) for display.
    return '#${hex.substring(2)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION DATA CLASS
// ═══════════════════════════════════════════════════════════════════════

/// Immutable description of a legend section's visual properties.
class _LegendSection {
  const _LegendSection({
    required this.name,
    required this.category,
    required this.nodeColor,
    required this.edgeColor,
    required this.edgeOpacity,
    required this.strokeWidth,
    required this.isDashed,
    this.dashLength = 0,
    this.gapLength = 0,
    required this.isStraight,
    required this.isCore,
    required this.isHeart,
    required this.midpointColor,
    required this.midpointOpacity,
    this.controlPoint,
    this.edgeLabel,
  });

  final String name;
  final KinshipEdgeCategory category;
  final Color nodeColor;
  final Color edgeColor;
  final double edgeOpacity;
  final double strokeWidth;
  final bool isDashed;
  final double dashLength;
  final double gapLength;
  final bool isStraight;
  final bool isCore;
  final bool isHeart;
  final Color midpointColor;
  final double midpointOpacity;
  final Offset? controlPoint; // for curved lines, in 140×44 canvas space
  final String? edgeLabel;
}

/// The 8 sections per the V2.1 spec.
List<_LegendSection> get _sections => [
      _LegendSection(
        name: 'core',
        category: KinshipEdgeCategory.self,
        nodeColor: KinrelColors.nodeSelf,
        edgeColor: const Color(0xFF475569),
        edgeOpacity: 1.0,
        strokeWidth: 1.2,
        isDashed: true,
        dashLength: 2.0,
        gapLength: 2.0,
        isStraight: false,
        isCore: true,
        isHeart: false,
        midpointColor: const Color(0xFF475569),
        midpointOpacity: 1.0,
        edgeLabel: null,
      ),
      _LegendSection(
        name: 'ancestors',
        category: KinshipEdgeCategory.grandparent,
        nodeColor: KinrelColors.nodeGrandparent,
        edgeColor: KinrelColors.nodeGrandparent,
        edgeOpacity: 0.75,
        strokeWidth: 2.0,
        isDashed: false,
        isStraight: false,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeGrandparent,
        midpointOpacity: 0.90,
        controlPoint: const Offset(70, 2),
        edgeLabel: 'solidExtendedBezier',
      ),
      _LegendSection(
        name: 'descendants',
        category: KinshipEdgeCategory.child,
        nodeColor: KinrelColors.nodeChild,
        edgeColor: KinrelColors.nodeChild,
        edgeOpacity: 0.85,
        strokeWidth: 2.0,
        isDashed: false,
        isStraight: false,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeChild,
        midpointOpacity: 1.0,
        controlPoint: const Offset(70, 8),
        edgeLabel: 'solidBezier',
      ),
      _LegendSection(
        name: 'paternal',
        category: KinshipEdgeCategory.parent,
        nodeColor: KinrelColors.nodeParent,
        edgeColor: KinrelColors.nodeParent,
        edgeOpacity: 0.85,
        strokeWidth: 2.0,
        isDashed: false,
        isStraight: false,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeParent,
        midpointOpacity: 1.0,
        controlPoint: const Offset(70, 8),
        edgeLabel: 'solidBezier',
      ),
      _LegendSection(
        name: 'maternal',
        category: KinshipEdgeCategory.parent,
        nodeColor: KinrelColors.nodeParent,
        edgeColor: KinrelColors.nodeParent,
        edgeOpacity: 0.85,
        strokeWidth: 2.0,
        isDashed: false,
        isStraight: false,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeParent,
        midpointOpacity: 1.0,
        controlPoint: const Offset(70, 8),
        edgeLabel: 'solidBezier',
      ),
      _LegendSection(
        name: 'inlaws',
        category: KinshipEdgeCategory.inLaw,
        nodeColor: KinrelColors.nodeInLaw,
        edgeColor: KinrelColors.nodeInLaw,
        edgeOpacity: 0.70,
        strokeWidth: 2.0,
        isDashed: true,
        dashLength: 5.0,
        gapLength: 4.0,
        isStraight: true,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeInLaw,
        midpointOpacity: 0.85,
        edgeLabel: 'dashedStraight',
      ),
      _LegendSection(
        name: 'cousins',
        category: KinshipEdgeCategory.cousin,
        nodeColor: KinrelColors.nodeCousin,
        edgeColor: KinrelColors.nodeCousin,
        edgeOpacity: 0.70,
        strokeWidth: 2.5,
        isDashed: false,
        isStraight: false,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeCousin,
        midpointOpacity: 0.85,
        controlPoint: const Offset(70, -12),
        edgeLabel: 'wideArcBezier',
      ),
      _LegendSection(
        name: 'step_adoptive',
        category: KinshipEdgeCategory.extended,
        nodeColor: KinrelColors.nodeExtended,
        edgeColor: KinrelColors.nodeExtended,
        edgeOpacity: 0.45,
        strokeWidth: 1.5,
        isDashed: true,
        dashLength: 4.0,
        gapLength: 4.0,
        isStraight: true,
        isCore: false,
        isHeart: false,
        midpointColor: KinrelColors.nodeExtended,
        midpointOpacity: 0.60,
        edgeLabel: 'dashedDefault',
      ),
    ];

// ═══════════════════════════════════════════════════════════════════════
// EDGE SAMPLE PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// Single CustomPainter that handles all visual variants for the legend.
///
/// Canvas space is 140×44 (the card is ~105px wide but the painter uses
/// a virtual 140px coordinate space that scales to fit).
class _EdgeSamplePainter extends CustomPainter {
  _EdgeSamplePainter({required this.section});

  final _LegendSection section;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale the 140×44 virtual canvas to the actual size.
    final scaleX = size.width / 140.0;
    final scaleY = size.height / 44.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (section.isCore) {
      _drawCore(canvas);
    } else if (section.isStraight) {
      _drawStraightLine(canvas);
      _drawMidpointStraight(canvas);
    } else {
      _drawCurvedLine(canvas);
      _drawMidpointCurved(canvas);
    }

    canvas.restore();
  }

  /// Core section: dashed hollow circle at center + "self / root" text.
  void _drawCore(Canvas canvas) {
    final paint = Paint()
      ..color = section.edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = section.strokeWidth;

    final center = const Offset(70, 18);
    final radius = 12.0;

    // Build a circle path and dash it via PathMetrics.
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    if (section.isDashed) {
      for (final metric in circlePath.computeMetrics()) {
        double pos = 0;
        while (pos < metric.length) {
          final segEnd =
              (pos + section.dashLength).clamp(0.0, metric.length);
          canvas.drawPath(metric.extractPath(pos, segEnd), paint);
          pos += section.dashLength + section.gapLength;
        }
      }
    } else {
      canvas.drawPath(circlePath, paint);
    }

    // "self / root" text below the circle.
    _drawText(
      canvas,
      'self / root',
      const Offset(70, 36),
      8,
      section.edgeColor,
    );
  }

  /// Straight line: horizontal at mid-height, optionally dashed.
  void _drawStraightLine(Canvas canvas) {
    final paint = Paint()
      ..color = section.edgeColor.withValues(alpha: section.edgeOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = section.strokeWidth
      ..strokeCap = StrokeCap.round;

    const start = Offset(10, 22);
    const end = Offset(130, 22);

    if (section.isDashed) {
      final path = Path()..moveTo(start.dx, start.dy)..lineTo(end.dx, end.dy);
      for (final metric in path.computeMetrics()) {
        double pos = 0;
        while (pos < metric.length) {
          final segEnd =
              (pos + section.dashLength).clamp(0.0, metric.length);
          canvas.drawPath(metric.extractPath(pos, segEnd), paint);
          pos += section.dashLength + section.gapLength;
        }
      }
    } else {
      canvas.drawLine(start, end, paint);
    }
  }

  /// Curved line: quadratic Bézier from (10,38) through control point to (130,38).
  void _drawCurvedLine(Canvas canvas) {
    final paint = Paint()
      ..color = section.edgeColor.withValues(alpha: section.edgeOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = section.strokeWidth
      ..strokeCap = StrokeCap.round;

    final cp = section.controlPoint ?? const Offset(70, 8);
    final path = Path()
      ..moveTo(10, 38)
      ..quadraticBezierTo(cp.dx, cp.dy, 130, 38);

    // Solid (no dash) for curved lines per spec.
    canvas.drawPath(path, paint);
  }

  /// Midpoint dot for straight lines.
  void _drawMidpointStraight(Canvas canvas) {
    if (section.isHeart) {
      _drawHeart(canvas, const Offset(70, 22));
    } else {
      final paint = Paint()
        ..color = section.midpointColor
          .withValues(alpha: section.midpointOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(70, 22), 3.0, paint);
    }
  }

  /// Midpoint dot for curved lines — uses Bézier t=0.5 formula.
  void _drawMidpointCurved(Canvas canvas) {
    // B(0.5) = 0.25·P0 + 0.5·CP + 0.25·P1
    final cp = section.controlPoint ?? const Offset(70, 8);
    final midX = 0.25 * 10 + 0.5 * cp.dx + 0.25 * 130;
    final midY = 0.25 * 38 + 0.5 * cp.dy + 0.25 * 38;

    final paint = Paint()
      ..color = section.midpointColor
          .withValues(alpha: section.midpointOpacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), 3.0, paint);
  }

  /// Draws a heart icon at [center] using TextPainter + Material Icons.
  void _drawHeart(Canvas canvas, Offset center) {
    _drawIcon(
      canvas,
      Icons.favorite,
      center,
      14.0,
      section.midpointColor
          .withValues(alpha: section.midpointOpacity.clamp(0.0, 1.0)),
    );
  }

  /// Draws a text label using TextPainter.
  void _drawText(
      Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: fontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    // Center the text at [center].
    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2,
      ),
    );
  }

  /// Draws an icon using TextPainter + Material Icons font.
  void _drawIcon(
      Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _EdgeSamplePainter oldDelegate) {
    // BUG 2 FIX: Compare by name + edgeLabel + isCore together, which
    // is guaranteed unique per section. Comparing only by name is
    // fragile — paternal and maternal both share KinshipEdgeCategory.parent
    // and may not repaint correctly when the filter changes.
    return oldDelegate.section.name != section.name ||
        oldDelegate.section.edgeLabel != section.edgeLabel ||
        oldDelegate.section.isCore != section.isCore;
  }
}
