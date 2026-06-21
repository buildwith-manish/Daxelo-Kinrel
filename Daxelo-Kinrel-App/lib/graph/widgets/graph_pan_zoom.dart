// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Production-Quality Pan/Zoom Container (v5.0)
//
// v5.0 changes (2026-06-21, fixing pinch-still-stuck-on-Android):
//   - REPLACED GestureDetector.onScale* with raw Listener pointer
//     tracking. The previous approach required the parent's
//     ScaleGestureRecognizer to WIN the gesture arena against every
//     node's Tap/LongPress recognizer. On real Android touchscreens
//     this resolution can stall long enough that pinch reads as
//     completely frozen — invisible on Flutter Web because browser
//     pointer-event delivery doesn't route through the same arena.
//   - Listener.onPointerDown/Move/Up fire unconditionally regardless
//     of arena outcome, so node taps can never block or delay pinch
//     again. Pan/zoom math is unchanged (same focal-anchored formula
//     as v4.1) — only the EVENT SOURCE changed.
//   - Single-finger movement under kPanSlop is ignored so ordinary
//     taps on nodes don't cause a tiny accidental pan/jitter.
//   - Multi-finger baseline (scale/translation/focal/span) is
//     recalculated every time a finger is added or removed, so
//     transitions between 1-finger-pan and 2-finger-pinch never jump.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A production-quality pan/zoom container.
///
/// Tracks raw pointers via [Listener] instead of GestureDetector's
/// scale recognizer, so it never has to win a gesture-arena race
/// against child node taps/long-presses.
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

  final TransformationController transformationController;
  final Widget child;
  final double minScale;
  final double maxScale;
  final VoidCallback? onTransformChanged;
  final VoidCallback? onDoubleTap;

  /// Kept for API compatibility — unused.
  final bool enableMomentum;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom> {
  // pointer id -> current LOCAL position
  final Map<int, Offset> _pointers = {};

  // Baseline, recalculated whenever the active-pointer COUNT changes.
  double _baseScale = 1.0;
  Offset _baseTranslation = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  double _baseSpan = 1.0;

  // Tap-vs-pan disambiguation for the single-finger case.
  Offset? _singleDownPosition;
  bool _singlePanActive = false;

  Offset _currentFocalPoint() {
    if (_pointers.isEmpty) return Offset.zero;
    double dx = 0, dy = 0;
    for (final p in _pointers.values) {
      dx += p.dx;
      dy += p.dy;
    }
    return Offset(dx / _pointers.length, dy / _pointers.length);
  }

  double _currentAverageSpan(Offset focal) {
    if (_pointers.isEmpty) return 1.0;
    double total = 0;
    for (final p in _pointers.values) {
      total += (p - focal).distance;
    }
    final avg = total / _pointers.length;
    return avg < 1.0 ? 1.0 : avg;
  }

  void _resetBaseline() {
    final matrix = widget.transformationController.value;
    _baseScale = matrix.getMaxScaleOnAxis();
    _baseTranslation =
        Offset(matrix.getTranslation().x, matrix.getTranslation().y);
    _baseFocalPoint = _currentFocalPoint();
    _baseSpan = _currentAverageSpan(_baseFocalPoint);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _singleDownPosition = event.localPosition;
      _singlePanActive = false;
    }
    _resetBaseline();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length == 1) {
      // Single finger — ignore tiny movement so taps on nodes stay
      // taps (don't nudge the canvas during a deliberate tap).
      if (!_singlePanActive) {
        final moved =
            (event.localPosition - (_singleDownPosition ?? event.localPosition))
                .distance;
        if (moved < kPanSlop) return;
        _singlePanActive = true;
      }
      final matrix = widget.transformationController.value;
      final scale = matrix.getMaxScaleOnAxis();
      final tx = matrix.getTranslation().x + event.delta.dx;
      final ty = matrix.getTranslation().y + event.delta.dy;
      widget.transformationController.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(scale);
      widget.onTransformChanged?.call();
      return;
    }

    // Two or more fingers — pinch-to-zoom anchored at the shared
    // focal point. Same math as the previous v4.1 GestureDetector
    // version; only the event source changed.
    final focal = _currentFocalPoint();
    final span = _currentAverageSpan(focal);
    final scaleFactor = _baseSpan <= 0 ? 1.0 : span / _baseSpan;

    final newScale =
        (_baseScale * scaleFactor).clamp(widget.minScale, widget.maxScale);
    final scaleRatio = _baseScale == 0 ? 1.0 : newScale / _baseScale;

    final newTranslation = Offset(
      focal.dx + (_baseTranslation.dx - _baseFocalPoint.dx) * scaleRatio,
      focal.dy + (_baseTranslation.dy - _baseFocalPoint.dy) * scaleRatio,
    );

    widget.transformationController.value = Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);
    widget.onTransformChanged?.call();
  }

  void _endPointer(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) {
      _singleDownPosition = null;
      _singlePanActive = false;
    }
    _resetBaseline();
    widget.onTransformChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: ClipRect(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: (e) => _endPointer(e.pointer),
              onPointerCancel: (e) => _endPointer(e.pointer),
              child: AnimatedBuilder(
                animation: widget.transformationController,
                builder: (context, _) {
                  final matrix = widget.transformationController.value;
                  final scale = matrix.getMaxScaleOnAxis();
                  final tx = matrix.getTranslation().x;
                  final ty = matrix.getTranslation().y;
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
