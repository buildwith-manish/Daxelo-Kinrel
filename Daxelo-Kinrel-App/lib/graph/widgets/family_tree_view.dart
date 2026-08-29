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

/// The size of a Tree node tile (avatar + name). Both layout + painter
/// must agree on this number so connectors terminate at the node edge.
const Size kTreeNodeSize = Size(96.0, 96.0);

/// Computes the hierarchical layout for a family's tree data.
///
/// Watches `familyTreeProvider` for data changes and re-computes positions
/// synchronously (HierarchicalLayout is algebraic — no isolate needed
/// for typical family sizes; the engine header claims 30 FPS at 5,000
/// nodes).
final treeLayoutProvider =
    Provider.family<Map<String, Offset>, String>((ref, familyId) {
  final treeAsync = ref.watch(familyTreeProvider(familyId));
  final tree = treeAsync.valueOrNull;
  if (tree == null || tree.persons.isEmpty) return const {};

  // Build GraphPerson list (HierarchicalLayout's input type).
  final graphPersons = <GraphPerson>[];
  String? viewerId;
  for (final p in tree.persons) {
    final id = (p['id'] ?? '').toString();
    final isViewer = (p['isViewer'] as bool?) ?? false;
    if (isViewer) viewerId = id;
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

  // Build GraphRelationship list.
  final graphRels = <GraphRelationship>[];
  for (final r in tree.relationships) {
    graphRels.add(GraphRelationship(
      id: (r['id'] ?? '').toString(),
      fromPersonId: (r['fromPersonId'] ?? '').toString(),
      toPersonId: (r['toPersonId'] ?? '').toString(),
      relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
    ));
  }

  // Pick the anchor — viewer if available, else the isAnchor-flagged person,
  // else the first person. (Mirrors the Graph view's viewer-first policy.)
  final anchorId = viewerId ??
      (graphPersons.where((p) => p.isAnchor).firstOrNull?.id) ??
      graphPersons.first.id;

  final layout = HierarchicalLayout(
    config: HierarchicalLayoutConfig(
      siblingSpacing: 110.0,
      levelSpacing: 170.0,
      spouseGap: 28.0,
      padding: 80.0,
      nodeWidth: kTreeNodeSize.width,
      nodeHeight: kTreeNodeSize.height,
    ),
  );

  final result = layout.compute(
    persons: graphPersons,
    relationships: graphRels,
    anchorPersonId: anchorId,
  );
  return result.positions;
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
    final positions = ref.watch(treeLayoutProvider(widget.familyId));
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

        // Initial centering: scroll to the anchor/viewer on first paint.
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
              _centerOnPerson(anchorId, positions);
            });
          }
        }

        final edges = _buildEdges(tree);
        final hiddenIds = collapseState.allHiddenMemberIds;
        final visiblePositions = Map<String, Offset>.from(positions)
          ..removeWhere((id, _) => hiddenIds.contains(id));

        return Stack(
          children: [
            // The Tree canvas itself — fills the available area.
            _TreeCanvas(
              positions: visiblePositions,
              edges: edges,
              hiddenPersonIds: hiddenIds,
              focusedPersonId: focusState.focusedPersonId,
              selectedPersonId: selectedId,
              persons: tree.persons,
              transformController: _transformController,
              onTapNode: _onTapNode,
              onLongPressNode: _onLongPressNode,
            ),

            // v5.126: "Export to PDF" FAB — bottom-right.
            // Generates a vector PDF by re-running HierarchicalLayout +
            // TreePainter against a PdfCanvas. Paginated by generation
            // row. Pixel-crisp at any zoom (no rasterization).
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
      final key = (r['relationshipKey'] ?? 'unknown').toString().toLowerCase();
      // Only draw structural-lineage edges in Tree. Skip sibling/uncle/etc.
      if (!TreePainter.kSpouseKeys.contains(key) &&
          !TreePainter.kParentKeys.contains(key) &&
          !TreePainter.kChildKeys.contains(key)) {
        continue;
      }
      final pairKey = [from, to]..sort();
      final canonical = '${pairKey[0]}|${pairKey[1]}';
      if (seen.contains(canonical)) continue;
      seen.add(canonical);
      result.add((fromId: from, toId: to, relationshipKey: key));
    }
    return result;
  }

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
}

