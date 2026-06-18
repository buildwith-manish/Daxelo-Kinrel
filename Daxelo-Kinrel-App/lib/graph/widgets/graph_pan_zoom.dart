// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Production-Quality Pan/Zoom Container (v4 — Simplified)
//
// v4 changes (responding to user feedback 2026-06-18):
//   - Removed min/max scale clamping — graph can be freely moved across
//     the entire canvas without restrictions (user request #4)
//   - Removed momentum fling (was causing jitter and "flyaway" graph)
//   - Simplified gesture handling: only onScaleStart/Update/End
//   - Double-tap to zoom retained (single-tap pass-through to child)
//   - Node taps work correctly because GestureDetector uses
//     HitTestBehavior.translucent — child node GestureDetectors win
//     the arena for taps, this widget wins for scale gestures.
//
// Architecture:
//   - Uses a TransformationController for the transform state
//   - Applies the transform via Positioned + Transform.scale
//   - AnimationController only for double-tap zoom animation

import 'package:flutter/material.dart';

/// A production-quality pan/zoom container.
///
/// Wraps [child] in a viewport-sized [GestureDetector] with
/// [HitTestBehavior.translucent], so:
///   - Pinch-to-zoom and pan work anywhere on the visible area
///   - Single taps pass through to child nodes (for selection)
///   - Two-finger gestures always win the arena over child taps
class GraphPanZoom extends StatefulWidget {
  const GraphPanZoom({
    super.key,
    required this.transformationController,
    required this.child,
    this.minScale = 0.05,
    this.maxScale = 8.0,
    this.onTransformChanged,
    this.onDoubleTap,
    this.enableMomentum = false,
  });

  /// The controller that holds the current 2D transform.
  final TransformationController transformationController;

  /// The content to be panned/zoomed.
  final Widget child;

  /// Minimum scale factor (default 0.05 = 5% — very lenient to allow
  /// the user to zoom way out and see the whole graph).
  final double minScale;

  /// Maximum scale factor (default 8.0 = 800% — generous zoom-in for
  /// reading details on small nodes).
  final double maxScale;

  /// Optional callback fired whenever the transform changes.
  final VoidCallback? onTransformChanged;

  /// Optional callback fired on double-tap. If null, double-tap
  /// toggles between scale=1.0 and scale=2.5 around the tap point.
  final VoidCallback? onDoubleTap;

  /// Kept for API compatibility — momentum is now disabled by default
  /// and the field is ignored. The fling behavior caused more issues
  /// than it solved (graph would drift after the user released).
  final bool enableMomentum;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom>
    with TickerProviderStateMixin {
  // ── Animation (for double-tap only) ────────────────────────────────
  late final AnimationController _animController;
  Animation<Matrix4>? _animAnimation;

  // ── Gesture state ───────────────────────────────────────────────────
  double _gestureStartScale = 1.0;
  Offset _gestureStartTranslation = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  bool _isGesturing = false;

  // ── Double-tap tracking ─────────────────────────────────────────────
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onAnimTick);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onAnimTick() {
    if (_animAnimation == null) return;
    widget.transformationController.value = _animAnimation!.value;
  }

  void _cancelAnimation() {
    if (_animController.isAnimating) {
      _animController.stop();
    }
  }

  /// Animate to a target matrix with an ease-out curve.
  void _animateTo(Matrix4 target, {Duration? duration}) {
    _cancelAnimation();
    final start = widget.transformationController.value;
    _animAnimation = Matrix4Tween(
      begin: start,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.duration = duration ?? const Duration(milliseconds: 250);
    _animController
      ..reset()
      ..forward().then((_) {
        widget.onTransformChanged?.call();
      });
  }

  // ── Gesture Handlers ────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _cancelAnimation();
    _isGesturing = true;
    final matrix = widget.transformationController.value;
    _gestureStartScale = matrix.getMaxScaleOnAxis();
    _gestureStartTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    // CRITICAL: use localFocalPoint (GestureDetector-local coords),
    // NOT details.focalPoint (screen-global). The translation in the
    // matrix is in local coords; mixing coordinate spaces causes the
    // canvas to jump off-screen by the widget's screen offset.
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_isGesturing) return;

    // Compute new scale (clamped to min/max, but with very lenient bounds).
    final newScale = (_gestureStartScale * details.scale)
        .clamp(widget.minScale, widget.maxScale);

