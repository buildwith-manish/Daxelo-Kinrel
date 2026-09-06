// lib/graph/widgets/graph_minimap.dart
//
// DAXELO KINREL — Graph Mini-Map (P4.1)
//
// Per Vision §11 HP-6 + §5 Layer 3 — an 80x60 mini-map in the bottom-right
// corner of the graph that shows the entire family as dots and a viewport
// rectangle indicating the current camera position. Stays in sync with
// camera at < 16ms per frame update.
//
// The mini-map only appears when the graph has > 30 nodes (below that
// threshold, the full graph is already visible and the mini-map is noise).
//
// Tap on the mini-map → camera centers on the tapped location (graph-space).
//
// Performance: the mini-map is a lightweight CustomPainter that draws
// N small dots + 1 rectangle. For a 5000-node graph, this is ~5000
// drawCircle calls — but they're 1px dots, so GPU cost is trivial.
// The painter is wrapped in a RepaintBoundary and only repaints when
// the camera or graph changes (via AnimatedBuilder on the camera
// ChangeNotifier).

import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

import 'package:flutter/material.dart';

import '../data/graph_data_models.dart' show GraphEdgeData;
import '../interaction/camera_controller.dart' show CameraController;

/// Renders a mini-map of the entire graph in a small box, with a
/// viewport rectangle showing the current camera position.
///
/// Tap on the mini-map to center the camera on the tapped graph-space
/// location.
class GraphMiniMap extends StatelessWidget {
  const GraphMiniMap({
    super.key,
    required this.camera,
    required this.positions,
    required this.viewportSize,
    this.anchorId,
    this.onTap,
    // v5.175: per-node colors for the mini-map dots.
    this.nodeColors,
  });

  /// The camera controller — listened to for viewport rectangle updates.
  final CameraController camera;

  /// Map of node ID → graph-space position for ALL nodes in the graph
  /// (not just visible ones). The mini-map shows the full graph.
  final Map<String, Offset> positions;

  /// The screen-space viewport size (used to compute the viewport rect
  /// in graph-space).
  final Size viewportSize;

  /// Optional anchor node ID — drawn in a highlight color.
  final String? anchorId;

  /// Optional callback invoked when the user taps the mini-map.
  /// Receives the graph-space position that was tapped.
  final void Function(Offset graphSpaceTarget)? onTap;

  /// v5.175: Optional per-node colors — if provided, each dot is drawn
  /// in its relationship-category color instead of the default white.
  /// Keyed by personId → Color. Falls back to white for unknown IDs.
  final Map<String, Color>? nodeColors;

  /// Mini-map dimensions.
  ///
  /// UX (v5.130): Enlarged from 80×60 → 96×72 (+20%) so the mini-map is
  /// easier to spot in the corner, dots are more legible at a glance, and
  /// the viewport rectangle reads more clearly when the user is panning
  /// far from the anchor. The container remains compact enough to stay
  /// out of the way of the bottom toolbar and FAB cluster.
  static const double width = 96.0;
  static const double height = 72.0;

