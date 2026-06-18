// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Production-Quality Pan/Zoom Container (v4.1)
//
// v4.1 changes (2026-06-18, fixing pinch-to-zoom + panning):
//   - REMOVED onDoubleTap from the parent GestureDetector. It was
//     conflicting with the child GraphNode's onDoubleTap (which
//     focuses the camera on the tapped node). When both parent and
//     child have DoubleTapGestureRecognizers, they compete in the
//     gesture arena and INTERFERE with the parent's
//     ScaleGestureRecognizer — causing pinch-to-zoom to fail.
//   - REMOVED the focalPointDelta addition in _onScaleUpdate that was
//     double-counting pan movement and causing the canvas to drift.
//     The correct math is just:
//       newTranslation = focalNow + (startTranslation - focalStart) * scaleRatio
//     This single formula handles pinch, pan, and combined gestures.
//   - Removed AnimationController, TickerProviderStateMixin, and all
//     animation-related code (only user was double-tap, now gone).
//
// v4 changes (earlier in 2026-06-18):
//   - Removed min/max scale clamping — graph can be freely moved
//   - Removed momentum fling (was causing "flyaway" graph)
//   - Simplified gesture handling: only onScaleStart/Update/End
//   - HitTestBehavior.translucent so child node taps pass through
//
// Architecture:
//   - Uses a TransformationController for the transform state
//   - Applies the transform via Positioned + Transform.scale

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

class _GraphPanZoomState extends State<GraphPanZoom> {
  // ── Gesture state ───────────────────────────────────────────────────
  double _gestureStartScale = 1.0;
  Offset _gestureStartTranslation = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  bool _isGesturing = false;

  // v4.1: Animation controller, double-tap tracking, and momentum fling
  // all removed. The only user was double-tap-to-zoom, which was removed
  // to fix the gesture arena conflict with node double-tap (focus camera).

  // ── Gesture Handlers ────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
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

    // ── v4.1 FIX: Correct focal-point-anchored zoom + pan math ──────
    //
    // The previous version had a bug: it added `details.focalPointDelta`
    // to the base translation, which double-counted the pan movement
    // and caused the canvas to drift/jump during pinch-zoom.
    //
    // The correct math is just:
    //   newTranslation = focalNow + (startTranslation - focalStart) * scaleRatio
    //
    // This single formula handles ALL three gesture types correctly:
    //   1. Pinch in place (fingers move toward/away from each other):
    //      focalNow ≈ focalStart, so the translation only changes due
    //      to scaleRatio — the focal point stays anchored under the
    //      fingers. ✅
    //   2. Two-finger pan (both fingers move in the same direction):
    //      focalNow moves with the fingers, scaleRatio ≈ 1, so the
    //      translation tracks the focal point. ✅
    //   3. Combined pinch + pan (real-world pinch gestures):
    //      Both terms contribute — the canvas zooms toward the focal
    //      point AND moves with it. ✅
    //
    // No need for a separate focalPointDelta term — it's already
    // encoded in the (focalNow - focalStart) difference.
    final focalNow = details.localFocalPoint;
    final scaleRatio =
        _gestureStartScale == 0 ? 1.0 : newScale / _gestureStartScale;

    final newTranslation = Offset(
      focalNow.dx +
          (_gestureStartTranslation.dx - _gestureStartFocalPoint.dx) *
              scaleRatio,
      focalNow.dy +
          (_gestureStartTranslation.dy - _gestureStartFocalPoint.dy) *
              scaleRatio,
    );

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

  // ── Double-Tap — REMOVED in v4.1 ───────────────────────────────────
  // The double-tap-to-zoom feature was removed because it conflicts
  // with the child GraphNode's onDoubleTap (which focuses the camera
  // on the tapped node). When both parent and child have
  // DoubleTapGestureRecognizers, they compete in the gesture arena
  // and interfere with the parent's ScaleGestureRecognizer, breaking
  // pinch-to-zoom.
  //
  // Users now zoom exclusively via pinch gestures. The "Center on Root"
  // button in the bottom toolbar can be used to reset the view.
  //
  // The _onDoubleTap and _onDoubleTapDown methods and the
  // _doubleTapPosition field are kept below (commented out) for
  // reference in case we want to re-add the feature with a different
  // approach (e.g., using a RawGestureDetector that only claims
  // double-taps on empty space).

  // void _onDoubleTapDown(TapDownDetails details) {
  //   _doubleTapPosition = details.localPosition;
  // }
  //
  // void _onDoubleTap() {
  //   if (_animController.isAnimating) return;
  //   final matrix = widget.transformationController.value;
  //   final currentScale = matrix.getMaxScaleOnAxis();
  //   final targetScale = currentScale < 1.5 ? 2.5 : 1.0;
  //   final focal = _doubleTapPosition ?? Offset.zero;
  //   final scaleRatio = targetScale / currentScale;
  //   final tx = matrix.getTranslation().x;
  //   final ty = matrix.getTranslation().y;
  //   final newTx = focal.dx + (tx - focal.dx) * scaleRatio;
  //   final newTy = focal.dy + (ty - focal.dy) * scaleRatio;
  //   final newMatrix = Matrix4.identity()
  //     ..translate(newTx, newTy)
  //     ..scale(targetScale);
  //   _animateTo(newMatrix, duration: const Duration(milliseconds: 250));
  //   widget.onDoubleTap?.call();
  // }

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
        //
        // v4.1 FIX: Removed onDoubleTap from this parent GestureDetector.
        // The child GraphNode widgets also have onDoubleTap (for focus-
        // camera-on-node). When both parent and child have
        // DoubleTapGestureRecognizers, they compete in the gesture arena
        // and INTERFERE with the parent's ScaleGestureRecognizer —
        // causing pinch-to-zoom to fail. The node's double-tap (focus)
        // is more important than the parent's double-tap (zoom toggle),
        // so we keep the node's and remove the parent's. Users zoom
        // via pinch gestures only.
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Scale gestures (pinch-to-zoom, two-finger pan, one-finger
              // pan on empty space) are always handled here.
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              // NO onDoubleTap here — it conflicts with node double-tap.
              // NO onLongPress here — child nodes handle their own long-press.
              // NO onTap here — child nodes handle their own taps.
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
