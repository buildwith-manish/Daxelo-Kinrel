// lib/shared/widgets/kinrel_icon.dart
//
// DAXELO KINREL — K-graph Icon Widget
//
// A self-contained widget wrapping [KinrelIconPainter] with
// optional tap handling, animation support, and semantic labeling.
//
// Usage:
// ```dart
// KinrelIcon(size: 64, palette: KinrelIconPalette.orange)
// KinrelIcon(size: 20) // auto mini mode
// KinrelIcon(size: 48, animated: true, onTap: () => ...)
// ```

import 'package:flutter/material.dart';
import '../painters/kinrel_icon_painter.dart';

/// KINREL K-graph Icon Widget.
///
/// Renders the KINREL brand icon as a custom-painted widget.
/// Automatically switches to a simplified 3-stroke version
/// at sizes ≤24px for legibility.
///
/// Supports 4 palettes, optional animation, and tap handling.
class KinrelIcon extends StatelessWidget {
  /// Icon size in logical pixels. Default 48.
  final double size;

  /// Color palette variant. Default orange.
  final KinrelIconPalette palette;

  /// Whether to show the pulse/ripple animation. Default false.
  final bool animated;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// Optional semantic label for accessibility.
  final String? semanticLabel;

  const KinrelIcon({
    super.key,
    this.size = 48,
    this.palette = KinrelIconPalette.orange,
    this.animated = false,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'KINREL icon',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: animated
            ? _AnimatedKinrelIcon(size: size, palette: palette)
            : CustomPaint(
                size: Size(size, size),
                painter: KinrelIconPainter(
                  palette: palette,
                  animated: false,
                ),
              ),
      ),
    );
  }
}

/// Animated variant that drives a repeating ripple on the center hub node.
class _AnimatedKinrelIcon extends StatefulWidget {
  final double size;
  final KinrelIconPalette palette;

  const _AnimatedKinrelIcon({
    required this.size,
    required this.palette,
  });

  @override
  State<_AnimatedKinrelIcon> createState() => _AnimatedKinrelIconState();
}

class _AnimatedKinrelIconState extends State<_AnimatedKinrelIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: KinrelIconPainter(
            palette: widget.palette,
            animated: true,
            animationValue: _controller.value,
          ),
        );
      },
    );
  }
}
