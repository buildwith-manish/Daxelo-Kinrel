// lib/graph/widgets/engine/interaction_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains gesture handlers, tap/long-press handlers, and camera focus.

part of '../family_graph_engine_view.dart';

/// Mixin containing interaction handlers for _FamilyGraphEngineViewState.
extension _InteractionMethods on _FamilyGraphEngineViewState {
  // ── Pan tuning constants ─────────────────────────────────────────────
  //
  // These values are the single source of truth for graph pan feel.
  // Tuned for a premium, controlled experience comparable to Figma /
  // Google Maps — small drags produce small movements, large drags
  // move proportionally, and release momentum is minimal.
  //
  // The key insight: live-drag sensitivity MUST match release-momentum
  // sensitivity. If they differ, the user feels a velocity discontinuity
  // the instant their finger lifts — the #1 cause of "uncontrolled" feel.

  /// Minimum finger movement before pan engages. Filters finger jitter.
  static const double _kPanDeadZone = 3.0;

  /// Drag sensitivity multiplier applied to BOTH live drag AND release
  /// momentum. 0.78 = 22% slower than raw finger movement. This gives
  /// a controlled, premium feel without feeling sluggish.
  static const double _kPanSensitivity = 0.78;

  /// Max pan delta per frame (px). Caps live-drag speed at
  /// 40 × 60fps = 2400px/s — comfortably above the momentum clamp
  /// (1800px/s) so drag never outpaces fling.
  static const double _kPanMaxDeltaPerFrame = 40.0;

