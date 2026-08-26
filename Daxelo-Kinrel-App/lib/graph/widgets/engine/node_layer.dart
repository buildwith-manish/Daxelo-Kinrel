// lib/graph/widgets/engine/node_layer.dart
// Extracted from family_graph_engine_view.dart to keep the main file
// under ~900 lines.
//
// Contains _buildNodeLayer — the LOD-aware node layer builder that
// renders either a single dot painter (FAR/MICRO/MINI tiers) or
// individual positioned node widgets (NEAR/COMPACT/CHIP tiers).
//
// v5.111: Updated for the new 5-tier semantic zoom system. The
// dispatch logic now handles:
//   • Lod.full     → _buildFullNode (premium GraphNode widgets)
//   • Lod.compact  → _buildFullNode (same widget, relation label faded
//                   automatically by relationLabelOpacityFor)
//   • Lod.mini     → NodeMiniPainter (circle + border + initial, single painter)
//   • Lod.micro    → NodeMicroPainter (colored circle + ring, single painter)
//   • Lod.chip     → _buildChipNode (legacy, kept for focus-mode fallback)
//   • Lod.dot      → NodeDotPainter (basic dots, single painter)

part of '../family_graph_engine_view.dart';

/// Mixin containing the LOD-aware node layer builder for
/// _FamilyGraphEngineViewState.
extension _NodeLayerMethods on _FamilyGraphEngineViewState {
  /// Builds the node layer for the current LOD tier.
  ///
  /// [effectivePositions] is the MERGED position map (auto-layout ⊕
  /// saved overrides ⊕ live drag overrides) — the SAME map the edge
  /// layer uses.
  List<Widget> _buildNodeLayer(
    GraphLayoutResult layout,
    Map<String, Offset> effectivePositions,
    Set<String> visible,
    Map<String, Map<String, dynamic>> personById,
    Map<String, String> relationLabelById,
    Map<String, KinshipEdgeCategory> relationCategoryById,
    Map<String, Map<String, dynamic>> customColorsByPersonId,
    String? viewerPersonId,
    FlatGraphResult flat,
  ) {
    final Lod lod = _lodFor(_camera.zoomLevel);

    // ── v5.111: MINI tier — circle + border + initial (single painter) ──
    if (lod == Lod.mini) {
      return _buildSinglePainterLayer(
        visible: visible,
        effectivePositions: effectivePositions,
        personById: personById,
        relationCategoryById: relationCategoryById,
        customColorsByPersonId: customColorsByPersonId,
        viewerPersonId: viewerPersonId,
        painterBuilder: (dots) =>
            NodeMiniPainter(dots, zoom: _camera.zoomLevel),
        includeInitial: true,
      );
    }

    // ── v5.111: MICRO tier — colored circle + accent ring (single painter) ──
    if (lod == Lod.micro) {
      return _buildSinglePainterLayer(
        visible: visible,
        effectivePositions: effectivePositions,
        personById: personById,
        relationCategoryById: relationCategoryById,
        customColorsByPersonId: customColorsByPersonId,
        viewerPersonId: viewerPersonId,
        painterBuilder: (dots) =>
            NodeMicroPainter(dots, zoom: _camera.zoomLevel),
        includeInitial: false,
      );
    }

    // ── DOT tier — basic dots (single painter) ──
    if (lod == Lod.dot) {
      return _buildSinglePainterLayer(
        visible: visible,
        effectivePositions: effectivePositions,
        personById: personById,
        relationCategoryById: relationCategoryById,
        customColorsByPersonId: customColorsByPersonId,
        viewerPersonId: viewerPersonId,
        painterBuilder: (dots) =>
            NodeDotPainter(dots, zoom: _camera.zoomLevel),
        includeInitial: false,
      );
    }

    // ── FULL / COMPACT / CHIP tiers — individual widgets ──
    final widgets = <Widget>[];
    final highlightedGen = widget.highlightedGeneration;
    for (final String id in visible) {
      final pos = effectivePositions[id];
      final p = personById[id];
      if (pos == null || p == null) continue;

      final Widget node;
      if (lod == Lod.full || lod == Lod.compact) {
        // v5.111: COMPACT uses the same _buildFullNode — the relation
        // label fade is driven by relationLabelOpacityFor (which fades
        // to 0 at zoom < 0.6, well within the COMPACT range 0.50-0.85).
        // The name remains visible. No additional wiring needed.
        node = _buildFullNode(
          id,
          p,
          relationLabelById,
          relationCategoryById,
          customColorsByPersonId,
          viewerPersonId,
        );
      } else {
        // Lod.chip — legacy fallback (shouldn't normally be reached
        // in the new 5-tier system, but kept for safety).
        node = _buildChipNode(
          p,
          category: relationCategoryById[id],
          customColors: customColorsByPersonId[id],
          isViewer: viewerPersonId != null && id == viewerPersonId,
        );
      }

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
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _withBranchAffordance(node, id, flat),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// v5.111: Shared helper that builds a single-painter node layer
  /// (used by MINI, MICRO, and DOT tiers). All three tiers render
  /// every visible node in ONE CustomPaint call — no per-node widgets.
  ///
  /// [painterBuilder] receives the list of [Dot] objects and returns
  /// the configured painter. [includeInitial] controls whether the
  /// person's first-name initial is attached to each Dot (MINI only).
  List<Widget> _buildSinglePainterLayer({
    required Set<String> visible,
    required Map<String, Offset> effectivePositions,
    required Map<String, Map<String, dynamic>> personById,
    required Map<String, KinshipEdgeCategory> relationCategoryById,
    required Map<String, Map<String, dynamic>> customColorsByPersonId,
    required String? viewerPersonId,
    required CustomPainter Function(List<Dot> dots) painterBuilder,
    required bool includeInitial,
  }) {
    final dots = <Dot>[];
    final focusedId = ref.read(graphFocusProvider).focusedPersonId;
    final selectedId = ref.read(selectedNodeProvider);
    final pathFocus = ref.read(graphPathFocusProvider).focus;
    final pathNodeIds = pathFocus?.orderedPersonIds.toSet();
    final searchState = ref.read(graphSearchProvider);

    for (final String id in visible) {
      final pos = effectivePositions[id];
      final p = personById[id];
      if (pos == null || p == null) continue;

      final isEmphasised = shouldOverrideFarTier(
            nodeId: id,
            focusedPersonId: focusedId,
            selectedPersonId: selectedId,
            pathNodeIds: pathNodeIds,
          ) ||
          (searchState.isActive && searchState.isMatch(id));

      // Compute the initial letter (MINI only).
      String? initial;
      if (includeInitial) {
        final name = (p['name'] as String?) ?? '';
        if (name.isNotEmpty) {
          initial = name.trimLeft().substring(0, 1).toUpperCase();
        }
      }

      dots.add(Dot(
        pos,
        _dotColor(
          p['gender'] as String?,
          (p['isAnchor'] as bool?) ?? false,
          category: relationCategoryById[id],
          customColors: customColorsByPersonId[id],
          isViewer: viewerPersonId != null && id == viewerPersonId,
        ),
        isEmphasised: isEmphasised,
        initial: initial,
      ));
    }

    return <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: painterBuilder(dots),
          child: const SizedBox.expand(),
        ),
      ),
    ];
  }
}
