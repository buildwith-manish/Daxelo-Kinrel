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
  List<({String fromId, String toId, String edgeId, String relationshipKey, String? labelAtoB})> edges,
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
  // v5.174: use labelAtoB for filtering (relationshipKey is always 'parent')
  const parentKeys = {'father', 'mother', 'parent', 'son', 'daughter', 'child',
                      'grandfather', 'grandmother', 'grandparent',
                      'grandchild', 'grandson', 'granddaughter'};
  final parentEdges = edges
      .where((e) => parentKeys.contains(
          (e.labelAtoB ?? e.relationshipKey).toLowerCase()))
      .toList();

  // Build: childId → set of parent IDs
  final parentsOfChild = <String, Set<String>>{};
  for (final e in parentEdges) {
    // v5.174: use labelAtoB for correct parent-child direction.
    // The canonical convention (graph_layout_service.dart:76-77):
    //   from=A, to=B, labelAtoB='father' → B IS the father of A
    //   → toId (B) is the PARENT, fromId (A) is the CHILD.
    //   from=A, to=B, labelAtoB='son' → B IS the son of A
    //   → fromId (A) is the PARENT, toId (B) is the CHILD.
    //
    // The DB stores relationshipKey='parent' for ALL non-spouse edges,
    // so we MUST use labelAtoB to determine the actual direction.
    final key = (e.labelAtoB ?? e.relationshipKey).toLowerCase();
    String parentId;
    String childId;
    if (key == 'father' || key == 'mother' || key == 'parent' ||
        key == 'grandfather' || key == 'grandmother' || key == 'grandparent') {
      // toPerson IS the parent (canonical: "B is the father of A")
      parentId = e.toId;
      childId = e.fromId;
    } else if (key == 'son' || key == 'daughter' || key == 'child' ||
               key == 'grandchild' || key == 'grandson' || key == 'granddaughter') {
      // fromPerson IS the parent (canonical: "B is the son of A")
      parentId = e.fromId;
      childId = e.toId;
    } else {
      // Unknown key — skip (shouldn't happen with the DB constraint)
      continue;
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

/// Resolves the effective source/target points for an edge.
///
/// This is the SINGLE source of truth for edge endpoint geometry. It is
/// called by BOTH:
///   • the edge painter (for the actual rendered bezier curve), and
///   • the tap hit-tester (for tap-target midpoint computation).
///
/// These two call sites MUST NEVER diverge. If you need edge endpoint
/// geometry anywhere else, call this function; do not reimplement it.
///
/// EDGE-ANCHOR FIX (this commit): this function is now a NO-OP for the
/// couple-union redirect. It returns the raw source/target unchanged
/// for EVERY edge — parent→child, child→parent, spouse, sibling, etc.
///
/// The user's spec is explicit: "Every edge in the graph must follow
/// the exact same geometric rule: sourceNode.center → targetNode.center.
/// This rule must apply to ALL nodes — Anchor, Selected, Unselected,
/// Parent, Child, Sibling, Spouse, Highlighted 'You' node. No
/// special-case anchoring logic should exist for specific node types
/// unless absolutely necessary."
///
/// The previous (Phase 6) implementation redirected parent→child
/// edges (where the parent was a partner in a confirmed couple union
/// and the child was attached to that union) to start at the
/// `unionMidpoint(partnerA, partnerB)` instead of the parent's node
/// center. Symmetrically for child→parent edges. This was a
/// special-case anchoring logic for parent/spouse/child nodes that
/// violated the user's spec — multiple edges from the same parent
/// node did NOT converge at the parent's center, they converged at
/// the union midpoint (an "offset position" between the two parents).
/// The user reported this as "non-anchor nodes still appear to have
/// edges attaching from offset positions, perimeter points, or
/// node-edge locations rather than behaving as true center-to-center
/// connections."
///
/// The redirect was a deliberate visual feature for showing family
/// structure (children visually descending from the couple's union,
/// not from one parent's center). Removing it changes the visual
/// representation to the more standard "each parent has their own edge
/// to the child" convention — which is what the user's spec requires.
/// The underlying family-structure DATA (which edges exist, which
/// unions are derived) is unchanged; only the edge endpoint geometry
/// changes.
///
/// The `coupleUnions` and `positionOf` parameters are KEPT in the
/// signature for API compatibility — existing call sites in
/// `engine_edge_painter.dart` and `interaction_mixin.dart` continue
/// to compile and call this function without changes. The function
/// body simply ignores them and returns the raw source/target. This
/// keeps the painter and hit-tester in sync (the original purpose
/// of the shared helper) — both use the raw box-center endpoints.
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
  // EDGE-ANCHOR FIX (this commit): NO redirect. Every edge anchors at
  // the box center of its source and target nodes — no special-case
  // routing for parent→child edges through the union midpoint. The
  // coupleUnions, positionOf, sourceId, and targetId parameters are
  // accepted for API compatibility (the painter and hit-tester call
  // sites pass them) but intentionally not consulted — see the doc
  // comment above for the reasoning.
  return (source: rawSource, target: rawTarget);
}
