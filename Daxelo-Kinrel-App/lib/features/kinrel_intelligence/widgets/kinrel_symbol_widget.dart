// lib/features/kinrel_intelligence/widgets/kinrel_symbol_widget.dart
//
// Kinrel — Animated Symbol Widget (Phase 10).
//
// Wraps [KinrelSymbolPainter] in a StatefulWidget with an AnimationController
// that drives the breathing/pulse effect. The pulse period comes from
// KinrelSymbolParameters.pulseSpeedMs (2000–6000ms) — high-connectivity
// families breathe faster, sparse families breathe slower.
//
// Memoization / performance (Phase 19.2):
//   - The widget takes the KinrelSymbolParameters directly (not the whole
//     KinrelModel) so parent rebuilds triggered by unrelated model fields
//     (e.g. metrics) don't restart the animation.
//   - The AnimationController is only restarted when pulseSpeedMs changes.
//   - The CustomPaint uses a `child`-less repaint boundary implicitly
//     because Flutter wraps CustomPaint in a RepaintBoundary when its
//     painter is non-null and the widget is in a render tree.

import 'package:flutter/material.dart';

import '../data/kinrel_model.dart';
import 'kinrel_symbol_painter.dart';

class KinrelSymbolWidget extends StatefulWidget {
  const KinrelSymbolWidget({
    super.key,
    required this.parameters,
    this.size = 220,
    this.archetypeKey,
    this.animate = true,
  });

  /// Symbol parameters. When these change, the painter is rebuilt.
  final KinrelSymbolParameters parameters;

  /// Square dimension of the painted symbol.
  final double size;

  /// Optional archetype key — currently only used as a visual hint to
  /// the painter (subtle outer-ring style).
  final ArchetypeType? archetypeKey;

  /// Set to false for a static (non-breathing) render. Used in tests
  /// and in the share card PNG export where we want a deterministic
  /// snapshot.
  final bool animate;

  @override
  State<KinrelSymbolWidget> createState() => _KinrelSymbolWidgetState();
}

class _KinrelSymbolWidgetState extends State<KinrelSymbolWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.parameters.pulseSpeedMs),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      // Static render — leave the controller at 0 so progress=0.
    }
  }

  @override
  void didUpdateWidget(covariant KinrelSymbolWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart the controller only if the pulse period changed — avoids
    // restarting the animation on every parent rebuild (Phase 19.2).
    if (oldWidget.parameters.pulseSpeedMs !=
        widget.parameters.pulseSpeedMs) {
      _controller.duration =
          Duration(milliseconds: widget.parameters.pulseSpeedMs);
    }
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
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
      builder: (context, _) {
        // progress = a triangle wave 0 → 1 → 0 → 1 ...
        // Use Curves.easeInOut for a softer breathing feel.
        final t = Curves.easeInOut.transform(_controller.value);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: KinrelSymbolPainter(
              parameters: widget.parameters,
              progress: t,
              archetypeKey: widget.archetypeKey,
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight static variant for use in places where animation would
/// be distracting (e.g. tiny cover thumbnails). Renders a single frame
/// at progress=0 with no ticker overhead.
class StaticKinrelSymbol extends StatelessWidget {
  const StaticKinrelSymbol({
    super.key,
    required this.parameters,
    this.size = 64,
    this.archetypeKey,
  });

  final KinrelSymbolParameters parameters;
  final double size;
  final ArchetypeType? archetypeKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: KinrelSymbolPainter(
          parameters: parameters,
          progress: 0,
          archetypeKey: archetypeKey,
        ),
      ),
    );
  }
}
