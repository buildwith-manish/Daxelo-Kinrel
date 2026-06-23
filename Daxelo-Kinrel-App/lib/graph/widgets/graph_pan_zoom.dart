// lib/graph/widgets/graph_pan_zoom.dart
//
// DAXELO KINREL — Pan/Zoom Container (v9.0 — Final definitive Android fix)
//
// ══════════════════════════════════════════════════════════════════════
// WHAT WAS ACTUALLY BROKEN (found by reading the real source):
//
//   In v7.0 the Listener had behavior: HitTestBehavior.opaque AND the
//   RawGestureDetector also had behavior: HitTestBehavior.opaque.
//
//   On Android, TWO nested opaque hit-test regions cause the OUTER one
//   (Listener) to win the arena dispatch. The inner RawGestureDetector
//   never receives the second PointerDownEvent (the second finger of a
//   pinch), so ScaleGestureRecognizer can never accumulate 2 pointers
//   → pinch-zoom permanently broken on device.
//
//   On web (mouse), there is only ever 1 pointer, so this conflict
//   never surfaces — which explains why it worked on web.
//
// THE FIX:
//   • Listener  → behavior: HitTestBehavior.translucent
//     (receives raw pointer callbacks without consuming the hit-test,
//      so inner widgets still get their PointerDownEvents)
//   • RawGestureDetector → behavior: HitTestBehavior.opaque
//     (wins the arena and receives ALL pointers including 2nd finger)
//
// ALSO FIXED:
//   • Single-finger pan used currentScale from live matrix mid-gesture
//     instead of _startScale → caused scale drift after a zoom.
//     Now always uses _startScale captured in _onScaleStart.
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
  /// Consumers convert to canvas space via: (localPos - Offset(tx,ty)) / scale
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

  // ── Tap / long-press state (raw Listener — bypasses gesture arena) ─
  final Map<int, Offset> _activePointers = {};
  Offset? _tapStartPosition;
  DateTime? _tapStartTime;
  bool _tapCancelled = false;
  Timer? _longPressTimer;

  static const double _tapMaxMovementPx = 12.0;
  static const int _tapMaxMs = 300;
  static const Duration _longPressDelay = Duration(milliseconds: 500);

  // ── Listener: raw pointer events ──────────────────────────────────

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
      // Second finger → cancel tap, this is a pinch
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
      final elapsed = DateTime.now().difference(_tapStartTime!).inMilliseconds;
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
    // Capture scale at gesture START — never re-read mid-gesture
    _startScale = matrix.getMaxScaleOnAxis();
    _startTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    _startFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      // ── PINCH-TO-ZOOM ────────────────────────────────────────────
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
      // ── SINGLE-FINGER PAN ────────────────────────────────────────
      // Use _startScale (not live matrix) to prevent scale drift
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
    // Taps fully handled by Listener above — nothing needed here.
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
              // KEY FIX: translucent (NOT opaque) so the Listener receives
              // raw pointer callbacks for tap detection WITHOUT consuming
              // the hit-test. The RawGestureDetector below it (opaque) then
              // correctly receives ALL PointerDownEvents including the second
              // finger of a pinch — which is what was broken on Android.
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: RawGestureDetector(
                // opaque: ScaleGestureRecognizer owns the arena and receives
                // ALL pointers, including the 2nd finger of a pinch on Android.
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
