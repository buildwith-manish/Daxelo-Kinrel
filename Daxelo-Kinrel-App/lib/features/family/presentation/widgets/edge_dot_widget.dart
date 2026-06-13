// lib/features/family/presentation/widgets/edge_dot_widget.dart
//
// DAXELO KINREL — Edge Dot Widget
//
// An animated dot widget that appears at the midpoint of each graph edge.
// Tapping the dot reveals the relationship popup.
//
// States:
//   Default  : Outer glow circle (alpha 0.2, r9) + inner solid circle (r5),
//              border 2px KinrelColors.darkCard
//   Selected : Same but radius scales to 7 with pulsing glow animation
//              (1.2s repeat, scale 1.0↔1.3)
//   Spouse   : Heart icon (two overlapping circles + triangle, size 14,
//              KinrelColors.orange) instead of circle dot
//
// The outer 32×32 tap target remains for touch accessibility.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE DOT WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// An animated edge dot widget that appears at the midpoint of a graph edge.
///
/// When [isSpouse] is true, shows a heart icon instead of a circle dot.
///
/// Usage:
/// ```dart
/// Positioned(
///   left: dotPosition.dx - 16,
///   top: dotPosition.dy - 16,
///   child: EdgeDotWidget(
///     dotPosition: dotPosition,
///     isSelected: selectedEdgeId == edge.id,
///     isSpouse: _spouseKeys.contains(edge.relationshipKey),
///     onTap: () => onEdgeTapped(edge.id),
///   ),
/// )
/// ```
class EdgeDotWidget extends StatefulWidget {
  const EdgeDotWidget({
    super.key,
    required this.dotPosition,
    required this.isSelected,
    required this.onTap,
    this.isSpouse = false,
  });

  /// The midpoint position of the edge.
  final Offset dotPosition;

  /// Whether this dot is currently selected.
  final bool isSelected;

  /// Callback when the dot is tapped.
  final VoidCallback onTap;

  /// When true, shows a heart icon instead of a circle dot.
  final bool isSpouse;

  @override
  State<EdgeDotWidget> createState() => _EdgeDotWidgetState();
}

class _EdgeDotWidgetState extends State<EdgeDotWidget>
    with SingleTickerProviderStateMixin {
  // ── Animation Controller ───────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Widget dotChild = widget.isSpouse
        ? _buildHeartDot()
        : _buildCircleDot();

    // The outer 32×32 tap target centered on the dot
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

  // ── Circle Dot (parent-child / sibling) ────────────────────────────

  /// Builds the default circle dot with outer glow and inner solid fill.
  ///
  /// Default: outer glow (alpha 0.2, radius 9) + inner solid (radius 5),
  ///          border 2px KinrelColors.darkCard
  /// Selected: same but radius scales to 7 (animated by parent)
  Widget _buildCircleDot() {
    final double innerRadius = widget.isSelected ? 7.0 : 5.0;
    final double outerRadius = widget.isSelected ? 11.0 : 9.0;
    final double glowAlpha = widget.isSelected ? 0.4 : 0.2;

    return CustomPaint(
      size: Size(outerRadius * 2, outerRadius * 2),
      painter: _CircleDotPainter(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        glowAlpha: glowAlpha,
      ),
    );
  }

  // ── Heart Dot (spouse) ─────────────────────────────────────────────

  /// Builds a small heart icon using two overlapping circles + a triangle.
  /// Size 14dp, KinrelColors.orange fill.
  Widget _buildHeartDot() {
    return CustomPaint(
      size: const Size(32, 32),
      painter: _SpouseDotPainter(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CIRCLE DOT PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter for the circle dot: outer glow + inner solid + border.
class _CircleDotPainter extends CustomPainter {
  _CircleDotPainter({
    required this.innerRadius,
    required this.outerRadius,
    required this.glowAlpha,
  });

  final double innerRadius;
  final double outerRadius;
  final double glowAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer glow halo
    final glowPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, glowPaint);

    // Inner solid circle
    final fillPaint = Paint()
      ..color = KinrelColors.orange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, fillPaint);

    // Border ring
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
        oldDelegate.glowAlpha != glowAlpha;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HEART DOT PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter for a small heart shape: two overlapping circles + triangle.
class _SpouseDotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Outer glow
    canvas.drawCircle(center, 10,
        Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.12));
    // Filled dot
    canvas.drawCircle(center, 5,
        Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.85));
    // White highlight
    canvas.drawCircle(center, 2.5,
        Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
