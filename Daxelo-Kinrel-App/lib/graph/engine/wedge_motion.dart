// lib/graph/engine/wedge_motion.dart
//
// DAXELO KINREL — Wedge graph motion, camera fit and edge routing.
//
// PURE DART (no widgets, no I/O). This is a 1:1 port of the math in the
// approved interactive preview, so the app animates, fits and routes
// edges exactly the same way:
//
//   • WedgeMotion      — one 450 ms ease-in-out curve; every node glides
//                        from its previous position to its new one; NEW
//                        nodes start at their parent's previous position.
//   • WedgeCameraFit   — fits a set of footprint boxes inside the visible
//                        area (between the top overlays and the bottom
//                        toolbar), scale clamped to [minScale, maxScale].
//   • WedgeEdgeRouter  — an edge is a STRAIGHT line unless that line
//                        crosses another node's footprint; only then is
//                        it bent into a quadratic curve using the smallest
//                        bow (90, 180, 270, 360, 450) that clears every
//                        footprint, preferring the side AWAY from the
//                        viewer, then the opposite side.
//
// Callers merge person positions and +N chip slots into ONE positions map
// (chip ids from ViewerWedgeLayout) and pass a [sizeOf] callback that
// returns each id's footprint (use WedgeLayoutConfig sizes).

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Animation curve + interpolation shared by nodes, chips, badges, edges
/// and the camera, so nothing ever lags behind anything else.
class WedgeMotion {
  const WedgeMotion._();

  /// One controller duration for node glide AND camera fit.
  static const int durationMs = 450;

  /// Ease-in-out: below 0.5 it is 2t², otherwise 1 − (−2t + 2)² / 2.
  static double easeInOut(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x < 0.5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;
  }

  /// Position of every id in [to] at animation progress [t] (0..1).
  ///
  /// • An id that existed in [from] glides from its previous position.
  /// • A NEW id starts at its parent's previous position (falling back
  ///   to the origin when the parent has no previous position).
  /// • Ids that are no longer in [to] are simply absent (removed
  ///   immediately, exactly like the preview).
  ///
  /// Take [from] as a snapshot of the CURRENTLY DRAWN (animated)
  /// positions at the moment of the tap, not the previous target.
  static Map<String, Offset> interpolate({
    required Map<String, Offset> from,
    required Map<String, Offset> to,
    required Map<String, String?> parentOf,
    required double t,
  }) {
    final e = easeInOut(t);
    final out = <String, Offset>{};
    to.forEach((id, target) {
      final parentId = parentOf[id];
      final start = from[id] ??
          (parentId != null ? from[parentId] : null) ??
          Offset.zero;
      out[id] = Offset(
        start.dx + (target.dx - start.dx) * e,
        start.dy + (target.dy - start.dy) * e,
      );
    });
    return out;
  }
}

