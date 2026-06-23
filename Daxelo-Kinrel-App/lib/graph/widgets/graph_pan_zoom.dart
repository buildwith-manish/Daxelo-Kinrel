// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Pan/Zoom Container (v8.0 — Definitive Android fix)
//
// ══════════════════════════════════════════════════════════════════════
// v8.0 (2026-06-23): ROOT CAUSE FOUND AND FIXED.
//
// WHY v7.0 STILL BROKE ON ANDROID:
//
//   Problem 1 — Listener(opaque) blocked ScaleGestureRecognizer:
//     In v7.0 the outer Listener had behavior: HitTestBehavior.opaque.
//     On Android, opaque means the Listener CONSUMES the pointer event
//     from the hit-test perspective. The inner RawGestureDetector's
//     ScaleGestureRecognizer never saw the raw PointerDownEvent, so it
//     could never enter the gesture arena → pinch-zoom dead on Android.
//     FIX: Listener must use HitTestBehavior.deferToChild (the default).
//     The RawGestureDetector below it keeps opaque so it owns the arena.
//
//   Problem 2 — Single-finger pan used wrong scale:
//     In _onScaleUpdate with 1 finger, the code read currentScale from
//     the CURRENT (live) matrix each frame. After any previous pinch this
//     was correct, but during a pan that followed a zoom the matrix scale
//     was already set, so re-reading it mid-pan caused scale drift.
//     FIX: Always use _startScale (captured in _onScaleStart) for both
//     1-finger pan and 2-finger pinch branches.
//
//   Problem 3 — Tap detection position was wrong after pan/zoom:
//     _tapStartPosition stored the raw Listener local position, which is
//     in the GraphPanZoom widget's coordinate space. But onTap consumers
//     (GraphCanvasWidget, FamilyGraphWidget) need this exact position to
//     do their hit-test math:
//       canvas_pos = (localPosition - Offset(tx,ty)) / scale
//     This is correct — no change needed — but documented here for clarity.
//
// ARCHITECTURE (unchanged from v7.0, bugs fixed):
//   • Listener (deferToChild) → raw pointer → tap + long-press detection.
//     Fires before gesture arena but does NOT consume hit-test.
//   • RawGestureDetector (opaque, ScaleGestureRecognizer) → pan + pinch.
//     Owns the gesture arena. ScaleGestureRecognizer works on Android.
//   • AnimatedBuilder on TransformationController → repaints canvas.
// ══════════════════════════════════════════════════════════════════════

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

  /// Called with the tap position in GraphPanZoom widget-local coordinates.
  /// Consumers convert to canvas coordinates via:
  ///   canvasPos = (localPosition - Offset(tx, ty)) / scale
  final void Function(Offset localPosition)? onTap;

  /// Called with the long-press position in GraphPanZoom widget-local coordinates.
  final void Function(Offset localPosition)? onLongPress;

  @override
  State<GraphPanZoom> createState() => _GraphPanZoomState();
}

class _GraphPanZoomState extends State<GraphPanZoom> {
  // ── Pan/zoom state ─────────────────────────────────────────────────
  double _startScale = 1.0;
  Offset _startFocalPoint = Offset.zero;
  Offset _startTranslation = Offset.zero;

  // ── Tap/long-press state ───────────────────────────────────────────
  // Tracked via Listener (raw pointer events, before gesture arena).
  final Map<int, Offset> _activePointers = {};
  Offset? _tapStartPosition;
  DateTime? _tapStartTime;
  bool _tapCancelled = false;
  Timer? _longPressTimer;

  static const double _tapMaxMovementPx = 12.0;
  static const int _tapMaxMs = 300;
  static const Duration _longPressDelay = Duration(milliseconds: 500);

  // ── Listener: raw pointer callbacks ───────────────────────────────

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      _tapStartPosition = event.localPosition;
      _tapStartTime = DateTime.now();
      _tapCancelled = false;

      _longPressTimer?.cancel();
      final capturedPos = event.localPosition;
      _longPressTimer = Timer(_longPressDelay, () {
        if (!_tapCancelled && _tapStartPosition != null) {
          widget.onLongPress?.call(capturedPos);
          _tapCancelled = true;
          _tapStartPosition = null;
        }
      });
    } else {
      // Multi-touch → cancel tap/long-press
      _longPressTimer?.cancel();
      _tapCancelled = true;
      _tapStartPosition = null;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (!_tapCancelled &&
        _tapStartPosition != null &&
        _activePointers.length == 1) {
      final moved = (event.localPosition - _tapStartPosition!).distance;
      if (moved > _tapMaxMovementPx) {
        _longPressTimer?.cancel();
        _tapCancelled = true;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_tapCancelled &&
        _tapStartPosition != null &&
        _activePointers.length == 1 &&
        _tapStartTime != null) {
      final elapsed =
          DateTime.now().difference(_tapStartTime!).inMilliseconds;
      if (elapsed < _tapMaxMs) {
        widget.onTap?.call(_tapStartPosition!);
      }
    }

    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty) {
      _longPressTimer?.cancel();
      _tapStartPosition = null;
      _tapStartTime = null;
      _tapCancelled = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _longPressTimer?.cancel();
    _tapStartPosition = null;
    _tapStartTime = null;
    _tapCancelled = false;
  }

  // ── ScaleGestureRecognizer: pan + pinch-zoom ───────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    final matrix = widget.transformationController.value;
    // v8 FIX: capture scale at gesture START and use it throughout
    // the entire gesture — never re-read mid-gesture to avoid drift.
    _startScale = matrix.getMaxScaleOnAxis();
    _startTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    _startFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      // ── PINCH-TO-ZOOM (2+ fingers) ──────────────────────────────
      final newScale =
          (_startScale * details.scale).clamp(widget.minScale, widget.maxScale);
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
      // ── SINGLE-FINGER PAN ────────────────────────────────────────
      // v8 FIX: use _startScale captured at gesture start,
      // NOT re-read from the live matrix (which caused scale drift).
      final delta = details.localFocalPoint - _startFocalPoint;
      final newTx = _startTranslation.dx + delta.dx;
      final newTy = _startTranslation.dy + delta.dy;

      widget.transformationController.value = Matrix4.identity()
        ..translate(newTx, newTy)
        ..scale(_startScale);
    }

    widget.onTransformChanged?.call();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Tap/long-press fully handled by Listener above.
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
              // v8 FIX: Use deferToChild (NOT opaque) so the Listener
              // does NOT consume the hit-test. If Listener is opaque, it
              // swallows the PointerDownEvent from the gesture arena's
              // perspective and the inner ScaleGestureRecognizer never
              // sees it → pinch-zoom permanently broken on Android.
              //
              // deferToChild means: hit-test passes through to the
              // RawGestureDetector child, which IS opaque and correctly
              // owns the gesture arena. The Listener still fires its raw
              // pointer callbacks for tap detection — it just doesn't
              // block the arena.
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: RawGestureDetector(
                // opaque: ensures ScaleGestureRecognizer owns the arena
                // and receives ALL pointer events including the 2nd finger
                // of a pinch on Android.
                behavior: HitTestBehavior.opaque,
                gestures: {
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(),
                    (instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate
                        ..onEnd = _onScaleEnd;
                    },
                  ),
                },
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