    // Compute the focal-point-anchored translation.
    //
    // The math: we want the canvas point that was under the initial
    // focal point to remain under the (moving) focal point as the
    // user pinches. This is the standard "pinch-to-zoom" anchor math.
    //
    //   newTranslation = focalNow +
    //                    (startTranslation - focalStart) * (newScale / startScale)
    //
    // We also add the pan offset (details.focalPointDelta) so that
    // two-finger panning works in addition to pinch-zoom.
    final focalNow = details.localFocalPoint;
    final scaleRatio =
        _gestureStartScale == 0 ? 1.0 : newScale / _gestureStartScale;

    final baseTranslation = Offset(
      focalNow.dx +
          (_gestureStartTranslation.dx - _gestureStartFocalPoint.dx) *
              scaleRatio,
      focalNow.dy +
          (_gestureStartTranslation.dy - _gestureStartFocalPoint.dy) *
              scaleRatio,
    );

    // Additionally apply the pan delta (so the canvas moves with the
    // fingers during a two-finger drag, not just zooms in place).
    // details.focalPointDelta is the change in the focal point since
    // the last update — adding it to the base translation gives us
    // pan + zoom combined.
    final newTranslation = baseTranslation + details.focalPointDelta;

    final newMatrix = Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);

    widget.transformationController.value = newMatrix;
    widget.onTransformChanged?.call();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isGesturing = false;
    widget.onTransformChanged?.call();

    // v4: No momentum fling. The previous implementation used a
    // FrictionSimulation with a very low drag coefficient (0.005)
    // which caused the graph to "fly away" after the user released
    // a pan gesture. Removed for stability.
  }

  // ── Double-Tap ──────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    if (_animController.isAnimating) return;

    final matrix = widget.transformationController.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    // Toggle between reset (1.0) and zoom-in (2.5x).
    final targetScale = currentScale < 1.5 ? 2.5 : 1.0;

    final focal = _doubleTapPosition ?? Offset.zero;
    final scaleRatio = targetScale / currentScale;
    final tx = matrix.getTranslation().x;
    final ty = matrix.getTranslation().y;
    // Keep the focal point anchored: zoom toward where the user tapped.
    final newTx = focal.dx + (tx - focal.dx) * scaleRatio;
    final newTy = focal.dy + (ty - focal.dy) * scaleRatio;
    final newMatrix = Matrix4.identity()
      ..translate(newTx, newTy)
      ..scale(targetScale);

    _animateTo(newMatrix, duration: const Duration(milliseconds: 250));
    widget.onDoubleTap?.call();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Force the gesture detector to be exactly viewport-sized.
        // This ensures the ScaleGestureRecognizer's hit-test region
        // covers the entire visible area, not just the child canvas.
        //
        // HitTestBehavior.translucent (NOT opaque) is critical here:
        //   - opaque: would block all taps from reaching child nodes,
        //             making node selection impossible.
        //   - translucent: lets the gesture detector receive the
        //             pointer events AND lets child widgets (like the
        //             node's GestureDetector) receive them too. The
        //             gesture arena then decides who wins based on the
        //             gesture type: taps → child node, scale → this widget.
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Scale gestures (pinch-to-zoom, two-finger pan) are
              // always handled here. Single taps pass through to nodes.
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onDoubleTapDown: _onDoubleTapDown,
              onDoubleTap: _onDoubleTap,
              // Long-press is also passed through to child nodes by
              // NOT defining onLongPress here. This lets nodes show
              // context menus if they want.
              child: AnimatedBuilder(
                animation: widget.transformationController,
                builder: (context, _) {
                  final matrix = widget.transformationController.value;
                  final scale = matrix.getMaxScaleOnAxis();
                  final tx = matrix.getTranslation().x;
                  final ty = matrix.getTranslation().y;
                  // Apply the transform via Positioned + Transform.scale.
                  // This is unambiguous: translation is via Positioned
                  // (origin = top-left of viewport), scale is via
                  // Transform.scale (origin = top-left of canvas).
                  // A canvas point (cx, cy) ends up at screen position
                  // (tx + cx*scale, ty + cy*scale). Correct.
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: tx,
                        top: ty,
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topLeft,
                          child: widget.child,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
