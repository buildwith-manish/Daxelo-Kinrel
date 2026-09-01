// lib/graph/engine/branch_chip_layout.dart
//
// DAXELO KINREL — Branch chip placement (v5.x fix)
//
// Pure helper that computes the on-canvas rect for every collapsed-branch
// "+N" chip, with multi-direction collision avoidance against:
//   • other placed chip rects
//   • every visible node's full bounding box (so chips don't overlap
//     another person's circle OR name label)
//   • the chip's OWN node (the chip must sit BELOW the name label,
//     never on top of the parent node's circle or name)
//
// Extracted from _buildCollapsedBranchChips (branch_affordance.dart) so
// the placement logic is unit-testable without mounting a widget tree
// AND so the canvas hit-tester (_hitTestBranchChip) can call the SAME
// helper — the rendered chip position and the tap target can never
// drift apart (the bug pattern that recurred every time the two sites
// duplicated the formula).
//
// CONTRACT
// ────────
// Anchor: the chip sits centered horizontally on the parent node, top
// edge just below the node's full bounding box (the name label sits
// in the lower portion of the node box, so "just below the box" =
// just below the name label).
//
// Collision resolution: try the anchor first. If it collides, try a
// list of candidate offsets in this priority order:
//   1. Straight down in 18px steps (up to 4 steps) — keeps the chip
//      directly below the parent, the most visually-tethered position.
//   2. Below + slightly left (18px steps, 4 steps) — when the column
//      below is occupied by another chip.
//   3. Below + slightly right (18px steps, 4 steps) — mirror of (2).
//   4. Above the node (rare; only if the entire below-column is
//      blocked by other chips / nodes).
//
// If every candidate collides, place at the candidate with the LEAST
// overlap area and flag it for a leader line. The caller can then
// draw a thin line from the chip back to the parent node's center so
// the user can still see which person the chip belongs to.
//
// All inputs are in GRAPH SPACE — the caller passes raw node
// positions (the SAME positions map the chip builder uses) and the
// helper returns rects in graph space. The parent camera Transform
// scales them to screen space.

import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Rect, Size;

/// Geometry constants used by the helper. Mirrored from
/// `_FamilyGraphEngineViewState._kNodeSize` (140×176) and
/// `_kCircleCenterYOffset` (-28) — kept here as constants so the
/// helper has zero widget-layer dependencies and can be unit-tested
/// in isolation.
class BranchChipGeometry {
  BranchChipGeometry._();

  /// Full node bounding box (circle + glow + name label + badges).
  /// Matches `_FamilyGraphEngineViewState._kNodeSize`.
  static const Size nodeBoxSize = Size(140.0, 176.0);

  /// The visual circle's center offset from the node's Positioned
  /// center. Matches `_FamilyGraphEngineViewState._kCircleCenterYOffset`.
  static const double circleCenterYOffset = -28.0;

  /// Approximate chip dimensions (matches the maxWidth in
  /// _buildCollapsedBranchChips's Container, plus padding).
  static const double chipWidth = 200.0;
  static const double chipHeight = 32.0;

  /// Vertical gap between the parent node's bounding box and the
  /// chip's top edge. Small enough that the chip clearly belongs to
  /// the node above it; large enough that the chip doesn't visually
  /// touch the name label's descender.
  static const double anchorGapBelowNode = 8.0;

  /// Step size for the multi-direction collision search.
  static const double collisionStep = 18.0;

  /// Horizontal offset for the "below + slightly left/right"
  /// candidates. Wide enough that the chip clearly moves out from
  /// under another chip; narrow enough that it stays visually
  /// tethered to its own node.
  static const double lateralOffset = 60.0;

  /// Maximum number of straight-down steps before falling back to
  /// lateral / above candidates.
  static const int maxDownSteps = 4;
}

/// A request for a chip placement.
///
/// One per collapsed branch. The helper returns the placed rect
/// (and whether a leader line is needed) per request.
class BranchChipPlacementRequest {
  BranchChipPlacementRequest({
    required this.branchId,
    required this.rootPersonId,
    required this.rootPosition,
  });

  /// Stable identifier for the request (used for deterministic
  /// tie-breaking when two requests would resolve to the same
  /// candidate position).
  final String branchId;

  /// The person ID this chip is anchored to.
  final String rootPersonId;

  /// The graph-space position of the root person (the SAME value
  /// `layout.positions[rootPersonId]` returns in the widget layer).
  final Offset rootPosition;
}

