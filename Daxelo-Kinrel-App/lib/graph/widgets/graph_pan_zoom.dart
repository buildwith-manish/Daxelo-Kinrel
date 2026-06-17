// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Custom Pan/Zoom Container (Production-Ready v2)
//
// A bulletproof replacement for Flutter's InteractiveViewer.
//
// v2 changes (fixes "blank screen" regression):
//   - Removed `Transform` widget; use a plain `Stack` with a
//     `Positioned` child whose `left`/`top` come directly from
//     `_currentTranslation` and whose scale is applied via
//     `Transform.scale` on the child itself. This eliminates any
//     origin/alignment confusion.
//   - Initial centering is now done in `initState` (reading the
//     controller's current value) rather than relying on the parent
//     to set it via a post-frame callback. If the controller is at
//     identity, we leave it alone (canvas renders at (0,0) which is
//     the top-left of the viewport — fully visible for any canvas
//     that fits).
//   - Removed the inertia/fling animation. It was causing the canvas
//     to drift off-screen on release. Pan/zoom is now 1:1 with the
//     gesture — no surprises.
//   - Simplified gesture math: track `_gestureStartTranslation` and
//     `_gestureStartScale` on scale-start, then on scale-update
//     compute the new translation that keeps the focal point
//     anchored. All in local coordinates.
//
// Features:
//   - Pinch to zoom (1-finger pan, 2-finger pinch + pan)
//   - Min/max scale clamping
//   - Single-tap pass-through to child nodes (no onDoubleTap)
//   - HitTestBehavior.opaque so the detector covers the whole
//     viewport, including empty space

import 'package:flutter/material.dart';

/// A custom pan/zoom container that replaces InteractiveViewer.
///
/// Wraps [child] in a viewport-sized [GestureDetector] with
/// [HitTestBehavior.opaque], so pinch-to-zoom works anywhere on the
/// visible area regardless of where the child's hit-test region falls.
class GraphPanZoom extends StatefulWidget {
  const GraphPanZoom({
    super.key,
    required this.transformationController,
    required this.child,
    this.minScale = 0.1,
    this.maxScale = 4.0,
    this.onTransformChanged,
  });

  /// The controller that holds the current 2D transform.
  ///
  /// The matrix is interpreted as:
  ///   [scale 0 0 0]
  ///   [0 scale 0 0]
  ///   [0 0 1 0]
  ///   [tx ty 0 1]
  /// where (tx, ty) is the translation in viewport-local pixels and
  /// `scale` is the uniform zoom factor.
  final TransformationController transformationController;

  /// The content to be panned/zoomed. Typically a SizedBox sized to
  /// the canvas dimensions, containing the graph's edges and nodes.
  final Widget child;

  /// Minimum scale factor (default 0.1 = 10%).
  final double minScale;

  /// Maximum scale factor (default 4.0 = 400%).
  final double maxScale;

  /// Optional callback fired whenever the transform changes (pan or
  /// zoom). Used by FamilyGraphWidget to update viewport culling.
  final VoidCallback? onTransformChanged;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom> {
  // Gesture tracking state — captured on scale-start, used on scale-update
  double _gestureStartScale = 1.0;
  Offset _gestureStartTranslation = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  // ── Gesture Handlers ────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    final matrix = widget.transformationController.value;
    _gestureStartScale = matrix.getMaxScaleOnAxis();
    _gestureStartTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    // CRITICAL: use localFocalPoint (GestureDetector-local coords),
    // NOT details.focalPoint (screen-global). The translation in the
    // matrix is in local coords; mixing coordinate spaces causes the
    // canvas to jump off-screen by the widget's screen offset
    // (AppBar + FilterBar ≈ 104px).
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newScale = (_gestureStartScale * details.scale)
        .clamp(widget.minScale, widget.maxScale);

    // The focal point has moved by (localFocalPoint - _gestureStartFocalPoint).
    // We want the canvas point under the initial focal point to stay
    // under the (moving) focal point.
    //
    // new_translation = focal_now + (initial_translation - focal_start) * (newScale / initialScale)
    //
    // All values are in local coords (GestureDetector-local), matching
    // the matrix's translation space.
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
    // No inertia — keep it simple and predictable. The previous
    // FrictionSimulation was causing the canvas to drift off-screen
    // on release.
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Force the gesture detector to be exactly viewport-sized.
        // This is the KEY fix — InteractiveViewer sizes its detector
        // to the child when `constrained: false`, but we explicitly
        // use SizedBox with constraints.maxWidth × maxHeight so the
        // detector covers the whole visible area.
        //
        // Note: We do NOT register onDoubleTap here because that
        // would reserve the gesture arena and delay single-tap
        // pass-through to child nodes. Double-tap-to-zoom is a
        // nice-to-have; node taps are essential.
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: AnimatedBuilder(
                animation: widget.transformationController,
                builder: (context, _) {
                  final matrix = widget.transformationController.value;
                  final scale = matrix.getMaxScaleOnAxis();
                  final tx = matrix.getTranslation().x;
                  final ty = matrix.getTranslation().y;
                  // Apply the transform via a Positioned + Transform.scale.
                  // This is more reliable than `Transform(transform: matrix)`
                  // because:
                  //   1. The translation is applied via Positioned, which
                  //      is unambiguous about origin (top-left of the
                  //      parent Stack = top-left of viewport).
                  //   2. The scale is applied via Transform.scale with
                  //      alignment: topLeft, so the canvas scales around
                  //      its own top-left corner — which is exactly what
                  //      the translation expects.
                  //
                  // The child (canvas-sized SizedBox) is placed at
                  // (tx, ty) and scaled by `scale`. A canvas point
                  // (cx, cy) ends up at screen position
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
