// lib/graph/widgets/edge_midpoint_layer.dart
//
// DAXELO KINREL — Edge Midpoint Hit Layer (v2)
//
// v2 (2026-06-23): Midpoint computation now uses the central
// [KinshipEdgeStyleResolver] + [KinshipLineShape] so hit zones line up
// with whatever curve the painter actually drew (sibling arc, cousin
// wide-arc, aunt/uncle shallow-S, grandparent extended bezier, etc.).
//
// Architecture:
//   • EdgeMidpointHitLayer sits between the edge CustomPaint layer and
//     the node layer in the canvas Stack.
//   • Hit circles are 44×44 dp (Material minimum touch target), rendered
//     fully transparent so the CustomPainter dots show through.
//   • The outer Listener-based panning is unaffected — a quick tap
//     (< 8 px movement) is dispatched through the GestureDetector arena
//     while a dragging finger never resolves onTap.

import 'package:flutter/material.dart';

import '../../core/kinship/kinship_edge_style.dart';
import '../data/family_graph_repository.dart' show GraphEdgeData;
// Needed for the GraphEdgeDataExt.isIndirectConnection extension used below.
import 'relationship_edge.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE MIDPOINT HIT LAYER
// ═══════════════════════════════════════════════════════════════════════

class EdgeMidpointHitLayer extends StatelessWidget {
  const EdgeMidpointHitLayer({
    super.key,
    required this.edges,
    required this.positions,
    required this.onMidpointTap,
    this.nodeWidth = 72.0,
    this.nodeHeight = 72.0,
    this.hitRadius = 22.0,
    this.blockedNodeIds = const {},
  });

  final List<GraphEdgeData> edges;
  final Map<String, Offset> positions;
  final void Function(String edgeId) onMidpointTap;
  final double nodeWidth;
  final double nodeHeight;
  final double hitRadius;
  final Set<String> blockedNodeIds;

  @override
  Widget build(BuildContext context) {
    final hits = <Widget>[];

    for (final edge in edges) {
      if (blockedNodeIds.contains(edge.sourceId) ||
          blockedNodeIds.contains(edge.targetId)) continue;

      final fromPos = positions[edge.sourceId];
      final toPos = positions[edge.targetId];
      if (fromPos == null || toPos == null) continue;

      final category = edge.isIndirectConnection
          ? KinshipEdgeCategory.indirect
          : KinshipEdgeClassifier.classify(edge.relationshipKey);
      final style = KinshipEdgeStyleResolver.styleForCategory(category);

      final mid = _computeMidpoint(fromPos, toPos, category, style.lineShape);

      hits.add(
        Positioned(
          left: mid.dx - hitRadius,
          top: mid.dy - hitRadius,
          width: hitRadius * 2,
          height: hitRadius * 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onMidpointTap(edge.id),
            child: const _HitCircle(),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: hits,
    );
  }

  /// Replicates the painter's endpoint + midpoint computation so the
  /// hit zone lines up with the visible dot / heart / label.
  Offset _computeMidpoint(
    Offset fromPos,
    Offset toPos,
    KinshipEdgeCategory category,
    KinshipLineShape shape,
  ) {
    final Offset start;
    final Offset end;

    if (category == KinshipEdgeCategory.spouse ||
        category == KinshipEdgeCategory.inLaw) {
      if (fromPos.dx <= toPos.dx) {
        start = Offset(fromPos.dx + nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx - nodeWidth / 2, toPos.dy);
      } else {
        start = Offset(fromPos.dx - nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx + nodeWidth / 2, toPos.dy);
      }
    } else {
      if (fromPos.dy <= toPos.dy) {
        start = Offset(fromPos.dx, fromPos.dy + nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy - nodeHeight / 2);
      } else {
        start = Offset(fromPos.dx, fromPos.dy - nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy + nodeHeight / 2);
      }
    }

    switch (shape) {
      case KinshipLineShape.dashedArc:
        final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
        final midX = (start.dx + end.dx) / 2;
        final cpY = start.dy - arcHeight;
        return Offset(
          midX,
          0.25 * start.dy + 0.5 * cpY + 0.25 * end.dy,
        );

      case KinshipLineShape.solidExtendedBezier:
        final dy = end.dy - start.dy;
        final cp1 = Offset(start.dx, start.dy + dy * 0.4);
        final cp2 = Offset(end.dx, start.dy + dy * 0.6);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.wideArcBezier:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final offset = dx.abs() * 0.3 + 40.0;
        final sign = dx >= 0 ? 1.0 : -1.0;
        final cp1 = Offset(start.dx + offset * sign, start.dy + dy * 0.33);
        final cp2 = Offset(end.dx - offset * sign, start.dy + dy * 0.67);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.dashedShallowS:
        final midY = (start.dy + end.dy) / 2;
        final dxOffset = (end.dx - start.dx) * 0.2;
        final cp1 = Offset(start.dx + dxOffset, midY - 15);
        final cp2 = Offset(end.dx - dxOffset, midY + 15);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.solidBezier:
      case KinshipLineShape.dashedStraight:
      case KinshipLineShape.dashedDefault:
        return Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
    }
  }
}

class _HitCircle extends StatelessWidget {
  const _HitCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
      ),
    );
  }
}