/// The result of placing a single chip.
class BranchChipPlacement {
  BranchChipPlacement({
    required this.request,
    required this.rect,
    required this.needsLeaderLine,
  });

  /// The original request — kept so the caller can map results back
  /// to branches by ID.
  final BranchChipPlacementRequest request;

  /// The graph-space rect where the chip should be rendered.
  final Rect rect;

  /// True when the chip had to be placed far enough from its parent
  /// node that a leader line should be drawn from the chip back to
  /// the parent node's center. False in the common case (chip sits
  /// directly below the name label, no leader line needed).
  final bool needsLeaderLine;
}

/// Compute the chip placement for every request.
///
/// Inputs:
///   [requests]     — one per collapsed branch, in any order. The
///                    helper sorts them deterministically (by
///                    rootPosition Y, then X, then branchId) so the
///                    same layout always produces the same chip
///                    positions, frame-to-frame (no jitter).
///   [allNodeBoxes] — the graph-space rects of EVERY visible node's
///                    full bounding box. Used for collision avoidance
///                    so chips don't overlap other persons' circles
///                    or name labels. Each rect is the
///                    140×176 box centered on the node's raw position
///                    (the helper can compute these from a positions
///                    map via [nodeBoxForPosition], or the caller can
///                    pass them in directly).
///
/// Returns one [BranchChipPlacement] per request, in the SAME order
/// as [requests]. The caller can map back to branches by ID.
List<BranchChipPlacement> placeBranchChips({
  required List<BranchChipPlacementRequest> requests,
  required List<Rect> allNodeBoxes,
}) {
  if (requests.isEmpty) return const [];

  // ── Deterministic order: Y asc, then X asc, then branchId asc. ──
  // Top-to-bottom, left-to-right — the order a human would visually
  // scan the tree. This means a chip near the top of the tree gets
  // first pick of its anchor position, and chips below it adapt.
  // Stable across frames because the inputs are stable (positions
  // are deterministic; branch IDs are stable).
  final sorted = List<BranchChipPlacementRequest>.from(requests)
    ..sort((a, b) {
      final byY = a.rootPosition.dy.compareTo(b.rootPosition.dy);
      if (byY != 0) return byY;
      final byX = a.rootPosition.dx.compareTo(b.rootPosition.dx);
      if (byX != 0) return byX;
      return a.branchId.compareTo(b.branchId);
    });

  final placedChips = <Rect>[];
  final resultsById = <String, BranchChipPlacement>{};

  for (final req in sorted) {
    final placement = _placeOneChip(
      request: req,
      allNodeBoxes: allNodeBoxes,
      placedChips: placedChips,
    );
    placedChips.add(placement.rect);
    resultsById[req.branchId] = placement;
  }

  // Return in the ORIGINAL request order so the caller can zip the
  // results back with its branch list.
  return [for (final r in requests) resultsById[r.branchId]!];
}

/// Compute the full bounding-box rect for a node at [position].
///
/// The node's Positioned widget is centered on [position] with size
/// `BranchChipGeometry.nodeBoxSize` (140×176). The visual circle is
/// at the top of the Column (offset by `circleCenterYOffset` from
/// the box center). This helper returns the FULL box rect — callers
/// use it for collision avoidance so chips never overlap another
/// person's circle OR name label.
Rect nodeBoxForPosition(Offset position) {
  final size = BranchChipGeometry.nodeBoxSize;
  return Rect.fromCenter(
    center: position,
    width: size.width,
    height: size.height,
  );
}

/// Compute the parent node's bounding box for a chip placement
/// request — the chip must NOT overlap this box (the chip's own
/// parent). The chip sits BELOW this box.
Rect _parentBoxForRequest(BranchChipPlacementRequest req) {
  return nodeBoxForPosition(req.rootPosition);
}

