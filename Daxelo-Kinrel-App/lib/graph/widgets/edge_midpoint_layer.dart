// lib/graph/widgets/edge_midpoint_layer.dart
//
// DAXELO KINREL — Edge Midpoint Hit Layer
//
// Transparent GestureDetector circles placed at every connection
// midpoint in canvas-space. Lives INSIDE the zoom/pan transform so
// tap positions always match the visible dots regardless of zoom.
//
// Architecture:
//   • EdgeMidpointHitLayer sits between the edge CustomPaint layer
//     and the node layer in the canvas Stack.
//   • Hit circles are 44×44 dp (Material minimum touch target), but
//     rendered fully transparent so the CustomPainter dots show through.
//   • The outer Listener-based panning is unaffected because a quick
//     tap (< 8 px movement) is dispatched through the GestureDetector
//     arena while a dragging finger never resolves onTap.

import 'package:flutter/material.dart';

import '../data/family_graph_repository.dart' show GraphEdgeData;
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

  /// All relationship edges in the current graph.
  final List<GraphEdgeData> edges;

  /// Canvas-space positions for every person node.
  final Map<String, Offset> positions;

  /// Called when a midpoint dot is tapped. Receives the edge id.
  final void Function(String edgeId) onMidpointTap;

  /// Width of a node card in canvas dp (must match RelationshipEdge).
  final double nodeWidth;

  /// Height of a node card in canvas dp (must match RelationshipEdge).
  final double nodeHeight;

  /// Touch-target radius around each midpoint (dp).
  final double hitRadius;

  /// Blocked node ids — skip their edges (same as the painter).
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
          ? EdgeCategory.indirect
          : EdgeStyleResolver.categoryFor(edge.relationshipKey);

      final mid = _computeMidpoint(fromPos, toPos, category);

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

  // ── Midpoint computation ───────────────────────────────────────────

  /// Replicates RelationshipEdge._computeEndpoints + midpoint formula.
  /// For bezier / sibling-arc edges we compute the TRUE t=0.5 point
  /// so the hit zone lines up with the visible label / dot.
  Offset _computeMidpoint(
    Offset fromPos,
    Offset toPos,
    EdgeCategory category,
  ) {
    final Offset start;
    final Offset end;

    if (category == EdgeCategory.spouse || category == EdgeCategory.inLaw) {
      // Horizontal spouse connector
      if (fromPos.dx <= toPos.dx) {
        start = Offset(fromPos.dx + nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx - nodeWidth / 2, toPos.dy);
      } else {
        start = Offset(fromPos.dx - nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx + nodeWidth / 2, toPos.dy);
      }
      // Straight line → linear midpoint
      return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    }

    // Vertical-ish edges
    if (fromPos.dy <= toPos.dy) {
      start = Offset(fromPos.dx, fromPos.dy + nodeHeight / 2);
      end = Offset(toPos.dx, toPos.dy - nodeHeight / 2);
    } else {
      start = Offset(fromPos.dx, fromPos.dy - nodeHeight / 2);
      end = Offset(toPos.dx, toPos.dy + nodeHeight / 2);
    }

    if (category == EdgeCategory.sibling) {
      // Quadratic bezier arc above siblings.
      // controlPoint = (midX, start.dy - arcHeight)
      // t=0.5 on a quadratic: (1/4)*P0 + (1/2)*P1 + (1/4)*P2
      final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
      final midX = (start.dx + end.dx) / 2;
      final cpY = start.dy - arcHeight;
      return Offset(
        midX,
        0.25 * start.dy + 0.5 * cpY + 0.25 * end.dy,
      );
    }

    // Cubic bezier with control points at midY:
    // At t=0.5 the x-midpoint is always the linear midX,
    // and y-midpoint is always midY — same as linear midpoint.
    return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  }
}

// ── Small invisible circle used as the tappable hit area ──────────────

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
