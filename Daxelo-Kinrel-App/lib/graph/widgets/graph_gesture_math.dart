// lib/graph/widgets/graph_gesture_math.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// Pure-math helpers for gesture-based pan/zoom transforms.
// Stateless and side-effect-free — trivial to unit-test.
//
// Web + mobile compatible: the math is platform-agnostic. The actual
// gesture detection (GestureDetector on mobile, Listener + pointer
// events on web) lives in the widget; this file just computes the
// resulting transform matrices.
//
// WEB-SPECIFIC NOTE:
// On web (desktop), users expect mouse-wheel zoom. The [zoomWithWheel]
// method computes the transform for a scroll-wheel event, anchoring
// the zoom at the mouse cursor position (like Google Maps).

import 'package:flutter/material.dart';

/// Pure-math helpers for computing graph pan/zoom transforms.
class GraphGestureMath {
  GraphGestureMath._();

  /// Minimum zoom scale (zoomed all the way out).
  static const double minScale = 0.05;

  /// Maximum zoom scale (zoomed all the way in).
  static const double maxScale = 5.0;

  /// Computes the new transform matrix after a scale gesture update.
  ///
  /// [startScale] — the scale at the beginning of the gesture.
  /// [startTranslation] — the translation at the beginning of the gesture.
  /// [startFocalPoint] — the focal point (in widget-local coords) at gesture start.
  /// [currentScale] — the scale factor from the gesture (1.0 = no change).
  /// [currentFocalPoint] — the current focal point (in widget-local coords).
  ///
  /// Returns a [Matrix4] that combines the new scale + translation,
  /// anchored at the focal point so the point under the user's fingers
  /// stays fixed during the zoom.
  static Matrix4 computeScaleUpdate({
    required double startScale,
    required Offset startTranslation,
    required Offset startFocalPoint,
    required double currentScale,
    required Offset currentFocalPoint,
  }) {
    final newScale = (startScale * currentScale).clamp(minScale, maxScale);
    final scaleRatio = startScale == 0 ? 1.0 : newScale / startScale;

    final newTranslation = Offset(
      currentFocalPoint.dx +
          (startTranslation.dx - startFocalPoint.dx) * scaleRatio,
      currentFocalPoint.dy +
          (startTranslation.dy - startFocalPoint.dy) * scaleRatio,
    );

    return Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);
  }

  /// Computes the new transform matrix for a mouse-wheel zoom event
  /// (web/desktop only — mobile uses pinch gestures).
  ///
  /// [currentMatrix] — the current transform matrix.
  /// [scrollDelta] — the scroll delta (positive = zoom out, negative = zoom in).
  /// [cursorPosition] — the mouse cursor position in widget-local coords.
  ///
  /// The zoom is anchored at [cursorPosition] so the point under the
  /// cursor stays fixed — standard desktop map/web-app behavior.
  static Matrix4 zoomWithWheel({
    required Matrix4 currentMatrix,
    required double scrollDelta,
    required Offset cursorPosition,
  }) {
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    // Each scroll "click" changes zoom by ~10%. Negative scrollDelta
    // (scroll up / toward screen) zooms IN.
    final zoomFactor = 1.0 - (scrollDelta * 0.001).clamp(-0.5, 0.5);
    final newScale = (currentScale * zoomFactor).clamp(minScale, maxScale);

    if (newScale == currentScale) return currentMatrix; // Already at limit

    final currentTx = currentMatrix.getTranslation().x;
    final currentTy = currentMatrix.getTranslation().y;

    // Anchor the zoom at the cursor position:
    //   newTranslation = cursor + (oldTranslation - cursor) * (newScale / oldScale)
    final scaleRatio = newScale / currentScale;
    final newTranslation = Offset(
      cursorPosition.dx + (currentTx - cursorPosition.dx) * scaleRatio,
      cursorPosition.dy + (currentTy - cursorPosition.dy) * scaleRatio,
    );

    return Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);
  }

  /// Computes the new transform matrix for a pure pan (drag) update.
  ///
  /// [currentMatrix] — the current transform matrix.
  /// [delta] — the pan delta since the last frame.
  static Matrix4 pan({
    required Matrix4 currentMatrix,
    required Offset delta,
  }) {
    final scale = currentMatrix.getMaxScaleOnAxis();
    final tx = currentMatrix.getTranslation().x;
    final ty = currentMatrix.getTranslation().y;

    return Matrix4.identity()
      ..translate(tx + delta.dx, ty + delta.dy)
      ..scale(scale);
  }

  /// Extracts the current zoom level from a transform matrix.
  static double getZoom(Matrix4 matrix) => matrix.getMaxScaleOnAxis();

  /// Extracts the current pan offset from a transform matrix.
  static Offset getPan(Matrix4 matrix) {
    final t = matrix.getTranslation();
    return Offset(t.x, t.y);
  }

  /// Computes a "fit-to-viewport" transform matrix that centers and
  /// scales the graph canvas to fit within the given screen dimensions,
  /// leaving a [margin] border on all sides.
  ///
  /// Used by the auto-center logic when the graph first loads or when
  /// the layout changes (new members added/removed).
  ///
  /// [screenW] / [screenH] — viewport dimensions (from LayoutBuilder constraints).
  /// [canvasW] / [canvasH] — graph canvas dimensions (from GraphLayoutResult).
  /// [nodeCount] — number of nodes; if ≤ 12, the fit scale is allowed to
  ///               go up to 2.0× so small graphs fill the viewport. Larger
  ///               graphs cap at 1.0× to avoid pixelation.
  /// [margin] — pixels of padding around the fitted canvas (default 32).
  ///
  /// Returns null if any dimension is ≤ 0 (can't compute a fit).
  static Matrix4? computeFitTransform({
    required double screenW,
    required double screenH,
    required double canvasW,
    required double canvasH,
    required int nodeCount,
    double margin = 32.0,
  }) {
    if (screenW <= 0 || screenH <= 0 || canvasW <= 0 || canvasH <= 0) {
      return null;
    }

    final fitScaleX = (screenW - margin * 2) / canvasW;
    final fitScaleY = (screenH - margin * 2) / canvasH;
    var fitScale = fitScaleX < fitScaleY ? fitScaleX : fitScaleY;

    // Small graphs (≤12 nodes) can scale up to 2.0× to fill the viewport.
    // Large graphs stay at 1.0× max to avoid pixelation.
    final double fitCeiling = nodeCount <= 12 ? 2.0 : 1.0;
    if (fitScale > fitCeiling) fitScale = fitCeiling;
    if (fitScale < minScale) fitScale = minScale;

    // Center the canvas in the viewport:
    //   translate = (viewport_center) - (canvas_center * scale)
    final canvasCenterX = canvasW / 2;
    final canvasCenterY = canvasH / 2;
    final translateX = (screenW / 2) - (canvasCenterX * fitScale);
    final translateY = (screenH / 2) - (canvasCenterY * fitScale);

    return Matrix4.identity()
      ..translate(translateX, translateY)
      ..scale(fitScale);
  }
}