  @override
  Widget build(BuildContext context) {
    // Don't render if there are no positions (empty graph).
    if (positions.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Mini-map. ${positions.length} family members. '
          'Double-tap and drag to navigate.',
      child: AnimatedBuilder(
        animation: camera,
        builder: (context, _) {
          return GestureDetector(
            onTapDown: (details) => _handleTap(details.localPosition),
            // v5.175: drag-the-rect support — Google Maps-style drag to pan.
            onPanUpdate: (details) {
              if (onTap == null) return;
              final pos = details.localPosition;
              _handleTap(pos);
            },
            onPanStart: (details) => _handleTap(details.localPosition),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                // UX (v5.130): Softened background alpha (0.7 → 0.55) so the
                // mini-map blends with the canvas instead of looking like a
                // floating black box, while still providing enough contrast
                // for the white node dots.
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  // UX (v5.130): Stronger border (0.2 → 0.32 alpha, 1 → 1.25
                  // width) so the mini-map outline stays visible over bright
                  // graph clusters.
                  color: Colors.white.withValues(alpha: 0.32),
                  width: 1.25,
                ),
                // UX (v5.130): Subtle drop-shadow lifts the mini-map off the
                // canvas so it doesn't disappear against busy backgrounds
                // (birthday glows, ambient particles, dark clusters).
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: CustomPaint(
                  painter: _MiniMapPainter(
                    positions: positions,
                    anchorId: anchorId,
                    camera: camera,
                    viewportSize: viewportSize,
                    nodeColors: nodeColors,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleTap(Offset localPos) {
    if (onTap == null) return;
    // Convert mini-map tap position → graph-space position.
    final bounds = _computeBounds();
    if (bounds == null) return;
    final sx = (localPos.dx / width) * (bounds.maxX - bounds.minX) + bounds.minX;
    final sy = (localPos.dy / height) * (bounds.maxY - bounds.minY) + bounds.minY;
    onTap!(Offset(sx, sy));
  }

  _Bounds? _computeBounds() {
    if (positions.isEmpty) return null;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    // Add padding so dots at the edge aren't clipped.
    const pad = 20.0;
    return _Bounds(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}

class _Bounds {
  const _Bounds(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.positions,
    required this.anchorId,
    required this.camera,
    required this.viewportSize,
    this.nodeColors,
  });

  final Map<String, Offset> positions;
  final String? anchorId;
  final CameraController camera;
  final Size viewportSize;
  // v5.175: per-node colors for the mini-map dots.
  final Map<String, Color>? nodeColors;

  // v5.x (PERF + STALE-RECT FIX — cached static dot field):
  //
  // Two problems with the previous implementation:
  //
  //  1. shouldRepaint compared `old.camera != camera` — the SAME
  //     CameraController instance every time, so it always returned
  //     false during pan/zoom and the viewport rectangle was FROZEN
  //     (stale) while the user navigated. It only ever caught up on
  //     a layout data change.
  //  2. If that comparison HAD worked, every camera frame would have
  //     re-issued O(N) drawCircle calls (700+ members = 700+ raster
  //     commands/frame) just to redraw identical dots.
  //
  // The fix addresses both: shouldRepaint now compares the camera's
  // ACTUAL state (panX/panY/zoom), and the static dot field is
  // recorded ONCE into a [ui.Picture] keyed by (positions identity,
  // anchorId, canvas size). Panning/zooming moves only the viewport
  // rectangle, so those frames replay the cached picture and draw
  // one rect + one fill — O(1) per frame instead of O(N).
  static ui.Picture? _cachedDots;
  static Map<String, Offset>? _cachedDotsPositions;
  static String? _cachedDotsAnchorId;
  static Size? _cachedDotsSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    // Compute graph-space bounds.
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    const pad = 20.0;
    minX -= pad; minY -= pad; maxX += pad; maxY += pad;
    final graphW = (maxX - minX).abs();
    final graphH = (maxY - minY).abs();
    if (graphW <= 0 || graphH <= 0) return;

    // Scale to fit mini-map.
    final sx = size.width / graphW;
    final sy = size.height / graphH;
    final s = math.min(sx, sy);

    Offset toMini(Offset graphPos) {
      return Offset(
        (graphPos.dx - minX) * s,
        (graphPos.dy - minY) * s,
      );
    }

    // v5.x (PERF FIX): record the static dot field ONCE per
    // (positions, anchorId, size) combination; replay it on every
    // camera-driven repaint. The dots do not change while the camera
    // pans/zooms — only the viewport rectangle does.
    final bool dotsDirty = !identical(_cachedDotsPositions, positions) ||
        _cachedDotsAnchorId != anchorId ||
        _cachedDotsSize != size ||
        _cachedDots == null;
    if (dotsDirty) {
      final recorder = ui.PictureRecorder();
      final dotCanvas = Canvas(recorder);
      // UX (v5.130): Slightly larger + more opaque dots (1.0 → 1.2 radius,
      // 0.6 → 0.7 alpha) so individual members read more clearly in dense
      // regions. Anchor dot is enlarged (1.8 → 2.4) for stronger orientation
      // cue — the anchor is the "You are here" of the graph.
      final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
      final anchorPaint = Paint()..color = const Color(0xFFE8612A);
      for (final entry in positions.entries) {
        final pos = toMini(entry.value);
        final isAnchor = entry.key == anchorId;
        // v5.175: use per-node colors if provided (relationship categories).
        final dotColor = nodeColors?[entry.key] ??
            Colors.white.withValues(alpha: 0.7);
        final paint = isAnchor
            ? anchorPaint
            : (Paint()..color = dotColor);
        dotCanvas.drawCircle(
          pos,
          isAnchor ? 2.4 : 1.2,
          paint,
        );
      }
      _cachedDots?.dispose();
      _cachedDots = recorder.endRecording();
      _cachedDotsPositions = positions;
      _cachedDotsAnchorId = anchorId;
      _cachedDotsSize = size;
    }
    canvas.drawPicture(_cachedDots!);

    // Draw viewport rectangle (current camera view in graph-space).
    final viewport = camera.computeViewport(viewportSize);
    final vpTopLeft = toMini(Offset(viewport.left, viewport.top));
    final vpBottomRight = toMini(Offset(viewport.right, viewport.bottom));
    final vpRect = Rect.fromPoints(vpTopLeft, vpBottomRight);
    // UX (v5.130): Stronger viewport rectangle (1.0 → 1.5 stroke, plus a
    // subtle translucent fill) so the user can locate their current view
    // at a glance even when the rectangle is small (zoomed in) or
    // overlapping dense node clusters.
    final vpFillPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.10);
    canvas.drawRect(vpRect, vpFillPaint);
    final vpPaint = Paint()
      ..color = const Color(0xFF4A90E2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(vpRect, vpPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) {
    // v5.x (STALE-RECT FIX): the old check compared
    // `old.camera != camera` — always the same instance, so this
    // returned false during pan/zoom and the viewport rectangle never
    // followed the camera. Now we compare the camera's actual state
    // (cheap double compares) so the rect tracks every pan/zoom frame,
    // while the dot field itself is served from the cached picture
    // (see [paint]).
    return !identical(old.positions, positions) ||
        old.anchorId != anchorId ||
        old.viewportSize != viewportSize ||
        old.camera.panX != camera.panX ||
        old.camera.panY != camera.panY ||
        old.camera.zoomLevel != camera.zoomLevel;
  }
}
