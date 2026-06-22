// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Pan/Zoom Container (v6.0 — Android-Proof)
//
// v6.0 (2026-06-22): COMPLETE REWRITE to fix pinch-zoom on Android APK.
//
// ROOT CAUSE of all previous failures (v4.1-v5.x):
//   The custom Listener + pointer-math approach computed span as
//   "average distance from focal point" which is HALF the actual finger
//   spread. While the math cancels out in theory, Android's pointer event
//   timing means the second finger's first PointerMove arrives before
//   _resetBaselineFromDown completes correctly, producing _baseSpan ≈ 0
//   which makes scaleFactor blow up or produce 1.0 forever (no zoom).
//
// FIX: Use Flutter's native ScaleGestureRecognizer via RawGestureDetector.
//   ScaleGestureRecognizer is implemented in the Flutter engine's C++ layer
//   with platform-specific pointer handling. It correctly:
//     - Wins the gesture arena on Android for 2-finger gestures
//     - Computes scale using the proper inter-finger distance formula
//     - Handles pointer ID assignment correctly on Android
//     - Fires even when child GestureDetectors exist (scale recognizer
//       doesn't compete with tap recognizers for 2-finger gestures)
//
// Single-finger tap/long-press: handled via onScaleStart/End tracking.
// Two-finger pinch/zoom: handled by ScaleGestureRecognizer.
// Single-finger pan: handled by ScaleGestureRecognizer (scale=1.0, panning).

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
  final bool enableMomentum;
  final void Function(Offset localPosition)? onTap;
  final void Function(Offset localPosition)? onLongPress;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom> {
  // Scale gesture state
  double _startScale = 1.0;
  Offset _startFocalPoint = Offset.zero;
  Offset _startTranslation = Offset.zero;

  // Tap detection
  Offset? _tapDownPosition;
  Offset? _pointerDownPosition; // v47: true pointer-down position captured by Listener
  bool _isPanning = false;
  Timer? _longPressTimer;
  static const double _tapMaxMovement = 18.0; // v47: was 10.0, too tight for Android finger tremble
  static const Duration _longPressDelay = Duration(milliseconds: 550); // v47: was 500ms, borderline with kLongPressTimeout

  void _onScaleStart(ScaleStartDetails details) {
    final matrix = widget.transformationController.value;
    _startScale = matrix.getMaxScaleOnAxis();
    _startTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    _startFocalPoint = details.localFocalPoint;

    if (details.pointerCount == 1) {
      // v47: Prefer the true pointer-down position captured by Listener;
      // ScaleGestureRecognizer.onStart fires AFTER the arena resolves, by
      // which point the finger has often moved several pixels.
      _tapDownPosition = _pointerDownPosition ?? details.localFocalPoint;
      _isPanning = false;

      _longPressTimer?.cancel();
      _longPressTimer = Timer(_longPressDelay, () {
        if (!_isPanning && _tapDownPosition != null) {
          widget.onLongPress?.call(_tapDownPosition!);
          _tapDownPosition = null;
        }
      });
    } else {
      _longPressTimer?.cancel();
      _tapDownPosition = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_tapDownPosition != null) {
      final moved = (details.localFocalPoint - _tapDownPosition!).distance;
      if (moved > _tapMaxMovement) {
        _longPressTimer?.cancel();
        _tapDownPosition = null;
        _isPanning = true;
      }
    } else {
      _isPanning = true;
    }

    if (details.pointerCount >= 2) {
      // ── PINCH-TO-ZOOM (2+ fingers) ─────────────────────────────
      final newScale = (_startScale * details.scale)
          .clamp(widget.minScale, widget.maxScale);
      final scaleRatio = newScale / _startScale;

      final newTx = _startFocalPoint.dx +
          (_startTranslation.dx - _startFocalPoint.dx) * scaleRatio +
          (details.localFocalPoint.dx - _startFocalPoint.dx);
      final newTy = _startFocalPoint.dy +
          (_startTranslation.dy - _startFocalPoint.dy) * scaleRatio +
          (details.localFocalPoint.dy - _startFocalPoint.dy);

      widget.transformationController.value = Matrix4.identity()
        ..translate(newTx, newTy)
        ..scale(newScale);
    } else {
      // ── SINGLE-FINGER PAN ──────────────────────────────────────
      final currentScale = widget.transformationController.value.getMaxScaleOnAxis();
      final delta = details.localFocalPoint - _startFocalPoint;
      final newTx = _startTranslation.dx + delta.dx;
      final newTy = _startTranslation.dy + delta.dy;

      widget.transformationController.value = Matrix4.identity()
        ..translate(newTx, newTy)
        ..scale(currentScale);
    }

    widget.onTransformChanged?.call();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _longPressTimer?.cancel();

    if (_tapDownPosition != null && !_isPanning) {
      widget.onTap?.call(_tapDownPosition!);
    }

    _tapDownPosition = null;
    _pointerDownPosition = null;
    _isPanning = false;
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
              // v47: Capture the true pointer-down position BEFORE the
              // gesture arena resolves. ScaleGestureRecognizer.onStart
              // fires after arena resolution, by which point the finger
              // has moved — causing inaccurate tap hit-testing.
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                _pointerDownPosition = event.localPosition;
              },
              onPointerCancel: (_) {
                _pointerDownPosition = null;
              },
              child: RawGestureDetector(
                gestures: {
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(),
                    (instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate
                        ..onEnd = _onScaleEnd;
                    },
                  ),
                },
                // v47: opaque — with translucent, Android routes the 2nd
                // pointer of a pinch to system UI, so ScaleGestureRecognizer
                // only sees 1 pointer and pinch never fires.
                behavior: HitTestBehavior.opaque,
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
          ),
        );
      },
    );
  }
}
