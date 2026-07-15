// lib/graph/interaction/couple_union_model.dart
//
// DAXELO KINREL — Derived Couple Union Layout Model (Phase 6)
//
// Represents partner unions as GRAPH/LAYOUT entities — NOT as family
// members. A union is a visual junction that sits at the midpoint of
// a spouse edge, showing where a couple connects and where children
// descend from.
//
// CRITICAL INVARIANTS:
//   • A union is NEVER a database member.
//   • A union has NO profile, NO name, NO kinship.
//   • A union is NEVER included in member search results.
//   • A union is NEVER included in kinship BFS as a person.
//   • A union's identity is DETERMINISTIC — derived from sorted
//     canonical partner IDs. No random UUIDs. The same pair always
//     produces the same union ID.
//
// CHILD ATTACHMENT:
//   A child connects through a union ONLY when BOTH parent
//   relationships are confirmed. If only one parent is known, the
//   child connects directly to that parent (no union).
//
//   This correctly handles:
//     • remarriage (multiple unions per person)
//     • stepchildren (child of one partner, not the other)
//     • half-siblings (share one parent via different unions)

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;

/// A derived couple union — a layout/presentation entity representing
/// a confirmed partner pairing. NOT a family member.
///
/// The union ID is deterministic: `union_${sorted(partnerA, partnerB)}`.
/// The same pair of canonical person IDs always produces the same
/// union ID, across sessions and rebuilds.
@immutable
class CoupleUnion {
  const CoupleUnion({
    required this.id,
    required this.partnerAId,
    required this.partnerBId,
    required this.edgeId,
    required this.relationshipKey,
    this.childIds = const <String>{},
  });

  /// Deterministic ID: `union_${sorted(partnerA, partnerB)}`.
  /// Stable across rebuilds — no random UUIDs.
  final String id;

  /// The first partner's canonical person ID.
  final String partnerAId;

  /// The second partner's canonical person ID.
  final String partnerBId;

  /// The spouse edge ID that this union is derived from.
  final String edgeId;

  /// The relationship key of the spouse edge (e.g. 'wife', 'husband').
  final String relationshipKey;

  /// Child IDs that are confirmed children of BOTH partners.
  /// A child is only attached to the union when canonical relationship
  /// data supports the parent pairing — i.e. BOTH partners have a
  /// parent-child edge to the child.
  ///
  /// If only one parent-child edge exists, the child is NOT attached
  /// to the union (it connects directly to the known parent).
  final Set<String> childIds;

  /// The sorted partner ID pair — used for equality + identity.
  (String, String) get partnerPair {
    final ids = [partnerAId, partnerBId]..sort();
    return (ids[0], ids[1]);
  }

  /// True if [personId] is one of the partners.
  bool hasPartner(String personId) =>
      personId == partnerAId || personId == partnerBId;

