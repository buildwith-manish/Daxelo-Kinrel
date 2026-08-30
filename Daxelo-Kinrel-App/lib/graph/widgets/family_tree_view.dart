// lib/graph/widgets/family_tree_view.dart
//
// DAXELO KINREL — Family Tree View (generation-locked hierarchy)
//
// Family Space: Graph ↔ Tree (↔ Map) — Implementation Prompt §5.
//
// The Tree view is the second renderer over the SAME family dataset as
// the Graph view. Differences vs. FamilyGraphEngineView:
//   - Layout: HierarchicalLayout (top-down, generation-locked rows)
//     instead of RadialLayout (ego-centric concentric rings).
//   - Edges: orthogonal connectors via TreePainter (no force sim).
//   - Expand/collapse: BranchCollapseNotifier (SAME provider the Graph
//     view uses — persisted via GraphLayoutState.expandedBranches).
//   - Cross-nav: shares graphFocusProvider with Graph + Map (focus on
//     a node from any view → all views know).
//
// Architecture invariants (§1 non-negotiable):
//   - One write path: Person + Relationship tables. NO TreeMember table.
//   - One cache family: familyTreeProvider (this view) + familyGraphProvider
//     (Graph view) — both invalidate together on Realtime changes.
//   - One focus state: graphFocusProvider (shared with Graph + Map).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/services/graph_layout_service.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show FlatGraphResult, familyGraphProvider, selectedNodeProvider;
import '../../features/family/presentation/providers/family_tree_provider.dart'
    show familyTreeProvider;
import '../../features/family/presentation/widgets/family_space_tab_bar.dart'
    show FamilySpaceTab, familySpaceTabProvider;
import '../engine/hierarchical_layout.dart';
import '../interaction/branch_collapse_state.dart' show branchCollapseProvider;
import '../interaction/graph_focus_state.dart' show graphFocusProvider;
import '../rendering/tree_painter.dart';
import '../rendering/tree_pdf_exporter.dart';

/// The size of a Tree node tile. Both layout + painter must agree on
/// this number so connectors terminate at the node edge.
///
/// v5.127: Changed from square (96×96) to a wider rounded-rectangle
/// (120×72, 5:3 aspect) to fit avatar + name side-by-side without
/// cramping. This is a Tree-view-only constant — the Graph view keeps
/// its circular nodes and own sizing.
const Size kTreeNodeSize = Size(120.0, 72.0);

/// v5.128: Layout result — positions + the set of secondary-spouse IDs
/// (so the painter can render their edges with dashed connectors per §2.3).
class _TreeLayoutResult {
  const _TreeLayoutResult({required this.positions, this.secondarySpouseIds = const {}});

  final Map<String, Offset> positions;
  final Set<String> secondarySpouseIds;
}

/// Computes the hierarchical layout for a family's tree data.
///
/// Watches `familyTreeProvider` for data changes and re-computes positions
/// synchronously (HierarchicalLayout is algebraic — no isolate needed
/// for typical family sizes; the engine header claims 30 FPS at 5,000
/// nodes).
final treeLayoutProvider =
    Provider.family<_TreeLayoutResult, String>((ref, familyId) {
  final treeAsync = ref.watch(familyTreeProvider(familyId));
  final tree = treeAsync.valueOrNull;
  if (tree == null || tree.persons.isEmpty) {
    return const _TreeLayoutResult(positions: {});
  }

  // Build GraphPerson list (HierarchicalLayout's input type).
  final graphPersons = <GraphPerson>[];
  String? viewerId;
  for (final p in tree.persons) {
    final id = (p['id'] ?? '').toString();
    final isViewer = (p['isViewer'] as bool?) ?? false;
    if (isViewer) viewerId = id;
    // v5.128 §2.4: parse birthDate for deterministic sibling ordering.
    // Falls back to null — the layout handles nulls by sorting after
    // non-nulls, with id-ascending as the final tiebreak.
    DateTime? birthDate;
    final rawDob = p['dateOfBirth'];
    if (rawDob is String && rawDob.isNotEmpty) {
      birthDate = DateTime.tryParse(rawDob);
    }
    graphPersons.add(GraphPerson(
      id: id,
      name: (p['name'] ?? '').toString(),
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as int?) ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      birthDate: birthDate,
    ));
  }

  // Build GraphRelationship list.
  final graphRels = <GraphRelationship>[];
  for (final r in tree.relationships) {
    graphRels.add(GraphRelationship(
      id: (r['id'] ?? '').toString(),
      fromPersonId: (r['fromPersonId'] ?? '').toString(),
      toPersonId: (r['toPersonId'] ?? '').toString(),
      relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
      // v5.129: parse labelAtoB so the layout engine can distinguish
      // sibling edges (labelAtoB='brother'/'sister') from parent-child
      // edges (labelAtoB='father'/'mother'/'son'/'daughter'). Both are
      // stored as relationshipKey='parent' in the DB due to the
      // relationship_fundamental_edge_check constraint — only labelAtoB
      // carries the semantic distinction.
      labelAtoB: (r['labelAtoB'] as String?) ?? (r['labelBtoA'] as String?),
    ));
  }

  // Pick the anchor — viewer if available, else the isAnchor-flagged person,
  // else the first person. (Mirrors the Graph view's viewer-first policy.)
  final anchorId = viewerId ??
      (graphPersons.where((p) => p.isAnchor).firstOrNull?.id) ??
      graphPersons.first.id;

  final layout = HierarchicalLayout(
    config: HierarchicalLayoutConfig(
      // v5.127: re-tuned for the new 120×72 rounded-rect node shape.
      siblingSpacing: 20.0,
      levelSpacing: 110.0,
      spouseGap: 8.0,
      padding: 60.0,
      nodeWidth: kTreeNodeSize.width,
      nodeHeight: kTreeNodeSize.height,
    ),
  );

  // v5.128 §2.3: the layout engine populates this set with the IDs of
  // all secondary spouses (index >= 1 in their partner's spouses list).
  // We thread it through to the painter for dashed-edge rendering.
  final secondarySpouseIds = <String>{};
  final result = layout.compute(
    persons: graphPersons,
    relationships: graphRels,
    anchorPersonId: anchorId,
    secondarySpouseIds: secondarySpouseIds,
  );
  return _TreeLayoutResult(
    positions: result.positions,
    secondarySpouseIds: secondarySpouseIds,
  );
});

