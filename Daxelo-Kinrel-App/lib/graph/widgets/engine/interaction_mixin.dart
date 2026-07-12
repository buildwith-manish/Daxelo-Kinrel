// lib/graph/widgets/engine/interaction_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains gesture handlers, tap/long-press handlers, and camera focus.

part of '../family_graph_engine_view.dart';

/// Mixin containing interaction handlers for _FamilyGraphEngineViewState.
mixin _InteractionMixin on ConsumerState<FamilyGraphEngineView> {
  void _onScaleStart(ScaleStartDetails d) {
    _camera.stopAnimation(); // cancel any in-flight fling/animateTo
    _lastFocal = d.focalPoint;
    _baseZoom = _camera.zoomLevel;
    _isPinching = false; // reset; will be set true on first multi-touch update
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // v97: Only fling on a single-finger pan release.
    // Never fling after a pinch — the velocity is unreliable
    // (pinch-release jitter produces large fake velocities).
    if (!_isPinching) {
      final v = d.velocity.pixelsPerSecond;
      if (v.distance > 50) {
        _camera.applyMomentum(v.dx, v.dy);
      }
    }
    _isPinching = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // v97: Determine if this is a pinch (multi-pointer) or a pan.
    // pointerCount > 1 OR a meaningful scale delta indicates pinch.
    final isPinch = d.pointerCount > 1 || (d.scale - 1.0).abs() > 0.01;
    if (isPinch) {
      _isPinching = true;
    }

    // Pan (works for one- and two-finger drags).
    // During a pinch, the focal point moves as the pinch center
    // shifts. This is natural two-finger panning — apply it once
    // here. The zoomTo focal-point compensation below handles
    // keeping the pinch center stable; we do NOT double-apply.
    final Offset delta = d.focalPoint - _lastFocal;
    if (delta != Offset.zero) {
      _camera.panBy(delta.dx, delta.dy);
    }
    _lastFocal = d.focalPoint;

    // Pinch zoom around the focal point.
    if (d.scale != 1.0) {
      final box = context.findRenderObject() as RenderBox?;
      final Offset local = box?.globalToLocal(d.focalPoint) ?? d.focalPoint;
      _camera.zoomTo(_baseZoom * d.scale, focalPoint: local);
    }
  }

  /// v62: Double-tap toggles between 1× and 2× zoom, centered on
  /// the tap focal point. Uses the camera's zoomTo with focalPoint
  /// so the zoom target stays under the user's finger.
  void _handleDoubleTapZoom() {
    final currentZoom = _camera.zoomLevel;
    final targetZoom = currentZoom < 1.5 ? 2.0 : 1.0;
    _camera.zoomTo(targetZoom, focalPoint: _doubleTapPosition);
  }

  // ── v72: Geometric Node Hit-Testing ────────────────────────────────────
  //
  // The parent GestureDetector's ScaleGestureRecognizer competes with
  // the child GraphNode's TapGestureRecognizer. On Flutter web, the
  // scale recognizer wins for ANY pointer sequence, so node taps never
  // fire. We solve this by doing a GEOMETRIC hit-test at the parent
  // level: convert the screen position to graph space, then check if
  // it falls inside any node circle.

  /// Converts a screen-space [localPosition] to graph-space coordinates
  /// using the camera's inverse transform.
  ///
  /// The camera transform is: translate(tx, ty) → scale(zoom).
  /// The inverse is: scale(1/zoom) → translate(-tx, -ty).
  /// So: graphPos = (screenPos - translation) / zoom.
  Offset _screenToGraphSpace(Offset localPosition) {
    final matrix = _camera.transformMatrix;
    // Extract translation (tx, ty) and scale (zoom) from the matrix.
    final zoom = matrix.getMaxScaleOnAxis();
    if (zoom == 0) return localPosition;
    final tx = matrix.getTranslation().x;
    final ty = matrix.getTranslation().y;
    return Offset(
      (localPosition.dx - tx) / zoom,
      (localPosition.dy - ty) / zoom,
    );
  }

  /// Finds the node ID at [screenPos], or null if no node is hit.
  /// v97: LOD-aware hit testing — the hit radius is converted from
  /// a minimum screen-space target to graph space via the current zoom.
  String? _hitTestNode(Offset screenPos, GraphLayoutResult layout) {
    final graphPos = _screenToGraphSpace(screenPos);
    // Compute the graph-space hit radius from a screen-space minimum.
    final metrics = _currentMetrics();
    final graphHitRadius = metrics.graphHitRadius;
    String? bestId;
    double bestDist = double.infinity;
    for (final entry in layout.positions.entries) {
      final dist = (entry.value - graphPos).distance;
      if (dist < graphHitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }
    return bestId;
  }

  /// v91 (PART 13): Computes the set of edge IDs that should be dimmed
  /// when relationship focus mode is active.
  ///
  /// When a node is selected, DIRECTLY CONNECTED edges retain normal
  /// (or increased) clarity, while UNRELATED edges gently reduce
  /// opacity by ~30%. The selected edge (if any) and any sweep edge
  /// are never dimmed.
  ///
  /// v95 (Phase 1): When a person is FOCUSED (via graphFocusProvider),
  /// uses the focus state's first-degree + second-degree neighbour
  /// sets to keep more edges visible. Only truly unrelated edges
  /// (neither first nor second degree) are dimmed. This creates a
  /// richer focus experience: immediate family stays bright, near
  /// relatives stay visible, distant branches dim softly.
  ///
  /// When no person is focused, falls back to the selection-based
  /// first-degree dim (the v91 behavior).
  ///
  /// Returns `null` when no node is selected AND no person is focused,
  /// so the painter can short-circuit the dim check entirely.
  Set<String>? _computeDimmedEdgeIds(List<DedupedEdge> edges) {
    final focusState = ref.read(graphFocusProvider);
    final String? focusedPerson = focusState.focusedPersonId;
    final searchState = ref.read(graphSearchProvider);

    // v96 (Phase 5): When search is active, dim edges that are NOT
    // connected to any matching node. Matching nodes stay bright
    // regardless of focus state.
    if (searchState.isActive && searchState.matchIds.isNotEmpty) {
      final connected = <String>{};
      final matchSet = searchState.matchIdSet;
      for (final deduped in edges) {
        final e = deduped.edge;
        if (matchSet.contains(e.sourceId) || matchSet.contains(e.targetId)) {
          connected.add(e.id);
        }
      }
      if (connected.length == edges.length) return null;
      final dimmed = <String>{};
      for (final deduped in edges) {
        if (!connected.contains(deduped.edge.id)) {
          dimmed.add(deduped.edge.id);
        }
      }
      return dimmed;
    }

    if (focusedPerson != null) {
      // Focus mode: use first + second degree neighbour sets.
      // An edge is "connected" if EITHER endpoint is the focus person,
      // a first-degree neighbour, or a second-degree neighbour.
      final connected = <String>{};
      final emphasisedIds = <String>{
        focusedPerson,
        ...focusState.firstDegreeIds,
        ...focusState.secondDegreeIds,
      };
      for (final deduped in edges) {
        final e = deduped.edge;
        if (emphasisedIds.contains(e.sourceId) ||
            emphasisedIds.contains(e.targetId)) {
          connected.add(e.id);
        }
      }
      if (connected.length == edges.length) return null;
      final dimmed = <String>{};
      for (final deduped in edges) {
        if (!connected.contains(deduped.edge.id)) {
          dimmed.add(deduped.edge.id);
        }
      }
      return dimmed;
    }

    // Fallback: selection-based first-degree dim (v91 behavior).
    final String? selectedNode = ref.read(selectedNodeProvider);
    if (selectedNode == null) return null;

    final connected = <String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      if (e.sourceId == selectedNode || e.targetId == selectedNode) {
        connected.add(e.id);
      }
    }

    // If every visible edge is connected, there's nothing to dim.
    if (connected.length == edges.length) return null;

    // Return the COMPLEMENT — edges that are NOT connected.
    final dimmed = <String>{};
    for (final deduped in edges) {
      if (!connected.contains(deduped.edge.id)) {
        dimmed.add(deduped.edge.id);
      }
    }
    return dimmed;
  }

  /// v92 (PARTS 14–16): Resolve the viewer→target kinship path.
  ///
  /// The selected node is the path target. The viewer is the current
  /// viewerPersonId. The path is resolved via the existing
  /// `RelationshipEngine.resolvePath` (which delegates to
  /// `GraphService.findPath` BFS) and post-processed into ordered
  /// person IDs + ordered edge IDs by the
  /// `GraphPathFocusNotifier`.
  ///
  /// This method is called ONCE per build — never inside paint().
  /// The notifier caches the result and short-circuits when the
  /// inputs (viewer, target, graphRevision) haven't changed.
  ///
  /// Returns the resolved `GraphKinshipPathFocus`, or null when:
  ///   • no node is selected
  ///   • viewer is null
  ///   • viewer == selected node
  ///   • no path exists
  GraphKinshipPathFocus? _resolvePathFocus({
    required String? viewerPersonId,
    required FlatGraphResult flat,
    required List<DedupedEdge> edges,
    required String? anchorId,
  }) {
    final String? targetPersonId = ref.read(selectedNodeProvider);
    if (targetPersonId == null || viewerPersonId == null) {
      // Clear any previous focus when nothing is selected.
      ref.read(graphPathFocusProvider.notifier).clear();
      return null;
    }

    // Build the GraphPerson list + relationship tuples the engine needs.
    final persons = <GraphPerson>[];
    for (final p in flat.persons) {
      persons.add(GraphPerson(
        id: (p['id'] ?? '').toString(),
        name: (p['name'] ?? '').toString(),
        gender: p['gender'] as String?,
        generationIndex:
            (p['generationIndex'] as num?)?.toInt() ?? 0,
        isAnchor: (p['isAnchor'] as bool?) ?? false,
        photoUrl: p['photoUrl'] as String?,
        isDeceased: (p['isDeceased'] as bool?) ?? false,
      ));
    }
    final relationships = <({String fromId, String toId, String type})>[
      for (final r in flat.relationships)
        (
          fromId: (r['fromPersonId'] ?? '').toString(),
          toId: (r['toPersonId'] ?? '').toString(),
          type: (r['relationshipKey'] ?? 'unknown').toString(),
        ),
    ];

    // Resolve the structural classification for the overall label/key.
    // Reuses the cached classification from relationCategoryById when
    // possible (already computed for node coloring).
    StructuralClassification? classification;
    try {
      classification = RelationshipEngine.instance.resolveClassification(
        viewerPersonId: viewerPersonId,
        targetPersonId: targetPersonId,
        persons: persons,
        relationships: relationships,
      );
    } catch (_) {
      // Classification is best-effort — if it fails, the path is
      // still resolved without a label.
      classification = null;
    }

    final graphRevision =
        edges.length * 100003 + flat.persons.length;

    return ref.read(graphPathFocusProvider.notifier).resolve(
          viewerPersonId: viewerPersonId,
          targetPersonId: targetPersonId,
          edges: edges,
          persons: persons,
          relationships: relationships,
          graphRevision: graphRevision,
          classification: classification,
        );
  }

  /// v91 (PART 12): Cinematic node focus. When the user taps a person,
  /// the camera gently animates to bring the node towards the focus
  /// region (slightly above viewport center, where the eye naturally
  /// rests). The zoom level is preserved — this is a guided pan, NOT
  /// an aggressive zoom-in.
  ///
  /// Respects reduced motion: when `MediaQuery.disableAnimationsOf` is
  /// true, the camera jumps immediately instead of animating.
  ///
  /// Does NOT create a second camera system — uses the existing
  /// `CameraController` and its `animateTo` API.
  void _maybeFocusCameraOnNode(String nodeId, GraphLayoutResult layout) {
    final pos = layout.positions[nodeId];
    if (pos == null || _viewportSize == Size.zero) return;

    // If the node is already comfortably visible near the viewport
    // center, do not move the camera. This prevents unnecessary motion
    // when the user taps a node that's already in focus.
    final viewport = _camera.computeViewport(_viewportSize);
    final focusRegion = Rect.fromCenter(
      center: viewport.center,
      width: viewport.width * 0.4,
      height: viewport.height * 0.4,
    );
    // Apply the same Y offset used for edges so the focus region aligns
    // with the visual circle center, not the Positioned box center.
    final visualPos = Offset(pos.dx, pos.dy + _kCircleCenterYOffset);
    if (focusRegion.contains(visualPos)) return;

    // Reduced motion → immediate pan, no animation.
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final Duration duration =
        reduced ? Duration.zero : const Duration(milliseconds: 420);

    // Target: bring the node to viewport center, preserving current zoom.
    _camera.animateTo(
      -pos.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -pos.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  /// v92 (PART 17): Canvas tap dispatcher. Checks edge midpoints FIRST
  /// (with a 48px invisible hit target), then falls back to node
  /// hit-testing. This lets the user tap the small midpoint bead/heart
  /// to open the relationship details sheet without enlarging the
  /// visual bead to 48px.
  ///
  /// The hit-test order is:
  ///   1. Edge midpoint (48px radius) — opens RelationshipInfoSheet
  ///   2. Node (44px radius) — selects node + shows quick-actions sheet
  ///
  /// If neither hits, the tap is a no-op (canvas background tap).
  void _handleCanvasTapDown(
    TapDownDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // ── 1. Edge midpoint hit-test ──────────────────────────────────
    final edgeId = _hitTestEdge(details.localPosition);
    if (edgeId != null) {
      _handleEdgeTap(edgeId, flat, viewerPersonId);
      return;
    }

    // ── 2. Fall back to node hit-test ──────────────────────────────
    _handleNodeTapDown(details, layout, flat, viewerPersonId);
  }

  /// v92 (PART 17): Geometric hit-test for edge midpoints. Returns the
  /// edge ID whose midpoint is within 48 logical px of [screenPos], or
  /// null if no edge hits.
  ///
  /// The 48px hit target is the spec'd accessible touch size (PART 21).
  /// The VISUAL bead remains 4–6px — only the invisible hit region is
  /// enlarged. If multiple edges overlap near the tap point, the
  /// closest midpoint wins.
  ///
  /// Phase 6 (hit-test parity): The midpoint is computed from the
  /// EFFECTIVE endpoints returned by `resolveEffectiveEdgeEndpoints` —
  /// the SAME function the painter uses to construct the rendered
  /// bezier curve. This is the entire point of the parity fix: before,
  /// the painter redirected parent→child edges to start at the union
  /// midpoint, but this hit-tester still used the parent's raw node
  /// position, so the rendered curve and the tap target were two
  /// different points. Tapping the actual rendered line near the union
  /// glyph silently missed, or registered a hit on a neighbouring edge.
  String? _hitTestEdge(Offset screenPos) {
    if (_currentEdges.isEmpty || _currentPositionsWithOffset.isEmpty) {
      return null;
    }
    final graphPos = _screenToGraphSpace(screenPos);
    // v97: Convert screen-space hit radius (48px) to graph space.
    final zoom = _camera.zoomLevel;
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    final hitRadius = 48.0 / safeZoom; // 48px screen-space touch target
    String? bestId;
    double bestDist = double.infinity;
    for (final deduped in _currentEdges) {
      final e = deduped.edge;
      final s = _currentPositionsWithOffset[e.sourceId];
      final t = _currentPositionsWithOffset[e.targetId];
      if (s == null || t == null) continue;
      // Phase 6: resolve the effective endpoints through the SAME
      // helper the painter uses. For a union-redirected parent→child
      // edge, `resolved.source` is the union midpoint (not the parent's
      // raw node position), so the midpoint computed below matches the
      // midpoint of the actually-rendered curve.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: e.sourceId,
        targetId: e.targetId,
        rawSource: s,
        rawTarget: t,
        coupleUnions: _currentCoupleUnions,
        positionOf: (id) => _currentPositionsWithOffset[id],
      );
      // The midpoint is the visual center of the edge. For Bézier
      // curves the actual PathMetric 50% tangent position may differ
      // slightly, but for hit-testing the geometric midpoint is a
      // close-enough approximation and is O(1) per edge.
      final mid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );
      final dist = (mid - graphPos).distance;
      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = e.id;
      }
    }
    return bestId;
  }

  /// v92 (PART 17): Handle a tap on an edge midpoint. Selects the edge
  /// (drives the v91 premium selected-edge + one-shot sweep visual)
  /// and opens the RelationshipInfoSheet with the relationship
  /// details + optional path focus info.
  ///
  /// IMPORTANT: The heart symbol is a VISUAL choice — it does NOT
  /// imply spouse semantics. The relationship label is always
  /// resolved from the actual `relationshipKey` stored on the edge,
  /// not from the midpoint symbol. A custom relationship with a heart
  /// midpoint will show its actual custom name in the sheet.
  void _handleEdgeTap(
    String edgeId,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // Find the deduped edge.
    final deduped = _currentEdges
        .where((d) => d.edge.id == edgeId)
        .firstOrNull;
    if (deduped == null) return;
    final e = deduped.edge;

    // Select the edge — drives the v91 premium selected-edge visual
    // + the one-shot sweep.
    ref.read(selectedEdgeProvider.notifier).state = edgeId;

    // Resolve person A (source) and person B (target) from flat.persons.
    final sourceMap = flat.persons
        .where((p) => p['id'] == e.sourceId)
        .firstOrNull;
    final targetMap = flat.persons
        .where((p) => p['id'] == e.targetId)
        .firstOrNull;
    if (sourceMap == null || targetMap == null) return;

    final sourceName = (sourceMap['name'] as String?) ?? 'Unknown';
    final targetName = (targetMap['name'] as String?) ?? 'Unknown';
    final sourceGender = sourceMap['gender'] as String?;
    final targetGender = targetMap['gender'] as String?;

    // Resolve the relationship label from the actual relationshipKey.
    // The heart symbol does NOT override this — heart is purely visual.
    // PART 17 / PART 21: heart-symbol semantic separation proof.
    final customColors = _currentEdgeCustomColors[e.id];
    String relationshipKey = e.relationshipKey;
    String? customRelationshipName;
    if (customColors != null) {
      // If the custom colors include a custom relationship name, use it.
      // Otherwise fall back to the relationshipKey.
      customRelationshipName =
          customColors['relationshipName'] as String?;
    }

    // v92 (PART 16): Resolve the path focus (if any) to pass to the
    // sheet. If the tapped edge is part of the active path, show the
    // step index.
    final pathFocus = ref.read(graphPathFocusProvider).focus;
    int? stepIndex;
    int? stepCount;
    if (pathFocus != null && pathFocus.orderedEdgeIds.contains(e.id)) {
      stepCount = pathFocus.stepCount;
      stepIndex = pathFocus.orderedEdgeIds.indexOf(e.id) + 1;
    }

    // Open the relationship details sheet. The sheet shows:
    //   • Person A → Person B with the relationship label
    //   • Directional sentences (A is the X of B / B is the Y of A)
    //   • Optional path focus section (if pathFocus is non-null)
    //   • Optional "Focus Path" button (if pathFocus is multi-hop)
    RelationshipInfoSheet.show(
      context,
      sourceId: e.sourceId,
      sourceName: sourceName,
      sourceGender: sourceGender,
      targetId: e.targetId,
      targetName: targetName,
      targetGender: targetGender,
      relationshipKey:
          customRelationshipName ?? relationshipKey,
      pathFocus: pathFocus,
      stepIndex: stepIndex,
      stepCount: stepCount,
      onFocusPath: (pathFocus != null && pathFocus.isMultiHop)
          ? () {
              // Re-trigger the trace by re-selecting the target node.
              // The trace controller will (re)start because the path
              // is already resolved — _maybeStartTrace in the wrapper
              // sees the same path and no-ops, so we explicitly reset
              // and restart by toggling the selection.
              Navigator.of(context).maybePop();
              // Re-select the target to retrigger the trace.
              ref.read(selectedNodeProvider.notifier).state =
                  pathFocus.targetPersonId;
            }
          : null,
    );
  }

  /// Handles a tap-down on the canvas. If the tap hits a node, shows
  /// the quick-actions sheet (same as long-press) — does NOT navigate
  /// to a separate route, avoiding the "Page Not Found" error.
  void _handleNodeTapDown(
    TapDownDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // Select the node.
    ref.read(selectedNodeProvider.notifier).state = nodeId;

    // v91 (PART 12): Cinematic camera focus on node selection.
    _maybeFocusCameraOnNode(nodeId, layout);

    // Show the quick-actions sheet (same as long-press).
    final personData = flat.persons
        .where((p) => p['id'] == nodeId)
        .firstOrNull;
    if (personData == null) return;

    final graphPersonData = GraphPersonData(
      id: nodeId,
      name: (personData['name'] as String?) ?? '',
      gender: personData['gender'] as String?,
      generationIndex:
          (personData['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (personData['isAnchor'] as bool?) ?? false,
      photoUrl: personData['photoUrl'] as String?,
      isDeceased: (personData['isDeceased'] as bool?) ?? false,
    );
    final isAnchor = (personData['isAnchor'] as bool?) ?? false;
    // v99 (Phase 8): Resolve role from provider — not hardcoded.
    final _role = ref.read(currentUserFamilyRoleProvider(widget.familyId));
    final _canRemove = _role == 'admin' || _role == 'owner';
    GraphQuickActions.show(
      context,
      graphPersonData,
      familyId: widget.familyId,
      isOwner: _canRemove,
      isSelf: isAnchor,
      ref: ref,
      onFocusPerson: _onFocusPerson,
      onViewRelationship: _onViewRelationship,
    );
  }

  /// Handles a long-press on the canvas. If the press hits a node,
  /// shows the quick-actions sheet.
  void _handleNodeLongPress(
    LongPressStartDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // Find the person data for this node.
    final personData = flat.persons
        .where((p) => p['id'] == nodeId)
        .firstOrNull;
    if (personData == null) return;

    final graphPersonData = GraphPersonData(
      id: nodeId,
      name: (personData['name'] as String?) ?? '',
      gender: personData['gender'] as String?,
      generationIndex:
          (personData['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (personData['isAnchor'] as bool?) ?? false,
      photoUrl: personData['photoUrl'] as String?,
      isDeceased: (personData['isDeceased'] as bool?) ?? false,
    );
    final isAnchor = (personData['isAnchor'] as bool?) ?? false;
    // v99 (Phase 8): Resolve role from provider — not hardcoded.
    final _role = ref.read(currentUserFamilyRoleProvider(widget.familyId));
    final _canRemove = _role == 'admin' || _role == 'owner';
    GraphQuickActions.show(
      context,
      graphPersonData,
      familyId: widget.familyId,
      isOwner: _canRemove,
      isSelf: isAnchor,
      ref: ref,
      onFocusPerson: _onFocusPerson,
      onViewRelationship: _onViewRelationship,
    );
  }

  // ── v99 (Phase 1): Engine-owned focus callback ────────────────────────
  //
  // Passed to GraphQuickActions.show() so the Focus action has access
  // to real deduped edges + camera viewport — NOT the empty edges +
  // null viewport that the previous direct-provider-call passed.
}