// ═══════════════════════════════════════════════════════════════════════
// TREE CANVAS — the actual paint surface
// ═══════════════════════════════════════════════════════════════════════

class _TreeCanvas extends StatelessWidget {
  const _TreeCanvas({
    required this.positions,
    required this.edges,
    required this.hiddenPersonIds,
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
  final String? focusedPersonId;
  final String? selectedPersonId;
  final List<Map<String, dynamic>> persons;
  final TransformationController transformController;
  final void Function(String personId, Map<String, dynamic> person) onTapNode;
  final void Function(String personId, Map<String, dynamic> person)
      onLongPressNode;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Compute canvas bounds.
    double maxX = 0, maxY = 0;
    for (final pos in positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    final canvasWidth = maxX + kTreeNodeSize.width + 80;
    final canvasHeight = maxY + kTreeNodeSize.height + 80;

    return InteractiveViewer(
      transformationController: transformController,
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
            // Layer 1: connectors (painter).
            CustomPaint(
              size: Size(canvasWidth, canvasHeight),
              painter: TreePainter(
                positions: positions,
                edges: edges,
                hiddenPersonIds: hiddenPersonIds,
                focusedPersonId: focusedPersonId,
                nodeSize: kTreeNodeSize,
              ),
            ),
            // Layer 2: positioned node widgets.
            for (final person in persons)
              if (positions.containsKey(person['id'])) _buildNode(person),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(Map<String, dynamic> person) {
    final id = person['id'] as String;
    final pos = positions[id]!;
    final name = (person['name'] as String?) ?? '';
    final photoUrl = person['avatarUrl'] as String?;
    final isDeceased = (person['isDeceased'] as bool?) ?? false;
    final isViewer = (person['isViewer'] as bool?) ?? false;
    final isAnchor = (person['isAnchor'] as bool?) ?? false;
    final restricted = (person['restricted'] as bool?) ?? false;
    final gender = person['gender'] as String?;

    final isSelected = selectedPersonId == id;
    final isFocused = focusedPersonId == id;

    return Positioned(
      left: pos.dx - kTreeNodeSize.width / 2,
      top: pos.dy - kTreeNodeSize.height / 2,
      width: kTreeNodeSize.width,
      height: kTreeNodeSize.height,
      child: GestureDetector(
        onTap: () => onTapNode(id, person),
        onLongPress: () => onLongPressNode(id, person),
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

  @override
  Widget build(BuildContext context) {
    final ringColor = isFocused
        ? KinrelColors.orange
        : isSelected
            ? KinrelColors.orange.withValues(alpha: 0.6)
            : isViewer
                ? const Color(0xFFE8612A)
                : isDeceased
                    ? const Color(0xFF7A6F8A)
                    : const Color(0x44FFFFFF);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar with ring.
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: ringColor,
              width: isFocused ? 3 : (isSelected || isViewer ? 2 : 1),
            ),
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
          child: ClipOval(
            child: restricted || photoUrl == null || photoUrl!.isEmpty
                ? _placeholderAvatar()
                : Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderAvatar(),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        // Name (truncated).
        SizedBox(
          width: kTreeNodeSize.width - 4,
          child: Text(
            restricted ? 'Restricted' : name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: restricted
                  ? KinrelColors.textSecondaryDark.withValues(alpha: 0.5)
                  : KinrelColors.textWhite,
              fontSize: 11,
              fontFamily: 'DMSans',
              fontWeight:
                  isViewer || isAnchor ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        // Deceased indicator (small dot below name).
        if (isDeceased)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: Color(0xFF7A6F8A),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  Widget _placeholderAvatar() {
    final isFemale = gender?.toLowerCase() == 'female';
    return Container(
      color: isFemale ? const Color(0xFF7A4F5F) : const Color(0xFF4F5F7A),
      child: Center(
        child: Text(
          restricted
              ? '?'
              : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'DMSans',
          ),
        ),
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