  /// True if [personId] is a confirmed child of both partners.
  bool hasChild(String personId) => childIds.contains(personId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoupleUnion && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'CoupleUnion($id, $partnerAId + $partnerBId, '
      'children=${childIds.length})';
}

/// Derives couple unions from canonical relationship data.
///
/// Unions are derived from confirmed spouse/partner edges. The
/// derivation is deterministic — the same input always produces the
/// same output.
///
/// Rules:
///   1. Each spouse edge → one union (deterministic ID from sorted
///      partner IDs).
///   2. Multiple spouses → multiple unions (remarriage support).
///   3. A child is attached to a union ONLY when BOTH partners have
///      a parent-child edge to that child.
///   4. If only one parent-child edge exists, the child is NOT
///      attached (preserves direct parent-child representation).
///
/// [edges] — all canonical relationship edges as (fromId, toId, edgeId,
/// relationshipKey) tuples.
///
/// Returns a list of [CoupleUnion] entities. These are
/// presentation-only — they are NOT persisted to the database and are
/// NOT included in member search or kinship BFS.
List<CoupleUnion> deriveCoupleUnions(
  List<({String fromId, String toId, String edgeId, String relationshipKey})> edges,
) {
  // ── Step 1: Find all spouse edges ──
  const spouseKeys = {'spouse', 'husband', 'wife', 'partner'};
  final spouseEdges = edges
      .where((e) => spouseKeys.contains(e.relationshipKey.toLowerCase()))
      .toList();

  // ── Step 2: Build unions from spouse edges ──
  // Deduplicate by canonical pair — if A-B spouse edge exists in both
  // directions (which EdgeDeduplicator should have collapsed), we
  // still guard against it here.
  final unionsByPair = <String, CoupleUnion>{};
  for (final e in spouseEdges) {
    final pair = [e.fromId, e.toId]..sort();
    final pairKey = '${pair[0]}|${pair[1]}';
    if (unionsByPair.containsKey(pairKey)) continue; // already have this pair

    final unionId = 'union_${pair[0]}_${pair[1]}';
    unionsByPair[pairKey] = CoupleUnion(
      id: unionId,
      partnerAId: e.fromId,
      partnerBId: e.toId,
      edgeId: e.edgeId,
      relationshipKey: e.relationshipKey,
    );
  }

  // ── Step 3: Attach children to unions ──
  // A child is attached to a union ONLY when BOTH partners have a
  // parent-child edge to that child.
  const parentKeys = {'father', 'mother', 'parent', 'son', 'daughter', 'child'};
  final parentEdges = edges
      .where((e) => parentKeys.contains(e.relationshipKey.toLowerCase()))
      .toList();

  // Build: childId → set of parent IDs
  final parentsOfChild = <String, Set<String>>{};
  for (final e in parentEdges) {
    // The edge direction is: from=newPerson, to=anchor, key=relationship
    // For parent edges: from=parent, to=child (key describes parent's role)
    // OR: from=child, to=parent (key describes child's role)
    // We need to figure out which endpoint is the parent.
    //
    // If key is 'father'/'mother'/'parent' → from IS the parent, to IS the child
    // If key is 'son'/'daughter'/'child' → from IS the child, to IS the parent
    final key = e.relationshipKey.toLowerCase();
    String parentId;
    String childId;
    if (key == 'father' || key == 'mother' || key == 'parent') {
      parentId = e.fromId;
      childId = e.toId;
    } else {
      // son/daughter/child
      parentId = e.toId;
      childId = e.fromId;
    }
    parentsOfChild.putIfAbsent(childId, () => <String>{}).add(parentId);
  }

  // For each union, find children that have BOTH partners as parents.
  final updatedUnions = <CoupleUnion>[];
  for (final union in unionsByPair.values) {
    final confirmedChildren = <String>{};
    for (final entry in parentsOfChild.entries) {
      final childId = entry.key;
      final parents = entry.value;
      // The child is attached to this union only if BOTH partners
      // are confirmed parents.
      if (parents.contains(union.partnerAId) &&
          parents.contains(union.partnerBId)) {
        confirmedChildren.add(childId);
      }
    }
    updatedUnions.add(CoupleUnion(
      id: union.id,
      partnerAId: union.partnerAId,
      partnerBId: union.partnerBId,
      edgeId: union.edgeId,
      relationshipKey: union.relationshipKey,
      childIds: confirmedChildren,
    ));
  }

  return updatedUnions;
}

/// Computes the visual position of a union junction — the geometric
/// midpoint between the two partners' positions.
///
/// This is used by the painter to render a subtle junction glyph at
/// the couple's connection point. The glyph must NOT compete with
/// person nodes — it's a small visual hint, not a full node.
Offset unionMidpoint(Offset partnerAPos, Offset partnerBPos) {
  return Offset(
    (partnerAPos.dx + partnerBPos.dx) / 2,
    (partnerAPos.dy + partnerBPos.dy) / 2,
  );
}

/// Returns true if [personId] is a partner in any union.
///
/// Used to prevent union entities from being treated as persons in
/// search results, kinship BFS, or member lists.
bool isUnionEntity(String personId) {
  // Union IDs start with 'union_' — they are never real person IDs.
  // This function is a safety check: if someone accidentally passes
  // a union ID as a person ID, it will be rejected.
  return personId.startsWith('union_');
}

/// Resolves the effective source/target points for an edge, applying
/// the couple-union redirect (Phase 6) if applicable.
///
/// This is the SINGLE source of truth for edge endpoint geometry. It is
/// called by BOTH:
///   • the edge painter (for the actual rendered bezier curve), and
///   • the tap hit-tester (for tap-target midpoint computation).
///
/// These two call sites MUST NEVER diverge — that was the original
/// Phase 6 hit-test-parity bug (the painter redirected the parent→child
/// edge to start at the union midpoint, but the hit-tester still used
/// the parent's raw node position, so tapping the rendered line near
/// the union glyph silently missed). If you need this logic anywhere
/// else, call this function; do not reimplement it.
///
/// Redirect rules:
///   • If [sourceId] is a partner in a union and [targetId] is a child
///     attached to that union → the effective SOURCE becomes
///     `unionMidpoint(partnerA, partnerB)`. The target is unchanged.
///   • Symmetrically, if [sourceId] is a union child and [targetId] is
///     a partner in that union → the effective TARGET becomes the
///     union midpoint. The source is unchanged.
///   • Otherwise → both endpoints are returned unchanged.
///
/// [positionOf] is a lookup callback that returns the raw layout
/// position of a person ID (or null if unknown). Both call sites use
/// the SAME coordinate space (the painter's `positions` map and the
/// hit-tester's `_currentPositionsWithOffset` map are both populated
/// with the visual-circle Y offset applied — see
/// `_kCircleCenterYOffset` in `family_graph_engine_view.dart`). This
/// is critical: if the two maps ever drift into different coordinate
/// spaces, the union midpoints computed from each will silently
/// differ and the parity bug returns.
///
/// Returns a record `({Offset source, Offset target})` of the
/// effective endpoints to use for curve construction / hit-testing.
({Offset source, Offset target}) resolveEffectiveEdgeEndpoints({
  required String sourceId,
  required String targetId,
  required Offset rawSource,
  required Offset rawTarget,
  required List<CoupleUnion> coupleUnions,
  required Offset? Function(String personId) positionOf,
}) {
  for (final union in coupleUnions) {
    if (union.hasPartner(sourceId) && union.hasChild(targetId)) {
      final a = positionOf(union.partnerAId);
      final b = positionOf(union.partnerBId);
      if (a != null && b != null) {
        return (source: unionMidpoint(a, b), target: rawTarget);
      }
      // Union matches but partner positions unavailable — fall through
      // to the default return. (We `break` rather than `continue`
      // because at most one union can match a given (parent, child)
      // pair: a child is attached to a union only when BOTH partners
      // are confirmed parents, so the union is unique.)
      break;
    }
    if (union.hasChild(sourceId) && union.hasPartner(targetId)) {
      final a = positionOf(union.partnerAId);
      final b = positionOf(union.partnerBId);
      if (a != null && b != null) {
        return (source: rawSource, target: unionMidpoint(a, b));
      }
      break;
    }
  }
  return (source: rawSource, target: rawTarget);
}
