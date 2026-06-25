// lib/graph/widgets/graph_web_gestures.dart
//
// Created in v31 refactor.
//
// A web-specific gesture wrapper that adds mouse-wheel zoom and
// mouse-drag pan support for desktop browsers. On mobile, this widget
// is a no-op pass-through (touch gestures are handled by the
// GestureDetector inside FamilyGraphWidget).
//
// Why a separate widget?
//   - Flutter's GestureDetector doesn't natively handle mouse-wheel
//     events. On web, users expect scroll-wheel zoom (like Google Maps).
//   - The Listener widget can capture PointerScrollEvent, which we
//     convert to zoom transforms via [GraphGestureMath.zoomWithWheel].
//   - Keeping this separate from the main graph widget means the
//     mobile gesture code stays clean (no kIsWeb branches everywhere).
//
// Usage:
//   On web: wrap FamilyGraphWidget with GraphWebGestures, passing the
//   same TransformationController.
//   On mobile: skip the wrapper entirely (kIsWeb is false).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'graph_gesture_math.dart';

/// A widget that adds mouse-wheel zoom + mouse-drag pan for web.
///
/// On mobile (kIsWeb == false), this is a no-op pass-through.
/// On web, it wraps the child in a [Listener] that captures:
///   - PointerScrollEvent → zoom anchored at cursor
///   - PointerPanZoomUpdateEvent → trackpad pinch zoom + pan
///   - PointerMoveEvent (with button pressed) → mouse-drag pan
class GraphWebGestures extends StatelessWidget {
  const GraphWebGestures({
    super.key,
    required this.transformationController,
    required this.child,
  });

  /// The TransformationController to update when the user scrolls or
  /// drags. This should be the SAME controller used by the graph widget.
  final TransformationController transformationController;

  /// The child widget (typically the graph canvas).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On mobile, skip the wrapper entirely — touch gestures are
    // handled by the GestureDetector inside the graph widget.
    if (!kIsWeb) {
      return child;
    }

    Offset? dragStartTranslation;
    Offset? dragStartPosition;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Mouse-wheel zoom: anchor at cursor position
          final newMatrix = GraphGestureMath.zoomWithWheel(
            currentMatrix: transformationController.value,
            scrollDelta: event.scrollDelta.dy,
            cursorPosition: event.localPosition,
          );
          transformationController.value = newMatrix;
        }
      },
      onPointerPanZoomUpdate: (event) {
        // Trackpad pinch zoom + pan (common on macOS Safari/Chrome)
        if (event.scale != 1.0) {
          final currentMatrix = transformationController.value;
          final currentScale = currentMatrix.getMaxScaleOnAxis();
          final newScale =
              (currentScale * event.scale).clamp(0.05, 5.0);
          final scaleRatio = newScale / currentScale;
          final currentTx = currentMatrix.getTranslation().x;
          final currentTy = currentMatrix.getTranslation().y;
          final newTranslation = Offset(
            event.localPosition.dx +
                (currentTx - event.localPosition.dx) * scaleRatio,
            event.localPosition.dy +
                (currentTy - event.localPosition.dy) * scaleRatio,
          );
          transformationController.value = Matrix4.identity()
            ..translate(newTranslation.dx, newTranslation.dy)
            ..scale(newScale);
        } else if (event.panDelta != Offset.zero) {
          // Trackpad pan
          transformationController.value = GraphGestureMath.pan(
            currentMatrix: transformationController.value,
            delta: event.panDelta,
          );
        }
      },
      onPointerDown: (event) {
        // Mouse button pressed — start drag-pan
        if (event.buttons == 1) {
          // Left button
          dragStartTranslation =
              GraphGestureMath.getPan(transformationController.value);
          dragStartPosition = event.position;
        }
      },
      onPointerMove: (event) {
        // Mouse drag-pan: translate the canvas by the delta
        if (event.buttons == 1 &&
            dragStartTranslation != null &&
            dragStartPosition != null) {
          final delta = event.position - dragStartPosition!;
          final scale =
              transformationController.value.getMaxScaleOnAxis();
          transformationController.value = Matrix4.identity()
            ..translate(
              dragStartTranslation!.dx + delta.dx,
              dragStartTranslation!.dy + delta.dy,
            )
            ..scale(scale);
        }
      },
      onPointerUp: (_) {
        dragStartTranslation = null;
        dragStartPosition = null;
      },
      onPointerCancel: (_) {
        dragStartTranslation = null;
        dragStartPosition = null;
      },
      child: child,
    );
  }
}
