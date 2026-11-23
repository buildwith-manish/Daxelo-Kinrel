// lib/graph/engine/large_tree_default.dart
//
// DAXELO KINREL - first-open default for LARGE family trees (G2b).
//
// PURE DART: no widgets, no Riverpod, no I/O.
//
// THRESHOLD: a tree is "large" when it has MORE than [kLargeTreeThreshold]
// people. The value is the existing [kNodeBudget] (50) - the budget the
// wedge layout already enforces (G2a audit, section 6) - so no second
// magic number exists. Trees at or below it keep today's behaviour.
//
// DEFAULT (large trees only): the wedge layout is already centred on
// "me" and already shows my direct connections. This helper decides the
// two extra pieces of intent that make the first view readable:
//   1. expand MY PARENTS, so their own parents (2 generations up) and
//      my siblings appear under them. Every other branch stays collapsed.
//   2. raise the viewer's page so my spouse, parents, children and
//      siblings are never pushed behind a "+N" chip.
// The result is applied through the EXISTING wedge state
// (WedgeViewNotifier.seedDefault); no new state class is involved.

import '../../core/graph/graph_service.dart' show inverseTypeMap;
import '../../core/kinship/kinship_edge_style.dart' show KinshipEdgeCategory;
import '../../core/kinship/structural_kinship_classifier.dart'
    show StructuralKinshipClassifier;
import '../interaction/branch_collapse_state.dart' show kNodeBudget;
import 'viewer_wedge_layout.dart' show WedgeLink;

/// A tree with MORE people than this gets the large-tree default.
const int kLargeTreeThreshold = kNodeBudget;

/// True when [personCount] people make the tree "large".
bool isLargeTree(int personCount) => personCount > kLargeTreeThreshold;

/// The intent to seed into the wedge state on first open.
class LargeTreeDefault {
  const LargeTreeDefault({
    required this.expandedRoots,
    required this.viewerPages,
  });

  /// Persons to expand (the viewer's parents).
  final Set<String> expandedRoots;

  /// Page index for the viewer (key = viewer id). Empty when page 0 is
  /// enough to show every spouse / parent / child / sibling.
  final Map<String, int> viewerPages;
}

/// Computes the large-tree default for [viewerId] from the full link list.
///
/// Link semantics match [ViewerWedgeLayout.compute]: [WedgeLink.keyAtoB]
/// (or relationshipKey) means "toId is fromId's <key>"; the reverse key
/// is keyBtoA, else the canonical inverse.
LargeTreeDefault computeLargeTreeDefault({
  required String viewerId,
  required List<WedgeLink> links,
  int pageSize = 8,
}) {
  final keyFromViewer = <String, String>{};
  for (final link in links) {
    final a = link.fromId;
    final b = link.toId;
    if (a.isEmpty || b.isEmpty || a == b) continue;
    final forward = link.keyAtoB ?? link.relationshipKey;
    if (a == viewerId) {
      keyFromViewer[b] = forward;
    } else if (b == viewerId) {
      keyFromViewer[a] = link.keyBtoA ??
          inverseTypeMap[forward] ??
          inverseTypeMap[link.relationshipKey] ??
          link.relationshipKey;
    }
  }

  final parents = <String>{};
  var closeCount = 0;
  keyFromViewer.forEach((neighbor, key) {
    if (key.isEmpty) return;
    final category = StructuralKinshipClassifier.classify(path: [key]).category;
    switch (category) {
      case KinshipEdgeCategory.parent:
        parents.add(neighbor);
        closeCount++;
      case KinshipEdgeCategory.spouse:
      case KinshipEdgeCategory.child:
      case KinshipEdgeCategory.sibling:
        closeCount++;
      default:
        break;
    }
  });

  // The layout ranks the viewer's children closest-first (spouse, parent,
  // child, sibling, ...), so the first [closeCount] slots are exactly the
  // people that must stay visible. Paging is cumulative.
  final page = closeCount > pageSize ? (closeCount - 1) ~/ pageSize : 0;
  return LargeTreeDefault(
    expandedRoots: parents,
    viewerPages: page > 0 ? {viewerId: page} : const <String, int>{},
  );
}
