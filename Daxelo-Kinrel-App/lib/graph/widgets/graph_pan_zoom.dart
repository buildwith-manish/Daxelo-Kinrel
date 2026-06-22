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

import 'dart:async';
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
    this.onTap,
    this.onLongPress,
  });

  final TransformationController transformationController;
  final Widget child;
  final double minScale;
  final double maxScale;
  final VoidCallback? onTransformChanged;
  final VoidCallback? onDoubleTap;

  /// Kept for API compatibility — unused.
  final bool enableMomentum;

  /// Called when the user taps (single finger, no significant movement).
  final void Function(Offset localPosition)? onTap;

  /// Called when the user long-presses (single finger, held 500ms).
  final void Function(Offset localPosition)? onLongPress;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom> {
  // pointer id -> current LOCAL position (updated on every move)
  final Map<int, Offset> _pointers = {};

  // v44 FIX: pointer id -> position at the moment each finger went DOWN.
  // When a second finger lands, _resetBaseline() must use the DOWN positions
  // (not the moved positions) for both fingers — otherwise _baseFocalPoint
  // and _baseSpan are wrong, causing a scale jump or freeze on the first
  // pinch frame on Android.
  final Map<int, Offset> _downPositions = {};

  // Baseline, recalculated whenever the active-pointer COUNT changes.
  double _baseScale = 1.0;
  Offset _baseTranslation = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  double _baseSpan = 1.0;

  // Tap-vs-pan disambiguation for the single-finger case.
  Offset? _singleDownPosition;
  bool _singlePanActive = false;

  // v45: Tap/long-press detection via Timer (no GestureDetector needed).
  int? _tapPointerId;
  Timer? _longPressTimer;
  static const Duration _longPressDelay = Duration(milliseconds: 500);
  // v46 FIX: Use 12.0 instead of kPanSlop (18.0).
  // On real Android screens, finger tremble during a tap often exceeds
  // 18px, causing every tap to be treated as a pan (and thus cancelled).
  // 12.0 is tight enough to not cause accidental pans but loose enough
  // to tolerate normal finger tremble.
  static const double _panSlop = 12.0;

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

  /// Compute focal point from a specific map (either _pointers or _downPositions).
  Offset _focalPointFrom(Map<int, Offset> map) {
    if (map.isEmpty) return Offset.zero;
    double dx = 0, dy = 0;
    for (final p in map.values) {
      dx += p.dx;
      dy += p.dy;
    }
    return Offset(dx / map.length, dy / map.length);
  }

  /// Compute average span from a specific map.
  double _averageSpanFrom(Map<int, Offset> map, Offset focal) {
    if (map.isEmpty) return 1.0;
    double total = 0;
    for (final p in map.values) {
      total += (p - focal).distance;
    }
    final avg = total / map.length;
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

  /// v44 FIX: Reset baseline using DOWN positions instead of current
  /// (moved) positions. This prevents the scale jump when a second
  /// finger lands — the first finger has already moved by the time
  /// the second finger goes down, so using its current position would
  /// give a wrong focal/span baseline.
  void _resetBaselineFromDown() {
    final matrix = widget.transformationController.value;
    _baseScale = matrix.getMaxScaleOnAxis();
    _baseTranslation =
        Offset(matrix.getTranslation().x, matrix.getTranslation().y);
    _baseFocalPoint = _focalPointFrom(_downPositions);
    _baseSpan = _averageSpanFrom(_downPositions, _baseFocalPoint);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _downPositions[event.pointer] = event.localPosition;

    if (_pointers.length == 1) {
      _singleDownPosition = event.localPosition;
      _singlePanActive = false;
      _resetBaseline();
      // v45: Start tap/long-press detection
      _startTapDetection(event.pointer, event.localPosition);
    } else {
      // Second finger → cancel tap/long-press, switch to pinch
      _cancelTapDetection();
      _resetBaselineFromDown();
    }
  }

  void _startTapDetection(int pointerId, Offset position) {
    _tapPointerId = pointerId;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      if (_tapPointerId == pointerId && !_singlePanActive && _pointers.length == 1) {
        widget.onLongPress?.call(position);
        _tapPointerId = null; // Consume — don't also fire tap on release
      }
    });
  }

  void _cancelTapDetection() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _tapPointerId = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length == 1) {
      if (!_singlePanActive) {
        final moved =
            (event.localPosition - (_singleDownPosition ?? event.localPosition))
                .distance;
        if (moved < _panSlop) return;
        _singlePanActive = true;
        // v45: Cancel tap/long-press when pan starts
        _cancelTapDetection();
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

  void _endPointer(int pointer, [Offset? upPosition]) {
    // v46 FIX: Capture the DOWN position BEFORE removing from map,
    // so we pass the stable tap position (not the possibly-jittered UP pos).
    final downPos = _downPositions[pointer];

    _pointers.remove(pointer);
    _downPositions.remove(pointer);

    if (_pointers.isEmpty && _tapPointerId == pointer && !_singlePanActive) {
      _cancelTapDetection();
      // v46 FIX: Use downPos (stable) instead of upPosition (may have micro-jitter)
      final tapPos = downPos ?? upPosition;
      if (tapPos != null) {
        widget.onTap?.call(tapPos);
      }
    } else {
      _cancelTapDetection();
    }

    if (_pointers.isEmpty) {
      _singleDownPosition = null;
      _singlePanActive = false;
    } else if (_pointers.length == 1) {
      // Going from 2→1 finger: the remaining finger becomes a fresh
      // pan anchor. Reset _singleDownPosition so the slop check starts
      // from the current position (no accidental pan jump).
      final remaining = _pointers.values.first;
      _singleDownPosition = remaining;
      _singlePanActive = false;
    }
    _resetBaseline();
    widget.onTransformChanged?.call();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
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
              // v46 FIX: opaque instead of translucent so the Listener
              // claims ALL pointer events immediately on Android,
              // preventing other widgets from stealing events mid-gesture.
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: (e) => _endPointer(e.pointer, e.localPosition),
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