// ═══════════════════════════════════════════════════════════════════════
// FAMILY TREE VIEW
// ═══════════════════════════════════════════════════════════════════════

/// The Tree view widget. Renders generations as horizontal rows.
///
/// State that survives tab switches (because the parent IndexedStack
/// keeps this widget built):
///   - Horizontal pan offset (via the internal TransformationController).
///   - Selected node (via the shared `selectedNodeProvider`).
///   - Focus state (via the shared `graphFocusProvider`).
class FamilyTreeView extends ConsumerStatefulWidget {
  const FamilyTreeView({
    super.key,
    required this.familyId,
    this.bottomChromeHeight = 0,
    this.topChromeHeight = 0,
  });

  final String familyId;
  final double bottomChromeHeight;
  final double topChromeHeight;

  @override
  ConsumerState<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends ConsumerState<FamilyTreeView> {
  final TransformationController _transformController =
      TransformationController();
  String? _lastFocusedId;
  bool _initialCenterDone = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(familyTreeProvider(widget.familyId));
    final layoutResult = ref.watch(treeLayoutProvider(widget.familyId));
    final positions = layoutResult.positions;
    final secondarySpouseIds = layoutResult.secondarySpouseIds;
    final collapseState = ref.watch(branchCollapseProvider);
    final focusState = ref.watch(graphFocusProvider);
    final selectedId = ref.watch(selectedNodeProvider);

    // Watch Realtime so the provider invalidates on Person/Relationship writes.
    ref.watch(familyGraphProvider(widget.familyId));

    // Auto-scroll to focused person when focus changes (cross-nav from Graph).
    final focusedId = focusState.focusedPersonId;
    if (focusedId != null &&
        focusedId != _lastFocusedId &&
        positions.containsKey(focusedId)) {
      _lastFocusedId = focusedId;
      // Defer to next frame so layout has settled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerOnPerson(focusedId, positions);
      });
    } else if (focusedId == null) {
      _lastFocusedId = null;
    }

    return treeAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load family tree.\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KinrelColors.textSecondaryDark,
              fontFamily: 'DMSans',
            ),
          ),
        ),
      ),
      data: (tree) {
        if (tree.persons.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.family_restroom,
                    color: KinrelColors.textSecondaryDark, size: 48),
                SizedBox(height: 12),
                Text(
                  'No family members yet.\nAdd your first member to see the tree.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: KinrelColors.textSecondaryDark,
                    fontFamily: 'DMSans',
                  ),
                ),
              ],
            ),
          );
        }

        // Initial centering: fit-to-view the anchor's immediate family
        // (2 generations above + below = ~5 rows). This is the key fix
        // for the "huge empty canvas" problem — instead of showing the
        // full 714-member tree at zoom=1.0 (where the user sees empty
        // space), we compute a focus set and fit it to the viewport.
        if (!_initialCenterDone && positions.isNotEmpty) {
          _initialCenterDone = true;
          final anchorId = tree.persons
                  .where((p) => p['isViewer'] == true)
                  .firstOrNull?['id'] as String? ??
              tree.persons
                  .where((p) => p['isAnchor'] == true)
                  .firstOrNull?['id'] as String?;
          if (anchorId != null && positions.containsKey(anchorId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitToFocusSet(anchorId, positions, tree.relationships);
            });
          }
        }

        final edges = _buildEdges(tree);
        final hiddenIds = collapseState.allHiddenMemberIds;
        final visiblePositions = Map<String, Offset>.from(positions)
          ..removeWhere((id, _) => hiddenIds.contains(id));

        // v5.130 §1: Compute generation labels for the left-edge column.
        // Groups positions by Y coordinate → one label per row.
        final generationLabels = _computeGenerationLabels(
          visiblePositions,
          tree.persons,
        );

        return Stack(
          children: [
            // The Tree canvas itself — fills the available area.
            _TreeCanvas(
              positions: visiblePositions,
              edges: edges,
              hiddenPersonIds: hiddenIds,
              secondarySpouseIds: secondarySpouseIds,
              focusedPersonId: focusState.focusedPersonId,
              selectedPersonId: selectedId,
              persons: tree.persons,
              transformController: _transformController,
              onTapNode: _onTapNode,
              onLongPressNode: _onLongPressNode,
            ),

            // v5.130 §1: Left-edge generation label column.
            // Fixed-width column on the left, showing "Generation +N / Label"
            // for each row. Scrolls vertically with the canvas (via transform).
            _GenerationLabelColumn(
              labels: generationLabels,
              transformController: _transformController,
            ),

            // v5.130 §2.3: Bottom control bar — Fit / Center / Expand All /
            // Collapse All / Levels.
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _TreeControlsBar(
                onFit: _fitToView,
                onCenter: _centerOnAnchor,
                onExpandAll: _expandAll,
                onCollapseAll: _collapseAll,
                onLevelsTap: () => _showLevelsMenu(context, generationLabels),
              ),
            ),

            // v5.126: "Export to PDF" FAB — bottom-right (above controls bar).
            Positioned(
              right: 16,
              bottom: (MediaQuery.of(context).padding.bottom + 80),
              child: _ExportPdfFab(
                familyId: widget.familyId,
                persons: tree.persons,
                relationships: tree.relationships,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Builds the deduplicated edge list expected by [TreePainter].
  List<({String fromId, String toId, String relationshipKey})> _buildEdges(
      FlatGraphResult tree) {
    final result = <({String fromId, String toId, String relationshipKey})>[];
    final seen = <String>{};
    for (final r in tree.relationships) {
      final from = (r['fromPersonId'] ?? '').toString();
      final to = (r['toPersonId'] ?? '').toString();
      if (from.isEmpty || to.isEmpty) continue;
      // v5.129: Use labelAtoB to determine the actual edge type.
      // The DB stores ALL non-spouse edges as relationshipKey='parent'
      // (due to the relationship_fundamental_edge_check constraint).
      // Only labelAtoB carries the semantic distinction:
      //   labelAtoB='brother'/'sister' → sibling (same-gen, horizontal connector)
      //   labelAtoB='father'/'mother'/'parent' → parent→child (vertical connector)
      //   relationshipKey='spouse' → spouse (horizontal connector)
      final label =
          ((r['labelAtoB'] as String?) ?? (r['labelBtoA'] as String?) ?? r['relationshipKey'] ?? 'unknown')
              .toString()
              .toLowerCase();
      final dbKey =
          (r['relationshipKey'] ?? 'unknown').toString().toLowerCase();

      // Classify: sibling, spouse, or parent/child.
      String edgeType;
      if (_kSiblingLabels.contains(label)) {
        edgeType = 'sibling';
      } else if (TreePainter.kSpouseKeys.contains(dbKey) ||
          TreePainter.kSpouseKeys.contains(label)) {
        edgeType = 'spouse';
      } else if (TreePainter.kParentKeys.contains(dbKey) ||
          TreePainter.kParentKeys.contains(label) ||
          TreePainter.kChildKeys.contains(label)) {
        edgeType = 'parent';
      } else {
        continue; // skip non-structural edges
      }

      final pairKey = [from, to]..sort();
      final canonical = '${pairKey[0]}|${pairKey[1]}';
      if (seen.contains(canonical)) continue;
      seen.add(canonical);
      result.add((fromId: from, toId: to, relationshipKey: edgeType));
    }
    return result;
  }

  /// v5.129: Labels that indicate a sibling edge (same-generation).
  static const Set<String> _kSiblingLabels = {
    'brother', 'sister', 'sibling',
    'elder_brother', 'elder_sister',
    'younger_brother', 'younger_sister',
    'step_brother', 'step_sister',
    'half_brother', 'half_sister',
  };

  void _onTapNode(String personId, Map<String, dynamic> person) {
    // Select the node (shared state with Graph view).
    ref.read(selectedNodeProvider.notifier).state = personId;

    // Focus on it (shared graphFocusProvider — also drives Map).
    final edges = _edgesForFocus();
    ref.read(graphFocusProvider.notifier).focus(
          personId: personId,
          personName: (person['name'] ?? 'Person').toString(),
          edges: edges,
          currentViewport: null,
        );
  }

  void _onLongPressNode(String personId, Map<String, dynamic> person) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (person['name'] ?? 'Person').toString(),
                      style: const TextStyle(
                        color: KinrelColors.textWhite,
                        fontFamily: 'DMSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: KinrelColors.textSecondaryDark),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_rounded,
                  color: KinrelColors.orange),
              title: const Text('View in Graph',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text(
                'Switch to the radial graph, centered here',
                style:
                    TextStyle(color: KinrelColors.textSecondaryDark, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _viewInGraph(personId, person);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Cross-nav handler: "View in Graph" from Tree.
  ///
  /// Sets the active Family Space tab to Graph and focuses on the
  /// tapped person via the shared `graphFocusProvider`. The Graph view's
  /// existing focus-watcher animates the camera to the target.
  void _viewInGraph(String personId, Map<String, dynamic> person) {
    // Switch the active tab (the parent IndexedStack swaps views).
    ref.read(familySpaceTabProvider.notifier).state = FamilySpaceTab.graph;

    // Focus on the target (Graph view's _onFocusPerson handler reacts).
    ref.read(graphFocusProvider.notifier).focus(
          personId: personId,
          personName: (person['name'] ?? 'Person').toString(),
          edges: _edgesForFocus(),
          currentViewport: null,
        );
    ref.read(selectedNodeProvider.notifier).state = personId;
  }

  List<({String fromId, String toId})> _edgesForFocus() {
    final tree = ref.read(familyTreeProvider(widget.familyId)).valueOrNull;
    if (tree == null) return const [];
    return [
      for (final r in tree.relationships)
        (
          fromId: (r['fromPersonId'] ?? '').toString(),
          toId: (r['toPersonId'] ?? '').toString(),
        ),
    ];
  }

  /// Centers the canvas on [personId] by setting the transform matrix.
  /// Auto-expands any collapsed ancestor branches along the path so the
  /// target is actually visible (§5 "scrollToAndHighlight").
  void _centerOnPerson(String personId, Map<String, Offset> positions) {
    if (!positions.containsKey(personId)) return;
    final target = positions[personId]!;

    // Auto-expand collapsed branches containing this person.
    // (BranchCollapseNotifier.expandBranch is idempotent.)
    ref.read(branchCollapseProvider.notifier).expandBranch(personId);

    // Compute the translation so the target lands at viewport center.
    // (Viewport size is determined by the InteractiveViewer's parent
    // constraints — we read it from MediaQuery via context.)
    final mq = MediaQuery.of(context);
    final viewportWidth = mq.size.width;
    final viewportHeight = mq.size.height;

    final dx = (viewportWidth / 2) - target.dx;
    final dy = (viewportHeight / 2) - target.dy;
    // ignore: deprecated_member_use
    // (translate is deprecated in this Flutter version but the
    //  replacement `translateByDouble` is not available in our pinned
    //  SDK — see https://github.com/flutter/flutter/issues/156012.)
    _transformController.value = Matrix4.identity()..translate(dx, dy);
  }

  /// v5.131: Fit-to-view the anchor's immediate family (focus set).
  ///
  /// This is the key fix for the "huge empty canvas" problem. Instead of
  /// centering on the anchor at zoom=1.0 (which shows a tiny portion of
  /// a massive canvas), we:
  ///   1. Compute a BFS from the anchor to find nodes within 2 hops
  ///      (parents, siblings, spouse, children, grandchildren).
  ///   2. Compute the bounding box of ONLY those nodes.
  ///   3. Fit that bounding box into the viewport with a comfortable
  ///      margin (40dp on all sides).
  ///   4. Center the result.
  ///
  /// The user immediately sees their immediate family on open — no
  /// empty space, no hunting. They can use Expand All / Levels to
  /// navigate to distant branches.
  void _fitToFocusSet(
    String anchorId,
    Map<String, Offset> positions,
    List<Map<String, dynamic>> relationships,
  ) {
    if (positions.isEmpty || !positions.containsKey(anchorId)) return;

    // ── Step 1: BFS from anchor, depth ≤ 2 ──
    // Build adjacency from the raw relationship data.
    final adjacency = <String, Set<String>>{};
    for (final r in relationships) {
      final from = (r['fromPersonId'] ?? '').toString();
      final to = (r['toPersonId'] ?? '').toString();
      if (from.isEmpty || to.isEmpty) continue;
      adjacency.putIfAbsent(from, () => <String>{}).add(to);
      adjacency.putIfAbsent(to, () => <String>{}).add(from);
    }

    // BFS: anchor → depth 0, neighbors → depth 1, their neighbors → depth 2
    final focusSet = <String>{anchorId};
    final queue = <String>[anchorId];
    final visited = <String>{anchorId};
    for (var depth = 0; depth < 2 && queue.isNotEmpty; depth++) {
      final nextQueue = <String>[];
      for (final node in queue) {
        final neighbors = adjacency[node] ?? const {};
        for (final n in neighbors) {
          if (!visited.contains(n) && positions.containsKey(n)) {
            visited.add(n);
            focusSet.add(n);
            nextQueue.add(n);
          }
        }
      }
      queue
        ..clear()
        ..addAll(nextQueue);
    }

    // ── Step 2: Bounding box of focus set ──
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final id in focusSet) {
      final pos = positions[id];
      if (pos == null) continue;
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    if (minX == double.infinity) return;

    // Add node size padding so cards aren't cut off at edges.
    minX -= kTreeNodeSize.width / 2;
    maxX += kTreeNodeSize.width / 2;
    minY -= kTreeNodeSize.height / 2;
    maxY += kTreeNodeSize.height / 2;

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    if (contentW <= 0 || contentH <= 0) return;

    // ── Step 3: Fit to viewport ──
    final mq = MediaQuery.of(context);
    final viewportW = mq.size.width - 100; // minus label column + margins
    final viewportH = mq.size.height - 120; // minus controls bar + margins

    final scaleX = viewportW / contentW;
    final scaleY = viewportH / contentH;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.3, 2.5);

    // ── Step 4: Center ──
    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;
    // After scaling, the content center should land at viewport center.
    // screenX = translateX + scale * contentCenterX = viewportW/2 + 50 (label col offset)
    // screenY = translateY + scale * contentCenterY = viewportH/2 + 60 (header offset)
    final dx = (mq.size.width / 2) - (contentCenterX * scale);
    final dy = (mq.size.height / 2) - (contentCenterY * scale);

    _transformController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // v5.130 §2.3: Control bar handlers
  // ═══════════════════════════════════════════════════════════════════════

  /// Fit: zoom/pan so every currently-expanded node is visible.
  /// v5.131: Uses the same fit-to-focus-set logic as initial load, but
  /// fits ALL visible nodes (not just the focus set) so the user can
  /// see the full tree after expanding branches.
  void _fitToView() {
    final layoutResult = ref.read(treeLayoutProvider(widget.familyId));
    final positions = layoutResult.positions;
    if (positions.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    // Add node size padding.
    minX -= kTreeNodeSize.width / 2;
    maxX += kTreeNodeSize.width / 2;
    minY -= kTreeNodeSize.height / 2;
    maxY += kTreeNodeSize.height / 2;

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    if (contentW <= 0 || contentH <= 0) return;

    final mq = MediaQuery.of(context);
    // More generous margins for manual Fit (user explicitly asked to see everything).
    final viewportW = mq.size.width - 80;
    final viewportH = mq.size.height - 160;

    final scaleX = viewportW / contentW;
    final scaleY = viewportH / contentH;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.3, 2.5);

    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;
    final dx = (mq.size.width / 2) - (contentCenterX * scale);
    final dy = (mq.size.height / 2) - (contentCenterY * scale);

    _transformController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  /// Center: re-center on the anchor without changing zoom.
  void _centerOnAnchor() {
    final tree = ref.read(familyTreeProvider(widget.familyId)).valueOrNull;
    if (tree == null) return;
    final anchorId = tree.persons
            .where((p) => p['isViewer'] == true)
            .firstOrNull?['id'] as String? ??
        tree.persons
            .where((p) => p['isAnchor'] == true)
            .firstOrNull?['id'] as String?;
    if (anchorId == null) return;
    final positions = ref.read(treeLayoutProvider(widget.familyId)).positions;
    _centerOnPerson(anchorId, positions);
  }

  /// Expand All: bulk-expand every collapsed branch.
  void _expandAll() {
    final tree = ref.read(familyTreeProvider(widget.familyId)).valueOrNull;
    if (tree == null) return;
    final notifier = ref.read(branchCollapseProvider.notifier);
    for (final p in tree.persons) {
      final id = p['id'] as String?;
      if (id != null) notifier.expandBranch(id);
    }
  }

  /// Collapse All: bulk-collapse every expanded branch.
  void _collapseAll() {
    ref.read(branchCollapseProvider.notifier).clearAll();
  }

  /// Levels: jump menu — tap a generation label to animate the camera
  /// to that row, horizontally centered on the anchor's column.
  void _showLevelsMenu(BuildContext context, List<_GenerationLabel> labels) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Jump to Generation',
                style: TextStyle(
                  color: KinrelColors.textWhite,
                  fontFamily: 'DMSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(color: Color(0x22FFFFFF)),
            ...labels.map((label) => ListTile(
                  leading: Text(
                    label.relativeGen >= 0
                        ? '+${label.relativeGen}'
                        : '${label.relativeGen}',
                    style: TextStyle(
                      color: KinrelColors.orange,
                      fontFamily: 'DMSans',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  title: Text(
                    label.name,
                    style: const TextStyle(
                      color: KinrelColors.textWhite,
                      fontFamily: 'DMSans',
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final mq = MediaQuery.of(context);
                    final viewportH = mq.size.height;
                    final currentScale =
                        _transformController.value.entry(0, 0);
                    final dy = (viewportH / 2) - (label.y * currentScale);
                    final currentTx =
                        _transformController.value.entry(0, 3);
                    _transformController.value = Matrix4.identity()
                      ..translate(currentTx, dy)
                      ..scale(currentScale);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TREE CANVAS — the actual paint surface
//
// v5.128 §3.2: Viewport culling. At 10,000+ nodes, rendering one Flutter
// widget per person janks regardless of correct layout math. This widget
// listens to the TransformationController (pan/zoom) and only builds
// widgets whose position falls inside the current visible viewport rect,
// expanded by a margin to avoid pop-in during fast scrolls.
//
// The connectors (TreePainter) still paint ALL edges — painting is cheap
// (one Canvas draw call per edge, batched by the GPU). It's the per-node
// Widget build + layout pass that's expensive at scale, so only that is
// culled.
// ═══════════════════════════════════════════════════════════════════════

class _TreeCanvas extends StatefulWidget {
  const _TreeCanvas({
    required this.positions,
    required this.edges,
    required this.hiddenPersonIds,
    required this.secondarySpouseIds,
    required this.focusedPersonId,
    required this.selectedPersonId,
    required this.persons,
    required this.transformController,
    required this.onTapNode,
    required this.onLongPressNode,
  });

  final Map<String, Offset> positions;
  final List<({String fromId, String toId, String relationshipKey})> edges;
  final Set<String> hiddenPersonIds;
  final Set<String> secondarySpouseIds;
  final String? focusedPersonId;
  final String? selectedPersonId;
  final List<Map<String, dynamic>> persons;
  final TransformationController transformController;
  final void Function(String personId, Map<String, dynamic> person) onTapNode;
  final void Function(String personId, Map<String, dynamic> person)
      onLongPressNode;

  @override
  State<_TreeCanvas> createState() => _TreeCanvasState();
}

class _TreeCanvasState extends State<_TreeCanvas> {
  /// v5.128 §3.2: Visible viewport rect in CANVAS coordinates (i.e.
  /// already inverse-transformed from screen space). Updated on every
  /// pan/zoom via the TransformationController listener.
  Rect? _visibleRect;

  @override
  void initState() {
    super.initState();
    widget.transformController.addListener(_onTransformChanged);
    // Initial computation — defer to next frame when LayoutBuilder has
    // the viewport size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTransformChanged());
  }

  @override
  void didUpdateWidget(_TreeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformController != widget.transformController) {
      oldWidget.transformController.removeListener(_onTransformChanged);
      widget.transformController.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.transformController.removeListener(_onTransformChanged);
    super.dispose();
  }

  /// Recompute the visible viewport rect in canvas coordinates.
  void _onTransformChanged() {
    if (!mounted) return;
    final mq = MediaQuery.of(context);
    final viewportSize = mq.size;

    // The TransformationController's matrix maps canvas → screen.
    // We need the inverse: screen → canvas. Clamp the inverse to identity
    // if the matrix is singular (e.g. scale 0, which InteractiveViewer
    // never actually reaches).
    final matrix = widget.transformController.value;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      setState(() => _visibleRect = null);
      return;
    }

    // Screen viewport (0,0)→(viewportSize) → canvas via inverse.
    final screenCorners = [
      Offset.zero,
      Offset(viewportSize.width, 0),
      Offset(0, viewportSize.height),
      Offset(viewportSize.width, viewportSize.height),
    ];
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final corner in screenCorners) {
      final canvas = MatrixUtils.transformPoint(inverse, corner);
      if (canvas.dx < minX) minX = canvas.dx;
      if (canvas.dy < minY) minY = canvas.dy;
      if (canvas.dx > maxX) maxX = canvas.dx;
      if (canvas.dy > maxY) maxY = canvas.dy;
    }
    // Expand by a margin (2× node size) to avoid pop-in during fast scrolls.
    final margin = kTreeNodeSize.longestSide * 2;
    final newRect = Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );
    if (_visibleRect != newRect) {
      setState(() => _visibleRect = newRect);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.positions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Compute canvas bounds.
    double maxX = 0, maxY = 0;
    for (final pos in widget.positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    final canvasWidth = maxX + kTreeNodeSize.width + 80;
    final canvasHeight = maxY + kTreeNodeSize.height + 80;

    // v5.128 §3.2: viewport culling — only build node widgets whose
    // position falls inside the visible rect. The painter still paints
    // ALL edges (cheap), only the widget build/layout is culled.
    final visibleRect = _visibleRect;

    return InteractiveViewer(
      transformationController: widget.transformController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.3,
      maxScale: 2.5,
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer 1: connectors (painter) — paints ALL edges.
            CustomPaint(
              size: Size(canvasWidth, canvasHeight),
              painter: TreePainter(
                positions: widget.positions,
                edges: widget.edges,
                hiddenPersonIds: widget.hiddenPersonIds,
                secondarySpouseIds: widget.secondarySpouseIds,
                focusedPersonId: widget.focusedPersonId,
                nodeSize: kTreeNodeSize,
              ),
            ),
            // Layer 2: positioned node widgets — culled to viewport.
            // v5.128 §3.2: at 10,000 nodes, building one widget per
            // person janks. Only build widgets inside the visible rect.
            for (final person in widget.persons)
              if (widget.positions.containsKey(person['id']))
                _maybeBuildNode(person, visibleRect) ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  /// v5.128 §3.2: Build the node widget only if its position falls inside
  /// the visible viewport rect (or if no rect is computed yet — fall back
  /// to building everything to avoid an empty canvas on first paint).
  Widget? _maybeBuildNode(Map<String, dynamic> person, Rect? visibleRect) {
    final id = person['id'] as String;
    final pos = widget.positions[id]!;
    if (visibleRect != null && !visibleRect.contains(pos)) {
      // Cull — outside viewport. The painter still draws the connector
      // endpoint, but no widget is built. This is what scales to 10k+.
      return null;
    }
    return _buildNode(person);
  }

  Widget _buildNode(Map<String, dynamic> person) {
    final id = person['id'] as String;
    final pos = widget.positions[id]!;
    final name = (person['name'] as String?) ?? '';
    final photoUrl = person['avatarUrl'] as String?;
    final isDeceased = (person['isDeceased'] as bool?) ?? false;
    final isViewer = (person['isViewer'] as bool?) ?? false;
    final isAnchor = (person['isAnchor'] as bool?) ?? false;
    final restricted = (person['restricted'] as bool?) ?? false;
    final gender = person['gender'] as String?;

    final isSelected = widget.selectedPersonId == id;
    final isFocused = widget.focusedPersonId == id;

    return Positioned(
      left: pos.dx - kTreeNodeSize.width / 2,
      top: pos.dy - kTreeNodeSize.height / 2,
      width: kTreeNodeSize.width,
      height: kTreeNodeSize.height,
      child: GestureDetector(
        onTap: () => widget.onTapNode(id, person),
        onLongPress: () => widget.onLongPressNode(id, person),
        child: _TreeNode(
          name: name,
          photoUrl: photoUrl,
          isDeceased: isDeceased,
          isViewer: isViewer,
          isAnchor: isAnchor,
          restricted: restricted,
          gender: gender,
          isSelected: isSelected,
          isFocused: isFocused,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TREE NODE
// ═══════════════════════════════════════════════════════════════════════

class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.name,
    required this.photoUrl,
    required this.isDeceased,
    required this.isViewer,
    required this.isAnchor,
    required this.restricted,
    required this.gender,
    required this.isSelected,
    required this.isFocused,
  });

  final String name;
  final String? photoUrl;
  final bool isDeceased;
  final bool isViewer;
  final bool isAnchor;
  final bool restricted;
  final String? gender;
  final bool isSelected;
  final bool isFocused;

  // v5.127: Tree-view-only node shape constants.
  //
  // The card is a rounded rectangle (8dp corner radius, 5:3 aspect:
  // 120×72 = the kTreeNodeSize). Inside, the avatar is a SMALLER
  // circle (40dp diameter) inset at the left, vertically centered —
  // like a contact card. The name + deceased indicator sit to the
  // right of the avatar, also vertically centered.
  //
  // All other visual treatments (color logic, focus pulse, deceased
  // dot, restricted placeholder) are byte-for-byte identical to the
  // previous circular design — only the container shape changed.
  static const double _cardCornerRadius = 8.0;
  static const double _avatarDiameter = 40.0;
  static const double _avatarInset = 6.0; // padding around avatar
  static const double _nameAvatarGap = 8.0;

  @override
  Widget build(BuildContext context) {
    // v5.127: identical color logic to the previous circular design —
    // only the SHAPE of the container applying it changed (circle →
    // rounded rectangle). Border width, focus box-shadow, color
    // selection all preserved verbatim.
    final ringColor = isFocused
        ? KinrelColors.orange
        : isSelected
            ? KinrelColors.orange.withValues(alpha: 0.6)
            : isViewer
                ? const Color(0xFFE8612A)
                : isDeceased
                    ? const Color(0xFF7A6F8A)
                    : const Color(0x44FFFFFF);

    final borderWidth = isFocused ? 3 : (isSelected || isViewer ? 2 : 1);

    return Container(
      width: kTreeNodeSize.width,
      height: kTreeNodeSize.height,
      // v5.127: rounded rectangle replaces the previous circular
      // BoxDecoration. 8dp corner radius per the spec; 2-3px border
      // stroke in the role color (the same color the circular ring
      // used).
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(_cardCornerRadius),
        border: Border.all(
          color: ringColor,
          width: borderWidth.toDouble(),
        ),
        // v5.127: focus box-shadow preserved verbatim from the
        // previous circular design (same color, blur, spread).
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: KinrelColors.orange.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      // v5.127: Row layout — avatar left, name right, both vertically
      // centered. (Previously a Column with avatar on top, name below.)
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _avatarInset,
          vertical: _avatarInset,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar — stays CIRCULAR, inset within the rectangular
            // card (not stretched/cropped to fill corners). Same
            // ClipOval + Image.network / placeholder logic as before.
            Container(
              width: _avatarDiameter,
              height: _avatarDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // v5.127: keep the avatar's own ring (subtle, 1.5px)
                // so the avatar still reads as a discrete element
                // inside the card. Color matches the card border so
                // the two feel cohesive.
                border: Border.all(
                  color: ringColor.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: restricted ||
                        photoUrl == null ||
                        photoUrl!.isEmpty
                    ? _placeholderAvatar()
                    : Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderAvatar(),
                      ),
              ),
            ),
            const SizedBox(width: _nameAvatarGap),
            // Name + deceased indicator — vertically stacked to the
            // right of the avatar. Same text style, color, weight,
            // truncation as before. Width bounded by remaining card
            // width so long names truncate with ellipsis.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    restricted ? 'Restricted' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: restricted
                          ? KinrelColors.textSecondaryDark
                              .withValues(alpha: 0.5)
                          : KinrelColors.textWhite,
                      fontSize: 11,
                      fontFamily: 'DMSans',
                      fontWeight: isViewer || isAnchor
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  // Deceased indicator (small dot to the LEFT of the
                  // years line — same color/size as before, just
                  // repositioned inside the horizontal layout).
                  if (isDeceased)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(width: 2),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF7A6F8A),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(width: 4, height: 4),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // v5.127: identical placeholder avatar to the previous design —
  // female → #7A4F5F, male/other → #4F5F7A, with the initial letter
  // centered. Only the diameter changed (was 56, now 40) to fit
  // inside the smaller circular avatar inset.
  Widget _placeholderAvatar() {
    final isFemale = gender?.toLowerCase() == 'female';
    return Container(
      color: isFemale ? const Color(0xFF7A4F5F) : const Color(0xFF4F5F7A),
      child: Center(
        child: Text(
          restricted
              ? '?'
              : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
          // v5.127: font size reduced from 18 → 14 to fit the smaller
          // 40dp avatar (was 56dp). Same font, weight, color as before.
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'DMSans',
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v5.130 §1: GENERATION LABEL COLUMN
// ═══════════════════════════════════════════════════════════════════════

/// A generation label for one row: the relative generation number and
/// its plain-language name relative to the anchor.
class _GenerationLabel {
  const _GenerationLabel({
    required this.relativeGen,
    required this.y,
    required this.name,
  });

  /// 0 = anchor's generation, -1 = parents, +1 = children, etc.
  final int relativeGen;

  /// The Y coordinate of this row in canvas space.
  final double y;

  /// Plain-language name: "You & Siblings", "Parents", "Grandparents", etc.
  final String name;
}

/// Computes generation labels from the layout positions.
///
/// Groups positions by Y coordinate (clustering within 1pt = same row),
/// then assigns each row a relative generation number based on its
/// distance from the anchor's row.
List<_GenerationLabel> _computeGenerationLabels(
  Map<String, Offset> positions,
  List<Map<String, dynamic>> persons,
) {
  if (positions.isEmpty) return const [];

  // Collect unique Y values (clustered within 1pt).
  final rowYs = <double>[];
  for (final pos in positions.values) {
    if (rowYs.isEmpty || (pos.dy - rowYs.last).abs() > 1.0) {
      rowYs.add(pos.dy);
    }
  }
  rowYs.sort();

  // Find the anchor's Y (viewer or isAnchor-flagged person).
  final anchorPerson = persons
          .where((p) => p['isViewer'] == true)
          .firstOrNull ??
      persons.where((p) => p['isAnchor'] == true).firstOrNull;
  final anchorId = anchorPerson?['id'] as String?;
  final anchorY = anchorId != null ? positions[anchorId]?.dy : null;

  // If no anchor found, use the middle row.
  final anchorRowIdx = anchorY != null
      ? rowYs.indexWhere((y) => (y - anchorY).abs() < 1.0)
      : rowYs.length ~/ 2;
  final effectiveAnchorIdx =
      anchorRowIdx >= 0 ? anchorRowIdx : rowYs.length ~/ 2;

  // Build labels.
  final labels = <_GenerationLabel>[];
  for (var i = 0; i < rowYs.length; i++) {
    final relGen = i - effectiveAnchorIdx;
    labels.add(_GenerationLabel(
      relativeGen: relGen,
      y: rowYs[i],
      name: _generationName(relGen),
    ));
  }
  return labels;
}

/// Returns the plain-language name for a relative generation.
/// 0 = "You & Siblings", -1 = "Parents", -2 = "Grandparents", etc.
/// +1 = "Children", +2 = "Grandchildren", etc.
String _generationName(int relGen) {
  switch (relGen) {
    case 0:
      return 'You & Siblings';
    case -1:
      return 'Parents';
    case -2:
      return 'Grandparents';
    case -3:
      return 'Great Grandparents';
    case -4:
      return 'Great Great Grandparents';
    case 1:
      return 'Children';
    case 2:
      return 'Grandchildren';
    case 3:
      return 'Great Grandchildren';
    case 4:
      return 'Great Great Grandchildren';
    default:
      return relGen < 0
          ? 'Generation $relGen'
          : 'Generation +$relGen';
  }
}

/// Left-edge label column. Fixed width, scrolls with the canvas.
///
/// Renders "Generation +N / Label" text at each row's Y position,
/// transformed by the same TransformationController as the canvas so
/// it pans/zooms in sync.
class _GenerationLabelColumn extends StatefulWidget {
  const _GenerationLabelColumn({
    required this.labels,
    required this.transformController,
  });

  final List<_GenerationLabel> labels;
  final TransformationController transformController;

  @override
  State<_GenerationLabelColumn> createState() => _GenerationLabelColumnState();
}

class _GenerationLabelColumnState extends State<_GenerationLabelColumn> {
  @override
  void initState() {
    super.initState();
    widget.transformController.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(_GenerationLabelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformController != widget.transformController) {
      oldWidget.transformController.removeListener(_onTransform);
      widget.transformController.addListener(_onTransform);
    }
  }

  @override
  void dispose() {
    widget.transformController.removeListener(_onTransform);
    super.dispose();
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.labels.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final viewportHeight = mq.size.height;

    // Transform: canvas Y → screen Y.
    // The transformController maps canvas → screen, so:
    //   screenY = transform(canvasY)
    // PDF/Flutter Y goes down, so the transform is:
    //   screenY = translateY + scale * canvasY
    // (where translateY is the Y component of the matrix's translation,
    // and scale is the uniform scale factor.)
    final matrix = widget.transformController.value;
    final scaleX = matrix.entry(0, 0);
    final translateY = matrix.entry(1, 3);

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 100,
      child: ClipRect(
        child: CustomPaint(
          size: Size(100, viewportHeight),
          painter: _GenerationLabelPainter(
            labels: widget.labels,
            scaleX: scaleX,
            translateY: translateY,
            viewportHeight: viewportHeight,
          ),
        ),
      ),
    );
  }
}

/// Painter for the generation label column. Draws text labels at each
/// row's screen-space Y position.
class _GenerationLabelPainter extends CustomPainter {
  _GenerationLabelPainter({
    required this.labels,
    required this.scaleX,
    required this.translateY,
    required this.viewportHeight,
  });

  final List<_GenerationLabel> labels;
  final double scaleX;
  final double translateY;
  final double viewportHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent dark background for the label column.
    final bgPaint = Paint()..color = const Color(0xCC191B2C);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw each label at its screen-space Y.
    for (final label in labels) {
      // Convert canvas Y to screen Y:
      //   screenY = translateY + scaleX * canvasY
      // (scaleX = scaleY because InteractiveViewer uses uniform scale.)
      final screenY = translateY + scaleX * label.y;

      // Skip if outside viewport.
      if (screenY < -20 || screenY > viewportHeight + 20) continue;

      // Draw the generation number (smaller, orange).
      final genText = label.relativeGen >= 0
          ? 'Gen +${label.relativeGen}'
          : 'Gen ${label.relativeGen}';
      final genPainter = TextPainter(
        text: TextSpan(
          text: genText,
          style: const TextStyle(
            color: KinrelColors.orange,
            fontSize: 9,
            fontFamily: 'DMSans',
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      genPainter.paint(canvas, Offset(5, screenY - 18));

      // Draw the name (smaller, dim white).
      final namePainter = TextPainter(
        text: TextSpan(
          text: label.name,
          style: const TextStyle(
            color: KinrelColors.textSecondaryDark,
            fontSize: 8,
            fontFamily: 'DMSans',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      namePainter.paint(canvas, Offset(5, screenY - 6));
    }
  }

  @override
  bool shouldRepaint(covariant _GenerationLabelPainter oldDelegate) {
    return oldDelegate.labels != labels ||
        oldDelegate.scaleX != scaleX ||
        oldDelegate.translateY != translateY;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v5.130 §2.3: TREE CONTROLS BAR
// ═══════════════════════════════════════════════════════════════════════

/// Bottom control bar with 5 buttons: Fit, Center, Expand All, Collapse All,
/// Levels. Matches the reference screenshot's bottom bar layout.
class _TreeControlsBar extends StatelessWidget {
  const _TreeControlsBar({
    required this.onFit,
    required this.onCenter,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onLevelsTap,
  });

  final VoidCallback onFit;
  final VoidCallback onCenter;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final VoidCallback onLevelsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.fit_screen_outlined,
            label: 'Fit',
            onTap: onFit,
          ),
          _ControlButton(
            icon: Icons.center_focus_strong_outlined,
            label: 'Center',
            onTap: onCenter,
          ),
          _ControlButton(
            icon: Icons.unfold_more_outlined,
            label: 'Expand',
            onTap: onExpandAll,
          ),
          _ControlButton(
            icon: Icons.unfold_less_outlined,
            label: 'Collapse',
            onTap: onCollapseAll,
          ),
          _ControlButton(
            icon: Icons.layers_outlined,
            label: 'Levels',
            onTap: onLevelsTap,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: KinrelColors.orange),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: KinrelColors.textSecondaryDark,
              fontSize: 9,
              fontFamily: 'DMSans',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v5.126: EXPORT-TO-PDF FAB
// ═══════════════════════════════════════════════════════════════════════

/// Floating action button that exports the current family tree to a
/// vector PDF (paginated by generation row).
///
/// Pipeline:
///   1. Convert tree.persons (List<Map<String, dynamic>>) → List<GraphPerson>
///   2. Convert tree.relationships → List<GraphRelationship>
///   3. Call TreePdfExporter.export() → Uint8List
///   4. Hand the bytes to Printing.sharePdf() (native platform share sheet)
///
/// The exporter RE-RUNS HierarchicalLayout + TreePainter against a
/// PdfCanvas — it does NOT screenshot the phone screen. So the PDF is:
///   - Vector (pixel-crisp at any zoom)
///   - Paginated by generation row
///   - Always shows the WHOLE tree (not just the visible subset)
class _ExportPdfFab extends StatefulWidget {
  const _ExportPdfFab({
    required this.familyId,
    required this.persons,
    required this.relationships,
  });

  final String familyId;
  final List<Map<String, dynamic>> persons;
  final List<Map<String, dynamic>> relationships;

  @override
  State<_ExportPdfFab> createState() => _ExportPdfFabState();
}

class _ExportPdfFabState extends State<_ExportPdfFab> {
  bool _isExporting = false;

  Future<void> _export() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      // Convert the tree data to the typed objects the exporter expects.
      final graphPersons = <GraphPerson>[];
      String? viewerId;
      for (final p in widget.persons) {
        final id = (p['id'] ?? '').toString();
        if ((p['isViewer'] as bool?) ?? false) viewerId = id;
        graphPersons.add(GraphPerson(
          id: id,
          name: (p['name'] ?? '').toString(),
          gender: p['gender'] as String?,
          generationIndex: (p['generationIndex'] as int?) ?? 0,
          isAnchor: (p['isAnchor'] as bool?) ?? false,
          photoUrl: p['photoUrl'] as String?,
          isDeceased: (p['isDeceased'] as bool?) ?? false,
        ));
      }

      final graphRels = <GraphRelationship>[];
      for (final r in widget.relationships) {
        graphRels.add(GraphRelationship(
          id: (r['id'] ?? '').toString(),
          fromPersonId: (r['fromPersonId'] ?? '').toString(),
          toPersonId: (r['toPersonId'] ?? '').toString(),
          relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
        ));
      }

      // Run the export (async — pdf.save() returns a Future).
      // We use a await Future.delayed(Duration.zero) to let the
      // "Exporting..." spinner paint before the (possibly slow)
      // layout + PDF generation runs on the UI isolate.
      await Future.delayed(Duration.zero);

      final exporter = TreePdfExporter();
      final bytes = await exporter.export(
        persons: graphPersons,
        relationships: graphRels,
        anchorPersonId: viewerId,
        familyName: 'Kinrel Family',
      );

      if (!mounted) return;

      // Hand the bytes to the platform share sheet.
      // filename: familyId-pageroots-TIMESTAMP.pdf so each export is unique.
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'kinrel-tree-${widget.familyId.substring(0, 8)}.pdf',
        subject: 'Kinrel Family Tree',
      );
    } catch (e, st) {
      debugPrint('[ExportPdf] error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: KinrelColors.darkCard,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'tree_export_pdf_${widget.familyId}',
      backgroundColor: KinrelColors.darkCard,
      foregroundColor: KinrelColors.orange,
      elevation: 4,
      onPressed: _isExporting ? null : _export,
      tooltip: 'Export to PDF',
      child: _isExporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: KinrelColors.orange,
              ),
            )
          : const Icon(Icons.picture_as_pdf_outlined, size: 20),
    );
  }
}