/// Space reserved for overlays around the graph canvas (logical px).
class WedgeViewInsets {
  const WedgeViewInsets({
    this.left = 10,
    this.top = 8,
    this.right = 10,
    this.bottom = 78,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Result of a camera fit: uniform [scale] and screen-space
/// [translation] such that screen = world * scale + translation.
class WedgeCamera {
  const WedgeCamera({required this.scale, required this.translation});

  final double scale;
  final Offset translation;
}

class WedgeCameraFit {
  const WedgeCameraFit._();

  /// Footprint box of a node centred at [center].
  static Rect boxFor(Offset center, Size footprint) => Rect.fromCenter(
        center: center,
        width: footprint.width,
        height: footprint.height,
      );

  /// Fits the union of [boxes] into the visible area.
  ///
  /// scale = clamp(min(availW / boxW, availH / boxH), minScale, maxScale)
  /// where availW / availH exclude [insets]. The box centre lands on the
  /// centre of the visible area. Pass the app's minimum readable zoom as
  /// [minScale] so names and labels never fall below the level-of-detail
  /// threshold (the preview used 0.12).
  static WedgeCamera fit({
    required Iterable<Rect> boxes,
    required Size viewport,
    WedgeViewInsets insets = const WedgeViewInsets(),
    double minScale = 0.12,
    double maxScale = 1.6,
  }) {
    var x0 = double.infinity;
    var y0 = double.infinity;
    var x1 = double.negativeInfinity;
    var y1 = double.negativeInfinity;
    for (final b in boxes) {
      x0 = math.min(x0, b.left);
      y0 = math.min(y0, b.top);
      x1 = math.max(x1, b.right);
      y1 = math.max(y1, b.bottom);
    }
    if (x0 == double.infinity) {
      return WedgeCamera(
        scale: 1.0,
        translation: Offset(viewport.width / 2, viewport.height / 2),
      );
    }
    final boxW = math.max(x1 - x0, 1.0);
    final boxH = math.max(y1 - y0, 1.0);
    final availW = viewport.width - insets.left - insets.right;
    final availH = viewport.height - insets.top - insets.bottom;
    final scale = math.max(
      minScale,
      math.min(maxScale, math.min(availW / boxW, availH / boxH)),
    );
    final screenCx = (insets.left + viewport.width - insets.right) / 2;
    final screenCy = (insets.top + viewport.height - insets.bottom) / 2;
    return WedgeCamera(
      scale: scale,
      translation: Offset(
        screenCx - scale * (x0 + x1) / 2,
        screenCy - scale * (y0 + y1) / 2,
      ),
    );
  }
}

/// One edge between two ids that both have positions.
class WedgeEdge {
  const WedgeEdge(this.aId, this.bId);

  final String aId;
  final String bId;

  /// Stable key (a to b) used to cache a route per edge.
  String get key => '$aId>$bId';
}

class WedgeEdgeRouter {
  const WedgeEdgeRouter({
    required this.sizeOf,
    this.padding = 6.0,
    this.samples = 24,
    this.bowSteps = const <double>[90, 180, 270, 360, 450],
  });

  /// Footprint of an id (person, viewer or +N chip).
  final Size Function(String id) sizeOf;

  /// Extra clearance added on each axis when testing a footprint.
  final double padding;

  /// Number of segments the path is sampled into (the first and last
  /// points, which sit inside the endpoints, are not tested).
  final int samples;

  /// Candidate bow distances, smallest first.
  final List<double> bowSteps;

  /// Point on the straight line (a to b) or the quadratic curve
  /// (a, control, b) at parameter [t].
  static Offset pointAt(Offset a, Offset b, Offset? control, double t) {
    if (control == null) {
      return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    }
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
    );
  }

  bool _blocked(
    Offset a,
    Offset b,
    Offset? control,
    String aId,
    String bId,
    Map<String, Offset> positions,
  ) {
    for (var s = 1; s < samples; s++) {
      final p = pointAt(a, b, control, s / samples);
      for (final entry in positions.entries) {
        if (entry.key == aId || entry.key == bId) continue;
        final q = entry.value;
        final size = sizeOf(entry.key);
        if ((p.dx - q.dx).abs() < size.width / 2 + padding &&
            (p.dy - q.dy).abs() < size.height / 2 + padding) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns null when the straight line is clear (draw it straight).
  /// Otherwise returns the control point of the quadratic curve to draw.
  Offset? route(
    String aId,
    String bId,
    Map<String, Offset> positions,
  ) {
    final a = positions[aId];
    final b = positions[bId];
    if (a == null || b == null) return null;
    if (!_blocked(a, b, null, aId, bId, positions)) return null;

    final mx = (a.dx + b.dx) / 2;
    final my = (a.dy + b.dy) / 2;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final rawLen = math.sqrt(dx * dx + dy * dy);
    final len = rawLen == 0 ? 1.0 : rawLen;
    final nx = -dy / len;
    final ny = dx / len;
    // Prefer the side AWAY from the viewer (the origin).
    final side = (mx * nx + my * ny) >= 0 ? 1.0 : -1.0;

    final tries = <double>[
      for (final m in bowSteps) side * m,
      for (final m in bowSteps) -side * m,
    ];
    for (final t in tries) {
      final c = Offset(mx + nx * t, my + ny * t);
      if (!_blocked(a, b, c, aId, bId, positions)) return c;
    }
    final last = bowSteps.last;
    return Offset(mx + nx * side * last, my + ny * side * last);
  }

  /// Routes every edge once. Compute this ONCE per finished layout
  /// (when the animation settles), never on every paint.
  Map<String, Offset?> routeAll(
    Iterable<WedgeEdge> edges,
    Map<String, Offset> positions,
  ) {
    return <String, Offset?>{
      for (final e in edges) e.key: route(e.aId, e.bId, positions),
    };
  }
}
