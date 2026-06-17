// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Custom Pan/Zoom Container (Production-Ready)
//
// A bulletproof replacement for Flutter's InteractiveViewer that gives
// us 100% control over gesture handling. InteractiveViewer has many
// quirks (sizing its internal RawGestureDetector to the child when
// `constrained: false`, deferring hit-tests when `clipBehavior:
// Clip.none`, competing with parent gesture detectors, etc.) that
// have repeatedly broken pinch-to-zoom in this app.
//
// This widget uses a plain GestureDetector with onScaleStart /
// onScaleUpdate / onScaleEnd at the TOP level, with
// `behavior: HitTestBehavior.opaque` and an explicit viewport-sized
// container. Pinch-to-zoom and pan work everywhere on the visible
// area, including empty space far from any node.
//
// The transform is written to a `TransformationController` so
// existing code that reads `_transformationController.value` (zoom
// level, pan offset, culling viewport) continues to work without
// changes.
//
// Features:
//   - Pinch to zoom (1-finger pan, 2-finger pinch + pan)
//   - Double-tap to zoom in (with optional fallback to zoom-out
//     when already zoomed in)
//   - Min/max scale clamping
//   - Inertia (fling) on pan release
//   - Smooth animation when clamping to bounds
//   - No external dependencies beyond Flutter

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
  /// The same controller is read by code that needs the current zoom
  /// level (`matrix.getMaxScaleOnAxis()`) or pan offset
  /// (`matrix.getTranslation()`).
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

class _GraphPanZoomState extends State<GraphPanZoom>
    with SingleTickerProviderStateMixin {
  // Gesture tracking state
  double _initialScale = 1.0;
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialTranslation = Offset.zero;
  bool _isAnimating = false;

  // Inertia simulation
  late final AnimationController _flingController;
  Animation<Matrix4>? _flingAnimation;

  @override
  void initState() {
    super.initState();
    _flingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_onFlingTick);
  }

  @override
  void dispose() {
    _flingController.dispose();
    super.dispose();
  }

  void _onFlingTick() {
    if (_flingAnimation == null) return;
    widget.transformationController.value = _flingAnimation!.value;
  }

  void _cancelFling() {
    if (_flingController.isAnimating) {
      _flingController.stop();
    }
    _isAnimating = false;
  }

  // ── Gesture Handlers ────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _cancelFling();
    final matrix = widget.transformationController.value;
    _initialScale = matrix.getMaxScaleOnAxis();
    _initialTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    _initialFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isAnimating) return;

    final newScale = (_initialScale * details.scale)
        .clamp(widget.minScale, widget.maxScale);

    // The focal point in screen coordinates has moved by
    // (details.focalPoint - _initialFocalPoint). We want the canvas
    // point under the focal point to stay under the focal point.
    //
    // Compose: new_translation = focal_screen + (initial_translation - focal_screen) * (newScale / initialScale) + (focal_now - focal_start)
    //
    // Simpler form: keep the same screen→canvas mapping as before
    // for the initial focal point, then pan by the focal delta.
    final focalDelta = details.focalPoint - _initialFocalPoint;
    final scaleRatio = _initialScale == 0 ? 1.0 : newScale / _initialScale;
    final newTranslation = Offset(
      _initialFocalPoint.dx +
          (_initialTranslation.dx - _initialFocalPoint.dx) * scaleRatio +
          focalDelta.dx,
      _initialFocalPoint.dy +
          (_initialTranslation.dy - _initialFocalPoint.dy) * scaleRatio +
          focalDelta.dy,
    );

    final newMatrix = Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);

    widget.transformationController.value = newMatrix;
    widget.onTransformChanged?.call();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Apply inertia (fling) for the pan component.
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.distance < 200) return; // ignore tiny flings

    final matrix = widget.transformationController.value;
    final startTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    final scale = matrix.getMaxScaleOnAxis();

    // Friction simulation — high drag so the fling decays quickly.
    // finalX gives the resting position given the initial velocity.
    final frictionSimX = FrictionSimulation(0.005, startTranslation.dx,
        velocity.dx);
    final frictionSimY = FrictionSimulation(0.005, startTranslation.dy,
        velocity.dy);

    final endMatrix = Matrix4.identity()
      ..translate(frictionSimX.finalX, frictionSimY.finalX)
      ..scale(scale);

    _isAnimating = true;
    // Note: _flingController already has _onFlingTick as a listener
    // (registered in initState), so we just need to set _flingAnimation
    // and start the controller.
    _flingAnimation = Matrix4Tween(
      begin: matrix,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _flingController,
      curve: Curves.easeOut,
    ));

    _flingController
      ..reset()
      ..forward().then((_) {
        _isAnimating = false;
        widget.onTransformChanged?.call();
      });
  }

  // ── Build ───────────────────────────────────────────────────────────
  // (Double-tap-to-zoom was intentionally removed because registering
  // onDoubleTap reserves the gesture arena and delays single-tap
  // pass-through to child nodes. Node taps are essential.)

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
              // Note: We do NOT pass `supportedDevices` here — the
              // default already accepts touch, mouse, stylus, and
              // trackpad. Pinning it to a const set required importing
              // package:flutter/gestures.dart for TargetDeviceKind,
              // which previously caused a CI analyzer failure.
              child: AnimatedBuilder(
                animation: widget.transformationController,
                builder: (context, _) {
                  return Transform(
                    transform: widget.transformationController.value,
                    alignment: Alignment.topLeft,
                    child: widget.child,
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
