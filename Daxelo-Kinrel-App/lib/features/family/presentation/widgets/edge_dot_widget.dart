// lib/features/family/presentation/widgets/edge_dot_widget.dart
//
// DAXELO KINREL — Edge Dot Widget (v2)
//
// v2 (2026-06-23): Now takes a [KinshipEdgeCategory] and renders the
// correct color + symbol per the central spec:
//   • spouse → PINK heart (always pink, regardless of edge color)
//   • every other category (except indirect) → filled dot in the
//     category color, with a glow halo and a subtle white center
//     highlight
//
// The dot/heart is now drawn in the CATEGORY color, not always orange.
// Parent=blue, Child=pink, Sibling=purple, Grandparent=indigo,
// Aunt/Uncle=cyan, Cousin=emerald, In-Law=amber, Extended=slate.
//
// Public API: const EdgeDotWidget({ ..., required category }).
// The legacy [isSpouse] flag is still accepted but ignored if
// [category] is also supplied (so old call sites keep working).

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/kinship/heart_shape.dart';
import '../../../../core/kinship/kinship_edge_style.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE DOT WIDGET
// ═══════════════════════════════════════════════════════════════════════

class EdgeDotWidget extends StatefulWidget {
  const EdgeDotWidget({
    super.key,
    required this.dotPosition,
    required this.isSelected,
    required this.onTap,
    this.category,
    this.isSpouse = false,
    this.relationshipKey,
  });

  /// The midpoint position of the edge (canvas-space).
  final Offset dotPosition;

  /// Whether this dot is currently selected.
  final bool isSelected;

  /// Callback when the dot is tapped.
  final VoidCallback onTap;

  /// Edge category — drives the color + symbol choice. When null, the
  /// widget falls back to [relationshipKey] (and then [isSpouse]).
  final KinshipEdgeCategory? category;

  /// Legacy flag (kept for backward compatibility). Ignored if
  /// [category] is non-null.
  final bool isSpouse;

  /// Relationship key — used as a fallback when [category] is null so
  /// the widget can still classify via [KinshipEdgeClassifier].
  final String? relationshipKey;

  @override
  State<EdgeDotWidget> createState() => _EdgeDotWidgetState();
}

class _EdgeDotWidgetState extends State<EdgeDotWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    if (widget.isSelected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant EdgeDotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Resolves the effective category — falls back through the legacy
  /// flags so any existing call site works.
  KinshipEdgeCategory get _effectiveCategory {
    if (widget.category != null) return widget.category!;
    if (widget.relationshipKey != null && widget.relationshipKey!.isNotEmpty) {
      return KinshipEdgeClassifier.classify(widget.relationshipKey!);
    }
    return widget.isSpouse
        ? KinshipEdgeCategory.spouse
        : KinshipEdgeCategory.extended;
  }

  @override
  Widget build(BuildContext context) {
    final category = _effectiveCategory;
    final style = KinshipEdgeStyleResolver.styleForCategory(category);

    final Widget dotChild;
    switch (style.midpointSymbol) {
      case KinshipMidpointSymbol.heart:
        dotChild = _buildHeart(style.midpointColor);
        break;
      case KinshipMidpointSymbol.dot:
        dotChild = _buildCircleDot(style.midpointColor);
        break;
      case KinshipMidpointSymbol.none:
        // Indirect connections get no visible dot — just a transparent
        // tap target so the user can still open the popup.
        dotChild = const SizedBox(width: 16, height: 16);
        break;
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32.0,
        height: 32.0,
        alignment: Alignment.center,
        color: Colors.transparent,
        child: widget.isSelected
            ? AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: child,
                  );
                },
                child: dotChild,
              )
            : dotChild,
      ),
    );
  }

  // ── Circle Dot (parent/child/sibling/grandparent/aunt-uncle/cousin/in-law/extended) ──

  Widget _buildCircleDot(Color color) {
    final double innerRadius = widget.isSelected ? 7.0 : 5.0;
    final double outerRadius = widget.isSelected ? 11.0 : 9.0;
    final double glowAlpha = widget.isSelected ? 0.4 : 0.2;

    return CustomPaint(
      size: Size(outerRadius * 2, outerRadius * 2),
      painter: _CircleDotPainter(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        glowAlpha: glowAlpha,
        color: color,
      ),
    );
  }

  // ── Heart (spouse) ──────────────────────────────────────────────────
  //
  // v89: Delegates to [HeartShape.drawHeart] so the widget overlay and
  // the canvas painter produce pixel-identical hearts. The old
  // implementation drew two overlapping circles + a tiny triangle,
  // which visually collapsed to a pink blob at any zoomed-out view.
  // The new implementation builds the heart from two cubic bezier
  // curves — a proper, recognizable heart silhouette at all zoom levels.

  Widget _buildHeart(Color color) {
    return CustomPaint(
      size: const Size(32, 32),
      painter: _HeartPainter(color: color),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CIRCLE DOT PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _CircleDotPainter extends CustomPainter {
  _CircleDotPainter({
    required this.innerRadius,
    required this.outerRadius,
    required this.glowAlpha,
    required this.color,
  });

  final double innerRadius;
  final double outerRadius;
  final double glowAlpha;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer glow halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, glowPaint);

    // Inner solid circle
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, fillPaint);

    // Border ring (uses darkCard for contrast against any edge color)
    final borderPaint = Paint()
      ..color = KinrelColors.darkCard
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, innerRadius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleDotPainter oldDelegate) {
    return oldDelegate.innerRadius != innerRadius ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.glowAlpha != glowAlpha ||
        oldDelegate.color != color;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HEART PAINTER (spouse midpoint) — v89 rewrite
// ═══════════════════════════════════════════════════════════════════════
//
// Delegates to [HeartShape.drawHeart] so this painter renders the
// exact same heart as the canvas painter in family_tree_painter.dart.
// The heart fills ~25×23 dp inside the 32×32 canvas (with a 5 dp glow
// halo extending slightly beyond).

class _HeartPainter extends CustomPainter {
  const _HeartPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    HeartShape.drawHeart(
      canvas: canvas,
      center: center,
      size: size.shortestSide,
      color: color,
    );
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) => old.color != color;
}