  /// Minimum release velocity (px/s) to trigger momentum. Below this,
  /// the graph just stops where the finger lifted.
  static const double _kMomentumMinVelocity = 200.0;

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
      if (v.distance > _kMomentumMinVelocity) {
        // Apply the SAME sensitivity as live drag so there's no velocity
        // discontinuity on release. Without this, a slow controlled drag
        // suddenly becomes a full-velocity fling the instant the finger
        // lifts — the primary cause of "uncontrolled" feel.
        _camera.applyMomentum(
          v.dx * _kPanSensitivity,
          v.dy * _kPanSensitivity,
        );
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
    // Premium control: dead zone + sensitivity multiplier + max delta cap.
    // - Dead zone (_kPanDeadZone): ignore micro-movements from finger jitter
    // - Sensitivity (_kPanSensitivity): 0.78x for controlled, premium feel
    // - Max delta (_kPanMaxDeltaPerFrame): prevent sudden large jumps
    final Offset rawDelta = d.focalPoint - _lastFocal;
    if (rawDelta != Offset.zero) {
      if (rawDelta.distance > _kPanDeadZone) {
        double dx = (rawDelta.dx * _kPanSensitivity)
            .clamp(-_kPanMaxDeltaPerFrame, _kPanMaxDeltaPerFrame);
        double dy = (rawDelta.dy * _kPanSensitivity)
            .clamp(-_kPanMaxDeltaPerFrame, _kPanMaxDeltaPerFrame);
        _camera.panBy(dx, dy);
      }
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
  /// the tap focal point. Uses the camera's zoomToSpring (P3.1) with
  /// focalPoint so the zoom target stays under the user's finger and
  /// the transition animates with a critically-damped spring.
  ///
  /// P3.1: switched from instant `zoomTo` to spring-based `zoomToSpring`
  /// so the double-tap zoom feels weighted and alive. Reduced-motion
  /// users snap instantly (no animation).
  void _handleDoubleTapZoom() {
    final currentZoom = _camera.zoomLevel;
    final targetZoom = currentZoom < 1.5 ? 2.0 : 1.0;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    _camera.zoomToSpring(
      targetZoom,
      focalPoint: _doubleTapPosition,
      reducedMotion: reduced,
    );
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
    final visualPos = Offset(pos.dx, pos.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset);
    if (focusRegion.contains(visualPos)) return;

    // Reduced motion → immediate pan, no animation.
    // P2.2: Uses spring physics (animateToWithSpring) instead of
    // the previous linear tween for a cinematic focus pull per Vision §5 Layer 1.
    final bool reduced = MediaQuery.disableAnimationsOf(context);

    // Target: bring the node to viewport center, preserving current zoom.
    _camera.animateToWithSpring(
      -pos.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -pos.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      reducedMotion: reduced,
    );
  }

  /// Canvas tap handler. Tapping the canvas selects a node (if the tap
  /// is within 44px of a node). Tapping the edge midpoint does NOT open
  /// the Connection screen — that gesture was moved to long-press (see
  /// [_handleNodeLongPress]). This prevents accidental opens when the
  /// user is just trying to select a node near a connection.
  ///
  /// If no node hits, the tap is a no-op (canvas background tap).
  void _handleCanvasTapDown(
    TapDownDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
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

    // P3.2: soft tick on edge tap.
    GraphHaptics.edgeTap(context);

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

    // P3.2: soft tick on node tap.
    GraphHaptics.nodeTap(context);

    // P2.1: If path-select mode is active, intercept the tap to select
    // the from/to nodes instead of showing quick actions.
    final focusState = ref.read(graphFocusProvider);
    if (focusState.pathSelectPhase == PathSelectPhase.awaitingFrom) {
      ref.read(graphFocusProvider.notifier).setPathSelectFrom(nodeId);
      SemanticsService.announce(
          'Selected. Tap the second person.', TextDirection.ltr);
      return;
    }
    if (focusState.pathSelectPhase == PathSelectPhase.awaitingTo) {
      final accepted =
          ref.read(graphFocusProvider.notifier).setPathSelectTo(nodeId);
      if (!accepted) {
        SemanticsService.announce(
            'Pick a different person.', TextDirection.ltr);
        return;
      }
      // Both nodes selected — trigger the path trace.
      _triggerPathTrace(
        focusState.pathSelectFromId!,
        nodeId,
        layout,
        flat,
        viewerPersonId,
      );
      return;
    }

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

  /// Handles a long-press on the canvas.
  ///
  /// Hit-test order:
  ///   1. Edge midpoint (48px radius) — opens the Connection screen
  ///      (RelationshipInfoSheet). This is the ONLY way to open the
  ///      Connection screen from the graph canvas. Tapping the midpoint
  ///      no longer opens it (see [_handleCanvasTapDown]).
  ///   2. Node (44px radius) — starts the compare-drag gesture.
  ///
  /// If neither hits, the long-press is a no-op (canvas background).
  void _handleNodeLongPress(
    LongPressStartDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // ── 1. Edge midpoint hit-test (opens Connection screen) ───────
    // The Connection screen opens ONLY on long-press of the midpoint
    // indicator (dot/heart). This is deliberate: tapping the midpoint
    // used to open it, but that caused accidental opens when users
    // were trying to select a nearby node. Long-press is a more
    // intentional gesture, and it works consistently on both touch
    // (press + hold) and desktop (mouse down + hold) — Flutter's
    // LongPressGestureRecognizer handles both uniformly.
    final edgeId = _hitTestEdge(details.localPosition);
    if (edgeId != null) {
      _handleEdgeTap(edgeId, flat, viewerPersonId);
      return;
    }

    // ── 2. Node hit-test (starts compare-drag) ────────────────────
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // P3.2: clear "menu opening" haptic on long-press.
    GraphHaptics.longPress(context);

    // P2.4: Start the two-node select-and-compare drag gesture.
    // Instead of immediately showing the quick-actions sheet, the
    // long-press starts a drag. If the user releases on another node,
    // the path trace fires (compare gesture). If the user releases on
    // the same node (no drag), the quick-actions sheet shows (legacy
    // behavior). This makes long-press-drag a direct "connect two
    // people" gesture — no FAB needed.
    _compareDragFromId = nodeId;
    _compareDragPosition = details.localPosition;
    setState(() {});

    // Also announce for screen readers.
    SemanticsService.announce(
        'Comparing. Drag to another person and release.', TextDirection.ltr);
  }

  /// P2.4: Handles drag movement during the compare gesture.
  /// Updates the visual connection line position.
  void _handleCompareDragUpdate(
    LongPressMoveUpdateDetails details,
    GraphLayoutResult layout,
  ) {
    if (_compareDragFromId == null) return;
    _compareDragPosition = details.localPosition;
    setState(() {});
  }

  /// P2.4: Handles release of the compare gesture.
  /// If released over a different node, triggers the path trace.
  /// If released over the same node (or empty canvas), shows quick actions.
  void _handleCompareDragEnd(
    LongPressEndDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final fromId = _compareDragFromId;
    if (fromId == null) return;

    // Clear the drag state first so the visual line disappears.
    final dragFromId = fromId;
    _compareDragFromId = null;
    setState(() {});

    // Hit-test the release position.
    final toId = _hitTestNode(details.localPosition, layout);

    if (toId != null && toId != dragFromId) {
      // Released on a different node → trigger the compare path trace.
      _triggerPathTrace(
        dragFromId,
        toId,
        layout,
        flat,
        viewerPersonId,
      );
    } else {
      // Released on the same node or empty canvas → show quick actions
      // (legacy long-press behavior).
      final personData = flat.persons
          .where((p) => p['id'] == dragFromId)
          .firstOrNull;
      if (personData == null) return;

      final graphPersonData = GraphPersonData(
        id: dragFromId,
        name: (personData['name'] as String?) ?? '',
        gender: personData['gender'] as String?,
        generationIndex:
            (personData['generationIndex'] as num?)?.toInt() ?? 0,
        isAnchor: (personData['isAnchor'] as bool?) ?? false,
        photoUrl: personData['photoUrl'] as String?,
        isDeceased: (personData['isDeceased'] as bool?) ?? false,
      );
      final isAnchor = (personData['isAnchor'] as bool?) ?? false;
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
  }

  // ── v99 (Phase 1): Engine-owned focus callback ────────────────────────
  //
  // Passed to GraphQuickActions.show() so the Focus action has access
  // to real deduped edges + camera viewport — NOT the empty edges +
  // null viewport that the previous direct-provider-call passed.

  // ── P2.1: Path trace + result bottom sheet ────────────────────────────

  /// Resolves the kinship path between [fromId] and [toId] and shows
  /// the result bottom sheet with the kinship term, path steps, and
  /// audio button.
  void _triggerPathTrace(
    String fromId,
    String toId,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // Build the relationships list for RelationshipEngine.resolvePath.
    final relationships = flat.relationships.map((r) {
      final fromId = r['fromPersonId']?.toString() ?? '';
      final toId = r['toPersonId']?.toString() ?? '';
      final type = r['relationshipKey']?.toString() ?? 'unknown';
      return (fromId: fromId, toId: toId, type: type);
    }).toList();

    // Build GraphPerson list for the path resolver.
    final persons = flat.persons.map((p) {
      return GraphPerson(
        id: p['id'] as String,
        name: (p['name'] as String?) ?? '',
        gender: p['gender'] as String?,
        generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
        isAnchor: (p['isAnchor'] as bool?) ?? false,
        photoUrl: p['photoUrl'] as String?,
        isDeceased: (p['isDeceased'] as bool?) ?? false,
      );
    }).toList();

    // Build deduped edges for the path focus resolver.
    final dedupedEdges = EdgeDeduplicator.deduplicate(
      flat.relationships.map((r) => GraphEdgeData(
            id: r['id'] as String,
            sourceId: r['fromPersonId']?.toString() ?? '',
            targetId: r['toPersonId']?.toString() ?? '',
            relationshipKey: r['relationshipKey']?.toString() ?? 'unknown',
          )).toList(),
    );

    // Resolve the path.
    final pathFocus = ref.read(graphPathFocusProvider.notifier).resolve(
          viewerPersonId: fromId,
          targetPersonId: toId,
          edges: dedupedEdges,
          persons: persons,
          relationships: relationships,
          graphRevision: 0,
        );

    // Mark trace as complete.
    ref.read(graphFocusProvider.notifier).markPathSelectComplete();

    // Show the result bottom sheet.
    if (pathFocus == null) {
      _showNoPathSheet(fromId, toId, flat);
      return;
    }

    // P3.2: clear "answer" haptic when the compare result sheet opens.
    GraphHaptics.compareComplete(context);

    // P2.1: The trace animation is driven automatically by EdgeSelectionWrapper
    // when it detects the resolved path focus. No need to call startTrace directly.

    _showPathResultSheet(pathFocus, flat);
  }

  void _showNoPathSheet(String fromId, String toId, FlatGraphResult flat) {
    final fromName = flat.persons
        .where((p) => p['id'] == fromId)
        .firstOrNull?['name'];
    final toName = flat.persons
        .where((p) => p['id'] == toId)
        .firstOrNull?['name'];
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_neutral,
                color: KinrelColors.textDim, size: 40),
            const SizedBox(height: 16),
            Text(
              'No connection found between $fromName and $toName.',
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'They may be in different branches of the family.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(graphFocusProvider.notifier).exitPathSelectMode();
              },
              child: const Text('Done',
                  style: TextStyle(color: KinrelColors.orange, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPathResultSheet(GraphKinshipPathFocus pathFocus, FlatGraphResult flat) {
    final fromName = flat.persons
        .where((p) => p['id'] == pathFocus.viewerPersonId)
        .firstOrNull?['name'] ?? 'Person';
    final toName = flat.persons
        .where((p) => p['id'] == pathFocus.targetPersonId)
        .firstOrNull?['name'] ?? 'Person';
    final kinshipLabel = pathFocus.resolvedRelationshipLabel ?? 'connected';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kinship term heading
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '$fromName is $kinshipLabel to $toName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Path steps
            ...pathFocus.steps.map((step) {
              final stepName = flat.persons
                  .where((p) => p['id'] == step.personId)
                  .firstOrNull?['name'] ?? 'Unknown';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 8, color: KinrelColors.orange.withOpacity(0.6)),
                    const SizedBox(width: 12),
                    Text(stepName,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14)),
                    if (step.relationshipType != null) ...[
                      const Spacer(),
                      Text(step.relationshipType!,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12)),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Reuse flutter_tts from path_finder_screen pattern.
                      try {
                        final tts = FlutterTts();
                        await tts.setLanguage('hi-IN');
                        await tts.speak('$fromName is $kinshipLabel to $toName');
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: const Text('Hear it spoken'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KinrelColors.orange,
                      side: BorderSide(
                          color: KinrelColors.orange.withOpacity(0.4)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(graphFocusProvider.notifier).exitPathSelectMode();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: KinrelColors.orange,
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
