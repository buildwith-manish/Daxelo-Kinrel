// lib/features/family_map/widgets/relationship_path_overlay.dart
//
// DAXELO KINREL — P10.5 Relationship Path Overlay (Flutter overlay
// fallback).
//
// Renders relationship edges as a Flutter [CustomPainter] overlay
// because maplibre 0.3.5 does not expose `setPaintProperty`
// (Rule 12 fallback). Reads pin screen positions from the
// [MapController] on every repaint triggered by the
// [progressNotifier].
//
// Extracted from `family_map_screen.dart` (originally the private
// `_RelationshipPathOverlay` widget + `_RelationshipPathPainter`
// painter) as part of the file decomposition. Both classes are now
// public.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/kinship/heart_shape.dart';
import '../config/map_visual_constants.dart';
import '../providers/family_map_provider.dart';
import 'animated_relationship_path.dart'
    show categorizeRelationship, PathStyle;

/// Renders relationship edges as a Flutter overlay.
///
/// Listens to the [progressNotifier] for repaint triggers (bumped by
/// the [AnimatedRelationshipPath] on each animation tick) and polls
/// each pin's screen position from the [mapController] on every
/// ticker frame.
class RelationshipPathOverlay extends StatefulWidget {
  const RelationshipPathOverlay({
    super.key,
    required this.mapController,
    required this.edges,
    required this.pins,
    required this.progressNotifier,
    required this.reducedMotion,
  });

  final MapController? mapController;
  final List<MapRelationshipEdge> edges;
  final List<MapPin> pins;
  final ValueNotifier<int> progressNotifier;
  final bool reducedMotion;

  @override
  State<RelationshipPathOverlay> createState() =>
      _RelationshipPathOverlayState();
}

class _RelationshipPathOverlayState extends State<RelationshipPathOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, Offset> _screenPositions = {};

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final controller = widget.mapController;
    if (controller == null) return;
    bool changed = false;
    for (final pin in widget.pins) {
      try {
        final screen =
            controller.toScreenLocation(Geographic(lon: pin.lng, lat: pin.lat));
        if (_screenPositions[pin.personId] != screen) {
          _screenPositions[pin.personId] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore
      }
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: RelationshipPathPainter(
          edges: widget.edges,
          screenPositions: _screenPositions,
          progress: widget.reducedMotion
              ? 0.0
              : (DateTime.now().millisecondsSinceEpoch %
                      MapVisualConstants.relationshipFlowCycle.inMilliseconds)
                  .toDouble() /
                  MapVisualConstants.relationshipFlowCycle.inMilliseconds,
          repaintNotifier: widget.progressNotifier,
        ),
      ),
    );
  }
}

/// [CustomPainter] that draws each [MapRelationshipEdge] as a line
/// (solid or dashed) between the two pin screen positions, with an
/// optional heart midpoint for close-family edges.
class RelationshipPathPainter extends CustomPainter {
  RelationshipPathPainter({
    required this.edges,
    required this.screenPositions,
    required this.progress,
    required this.repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final List<MapRelationshipEdge> edges;
  final Map<String, Offset> screenPositions;
  final double progress;
  final ValueNotifier<int> repaintNotifier;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || screenPositions.length < 2) return;
    for (final edge in edges) {
      final a = screenPositions[edge.pinA.personId];
      final b = screenPositions[edge.pinB.personId];
      if (a == null || b == null) continue;
      _drawEdge(canvas, edge, a, b);
    }
  }

  void _drawEdge(Canvas canvas, MapRelationshipEdge edge, Offset a, Offset b) {
    final category = categorizeRelationship(edge.relationshipKey);
    final style = PathStyle.forCategory(category);
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round;

    if (style.dashed) {
      _drawDashedLine(canvas, a, b, paint);
    } else {
      canvas.drawLine(a, b, paint);
    }

    if (style.showHeartMidpoint) {
      final mid = (a + b) / 2;
      final path = HeartShape.buildPath(center: mid, width: 14, height: 14);
      canvas.drawPath(
        path,
        Paint()
          ..color = KinrelColors.orange
          ..style = ui.PaintingStyle.fill,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final total = dashWidth + dashGap;
    final distance = (b - a).distance;
    if (distance == 0) return;
    final count = (distance / total).floor();
    final dir = (b - a) / distance;
    for (var i = 0; i < count; i++) {
      final start = a + dir * (i * total);
      final end = start + dir * dashWidth;
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RelationshipPathPainter old) =>
      old.progress != progress || old.edges != edges;
}
