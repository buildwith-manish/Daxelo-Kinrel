// lib/features/family/presentation/widgets/edge_dot_widget.dart
//
// DAXELO KINREL — Edge Dot Widget
//
// An animated dot widget that appears at the midpoint of each graph edge.
// Tapping the dot reveals the relationship popup.
//
// States:
//   Default  : 10px diameter, KinrelColors.textDim, border 2px KinrelColors.darkCard
//   Selected : 14px diameter, KinrelColors.orange, border 2px KinrelColors.darkCard,
//              orange glow shadow, pulse animation
//   Hover    : 12px diameter, KinrelColors.amber (tap area on mobile)

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE DOT WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// An animated edge dot widget that appears at the midpoint of a graph edge.
///
/// Usage:
/// ```dart
/// Positioned(
///   left: dotPosition.dx - 16,
///   top: dotPosition.dy - 16,
///   child: EdgeDotWidget(
///     dotPosition: dotPosition,
///     isSelected: selectedEdgeId == edge.id,
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
  });

  /// The midpoint position of the edge.
  final Offset dotPosition;

  /// Whether this dot is currently selected.
  final bool isSelected;

  /// Callback when the dot is tapped.
  final VoidCallback onTap;

  @override
  State<EdgeDotWidget> createState() => _EdgeDotWidgetState();
}

class _EdgeDotWidgetState extends State<EdgeDotWidget>
    with SingleTickerProviderStateMixin {
  // ── Animation Controller ───────────────────────────────────────────

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ── Hover State ────────────────────────────────────────────────────

  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
    // Determine dot size and color based on state
    final double dotSize;
    final Color dotColor;
    final List<BoxShadow>? boxShadow;

    if (widget.isSelected) {
      dotSize = 14.0;
      dotColor = KinrelColors.orange;
      boxShadow = [
        BoxShadow(
          color: KinrelColors.orange.withValues(alpha: 0.5),
          blurRadius: 8.0,
          spreadRadius: 2.0,
        ),
      ];
    } else if (_isHovered) {
      dotSize = 12.0;
      dotColor = KinrelColors.amber;
      boxShadow = null;
    } else {
      dotSize = 10.0;
      dotColor = KinrelColors.textDim;
      boxShadow = null;
    }

    final Widget dotChild = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        border: Border.all(
          color: KinrelColors.darkCard,
          width: 2.0,
        ),
        boxShadow: boxShadow,
      ),
    );

    // The outer 32x32 tap target centered on the dot
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
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
      ),
    );
  }
}
