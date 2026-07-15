// lib/graph/widgets/engine/node_layer.dart
// Extracted from family_graph_engine_view.dart to keep the main file
// under ~900 lines.
//
// Contains _buildNodeLayer — the LOD-aware node layer builder that
// renders either a single dot painter (FAR tier) or individual
// positioned node widgets (NEAR/MEDIUM tiers).

part of '../family_graph_engine_view.dart';

/// Mixin containing the LOD-aware node layer builder for
/// _FamilyGraphEngineViewState.
extension _NodeLayerMethods on _FamilyGraphEngineViewState {
  /// Builds the node layer for the current LOD tier.
  List<Widget> _buildNodeLayer(
    GraphLayoutResult layout,
    Set<String> visible,
    Map<String, Map<String, dynamic>> personById,
    Map<String, String> relationLabelById,
    Map<String, KinshipEdgeCategory> relationCategoryById,
    Map<String, Map<String, dynamic>> customColorsByPersonId,
    String? viewerPersonId,
    FlatGraphResult flat,
  ) {
    final Lod lod = _lodFor(_camera.zoomLevel);

    // Dot tier: one painter for ALL visible nodes — no per-node widgets.
    if (lod == Lod.dot) {
      final dots = <Dot>[];
      for (final String id in visible) {
        final pos = layout.positions[id];
        final p = personById[id];
        if (pos == null || p == null) continue;

        // v96 (Phase 3): At FAR (dot) zoom, focused/selected/path
        // nodes get an emphasised dot (larger + accent ring) so they
        // remain discoverable.
        // v96 (Phase 5): Search matches also get emphasised dots.
        final focusedId = ref.read(graphFocusProvider).focusedPersonId;
        final selectedId = ref.read(selectedNodeProvider);
        final pathFocus = ref.read(graphPathFocusProvider).focus;
        final pathNodeIds = pathFocus?.orderedPersonIds.toSet();
        final searchState = ref.read(graphSearchProvider);
        final isEmphasised = shouldOverrideFarTier(
          nodeId: id,
          focusedPersonId: focusedId,
          selectedPersonId: selectedId,
          pathNodeIds: pathNodeIds,
        ) || (searchState.isActive && searchState.isMatch(id));

        dots.add(Dot(
          pos,
          _dotColor(
            p['gender'] as String?,
            (p['isAnchor'] as bool?) ?? false,
            // v69: Use the authoritative category for dot color.
            category: relationCategoryById[id],
            // v83: Use custom colors if available
            customColors: customColorsByPersonId[id],
          ),
          isEmphasised: isEmphasised,
        ));
      }
      return <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: NodeDotPainter(dots, zoom: _camera.zoomLevel),
            // v2.2 Fix 1: SizedBox.expand() ensures the dot painter
            // canvas covers the full Stack area.
            child: const SizedBox.expand(),
          ),
        ),
      ];
    }

    // Full / chip tiers: individual widgets (culling keeps the count small).
    final widgets = <Widget>[];
    final highlightedGen = widget.highlightedGeneration;
    for (final String id in visible) {
      final pos = layout.positions[id];
      final p = personById[id];
      if (pos == null || p == null) continue;
      final Widget node = lod == Lod.full
          ? _buildFullNode(id, p, relationLabelById, relationCategoryById, customColorsByPersonId, viewerPersonId)
          : _buildChipNode(p, category: relationCategoryById[id], customColors: customColorsByPersonId[id]);

      // v62: Dim nodes not in the highlighted generation (if set).
      final int personGen =
          (p['generationIndex'] as num?)?.toInt() ?? 0;
      final double opacity = (highlightedGen != null &&
              personGen != highlightedGen)
          ? 0.15
          : 1.0;

      widgets.add(Positioned(
        left: pos.dx - _FamilyGraphEngineViewState._kNodeSize.width / 2,
        top: pos.dy - _FamilyGraphEngineViewState._kNodeSize.height / 2,
        width: _FamilyGraphEngineViewState._kNodeSize.width,
        height: _FamilyGraphEngineViewState._kNodeSize.height,
        child: Opacity(
          opacity: opacity,
          // 2.5D: Add padding around the node so the elevation shadows
          // (blurRadius up to 20px) have room to render inside the
          // RepaintBoundary layer. Without this padding, the RepaintBoundary
          // clips the shadow to the node's bounds, making it invisible.
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              // v92 (PART 19): Wrap the node in a Stack so we can
              // overlay the +N collapsed-branch affordance chip.
              child: _withBranchAffordance(node, id, flat),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }
}