/// Place a single chip, given the already-placed chips and all node
/// boxes. Tries the anchor first, then the candidate list. If every
/// candidate collides, picks the candidate with the least overlap
/// and marks it for a leader line.
BranchChipPlacement _placeOneChip({
  required BranchChipPlacementRequest request,
  required List<Rect> allNodeBoxes,
  required List<Rect> placedChips,
}) {
  final parentBox = _parentBoxForRequest(request);
  final anchor = _anchorRect(parentBox);

  // Build the candidate list — the anchor first, then the
  // multi-direction fallbacks.
  final candidates = <Rect>[anchor];

  // 1. Straight down in 18px steps (up to 4).
  for (var step = 1; step <= BranchChipGeometry.maxDownSteps; step++) {
    final dy = BranchChipGeometry.collisionStep * step;
    candidates.add(anchor.translate(0, dy));
  }

  // 2. Below + slightly left.
  final lateralOffset = BranchChipGeometry.lateralOffset;
  for (var step = 1; step <= BranchChipGeometry.maxDownSteps; step++) {
    final dy = BranchChipGeometry.collisionStep * step;
    candidates.add(anchor.translate(-lateralOffset, dy));
  }

  // 3. Below + slightly right.
  for (var step = 1; step <= BranchChipGeometry.maxDownSteps; step++) {
    final dy = BranchChipGeometry.collisionStep * step;
    candidates.add(anchor.translate(lateralOffset, dy));
  }

  // 4. Above the node (rare; only if the entire below-column is
  //    blocked). The "above" candidate sits above the parent node's
  //    bounding box with the same anchorGapBelowNode gap.
  final aboveAnchor = Rect.fromLTWH(
    anchor.left,
    parentBox.top -
        BranchChipGeometry.chipHeight -
        BranchChipGeometry.anchorGapBelowNode,
    BranchChipGeometry.chipWidth,
    BranchChipGeometry.chipHeight,
  );
  candidates.add(aboveAnchor);

  // Find the first candidate that doesn't collide with anything.
  for (final candidate in candidates) {
    if (!_collidesWithAny(candidate, allNodeBoxes, placedChips)) {
      // Check whether this candidate is far enough from the parent
      // node that a leader line is needed. The leader-line
      // threshold is "more than 2 down-steps below the anchor, OR
      // any lateral offset". This keeps the chip visually tethered
      // — the user can see which person it belongs to.
      final dyFromAnchor = candidate.top - anchor.top;
      final dxFromAnchor = (candidate.left - anchor.left).abs();
      final needsLeader =
          dyFromAnchor > BranchChipGeometry.collisionStep * 2 ||
              dxFromAnchor > 1.0;
      return BranchChipPlacement(
        request: request,
        rect: candidate,
        needsLeaderLine: needsLeader,
      );
    }
  }

  // Every candidate collides. Pick the candidate with the LEAST
  // total overlap area (sum of overlaps with all node boxes + all
  // placed chips). This minimizes the visual mess. Mark for a
  // leader line so the user can see which person the chip belongs
  // to.
  Rect? bestCandidate;
  var bestOverlap = double.infinity;
  for (final candidate in candidates) {
    final overlap = _totalOverlapArea(candidate, allNodeBoxes, placedChips);
    if (overlap < bestOverlap) {
      bestOverlap = overlap;
      bestCandidate = candidate;
    }
  }
  // bestCandidate is always non-null here because candidates is
  // non-empty (we always add at least the anchor + down-steps).
  return BranchChipPlacement(
    request: request,
    rect: bestCandidate!,
    needsLeaderLine: true,
  );
}

/// The anchor rect for a chip below the parent node box: centered
/// horizontally on the parent's center X, top edge just below the
/// parent's box bottom edge (with the small anchorGapBelowNode gap).
Rect _anchorRect(Rect parentBox) {
  final parentCenterX = parentBox.center.dx;
  return Rect.fromLTWH(
    parentCenterX - BranchChipGeometry.chipWidth / 2,
    parentBox.bottom + BranchChipGeometry.anchorGapBelowNode,
    BranchChipGeometry.chipWidth,
    BranchChipGeometry.chipHeight,
  );
}

/// True if [rect] overlaps any node box or any placed chip rect.
bool _collidesWithAny(
    Rect rect, List<Rect> allNodeBoxes, List<Rect> placedChips) {
  for (final nodeBox in allNodeBoxes) {
    if (rect.overlaps(nodeBox)) return true;
  }
  for (final placedChip in placedChips) {
    if (rect.overlaps(placedChip)) return true;
  }
  return false;
}

/// Total overlap area of [rect] with all node boxes + placed chips.
/// Used to pick the "least bad" candidate when every candidate
/// collides.
double _totalOverlapArea(
    Rect rect, List<Rect> allNodeBoxes, List<Rect> placedChips) {
  var total = 0.0;
  for (final nodeBox in allNodeBoxes) {
    if (rect.overlaps(nodeBox)) {
      total += _overlapArea(rect, nodeBox);
    }
  }
  for (final placedChip in placedChips) {
    if (rect.overlaps(placedChip)) {
      total += _overlapArea(rect, placedChip);
    }
  }
  return total;
}

double _overlapArea(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return 0.0;
  return (right - left) * (bottom - top);
}
