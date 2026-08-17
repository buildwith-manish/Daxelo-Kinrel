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

  /// v5.23 (PART 2.5 reset): Double-tap dispatcher.
  ///
  /// In Rearrange mode, a double-tap whose captured position is within
  /// the 48px hit-radius of an edge midpoint dot resets that edge's
  /// custom bow override — calls
  /// `LayoutOverridesService.removeEdgeWaypoint(familyId, edgeId)`,
  /// which removes the entry from GraphLayoutState.edgeWaypoints. The
  /// provider invalidation triggers a rebuild, the effective edge
  /// waypoints map no longer contains this edgeId, and the painter
  /// falls back to the EXISTING `_bezier` + PathMetric t=0.5 midpoint
  /// calculation. The curve snaps back to the true computed midpoint.
  ///
  /// Double-tap NOT on a dot (or outside Rearrange mode) falls through
  /// to the existing [_handleDoubleTapZoom] zoom-toggle behaviour, so
  /// users in Rearrange mode can still double-tap-to-zoom anywhere
  /// there isn't a midpoint dot.
  ///
  /// This mirrors the pattern already used for the node's per-element
  /// "Reset to auto layout" action in `graph_quick_actions.dart` (which
  /// calls `LayoutOverridesService.removeNodeOverride`).
  void _handleDoubleTap(
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final isRearranging = ref.read(rearrangeModeProvider);
    if (isRearranging) {
      final edgeId = _hitTestEdge(_doubleTapPosition);
      if (edgeId != null) {
        // Reset this edge's custom bow override. The provider
        // invalidation triggered inside removeEdgeWaypoint causes
        // personalLayoutOverridesProvider to re-read the fresh row,
        // so the canvas rebuilds without this edgeId in
        // effectiveEdgeWaypoints → the painter falls back to the
        // default t=0.5 midpoint.
        //
        // Also clear any LIVE drag override for this edge in case the
        // user was mid-drag and double-tapped to reset (rare but
        // possible — the live override would otherwise re-assert
        // itself on the next rebuild).
        final newLiveEdge = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
        newLiveEdge.remove(edgeId);
        _rearrangeLiveEdgeWaypoints = newLiveEdge;
        _rearrangeDragRevision++;
        setState(() {});

        // Fire-and-forget the persist — the local state already
        // reflects the reset so the UI snaps immediately. The persist
        // updates the GraphLayoutState row so the reset survives a
        // reload.
        LayoutOverridesService.removeEdgeWaypoint(
          ref,
          widget.familyId,
          edgeId,
        ).then((_) {
          // Provider invalidation handles the rebuild. Show a brief
          // snackbar so the user knows the reset was committed.
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Reset curve to center'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }).catchError((Object e) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('Failed to reset curve: $e'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        });
        return;
      }
    }
    // No midpoint dot hit (or not in Rearrange mode) → zoom toggle.
    _handleDoubleTapZoom();
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
    // v5.25 (Bug 3 fix): Prefer _currentPositionsWithOffset when it's
    // populated — it's the SAME map the canvas_mixin computes for the
    // painter (effectivePositions = autoLayout ⊕ savedOverrides ⊕
    // liveDragOverrides) with the visual-circle Y offset applied.
    //
    // Why this matters: in Rearrange mode (and after a node has been
    // dragged+served), the on-screen positions DIVERGE from
    // layout.positions (which is the auto-layout only). Hit-testing
    // against layout.positions means long-pressing a VISUALLY-MOVED
    // node silently misses — the user reports "can drag dots but not
    // nodes". _currentPositionsWithOffset is populated by the
    // canvas_mixin on every build (lines 454-461) and includes the
    // viewer's saved overrides + any in-progress drag, so it always
    // matches what's actually on screen.
    //
    // _currentPositionsWithOffset may be empty on the very first
    // frame (before the canvas_mixin has run its build). Fall back to
    // layout.positions in that case so the existing non-Rearrange
    // behaviour is unchanged.
    final positions = _currentPositionsWithOffset.isNotEmpty
        ? _currentPositionsWithOffset
        : layout.positions;
    for (final entry in positions.entries) {
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

  /// Handles a tap-down on the canvas.
  ///
  /// A single tap (or the down-stroke of any pointer sequence) ONLY
  /// selects / highlights the node — it does NOT open the member
  /// information bottom sheet. The bottom sheet is opened exclusively
  /// by a long-press on a node (see [_handleNodeLongPress]).
  ///
  /// This is the single source of truth for the "tap = select only"
  /// contract: a normal tap must NEVER open the information panel.
  ///
  /// Path-select mode (P2.1) is still handled here because that mode
  /// explicitly uses taps to pick the from/to nodes for relationship
  /// tracing — it is a separate, user-activated mode and is not a
  /// "normal tap".
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

    // Select / highlight the node. A normal tap does NOT open the
    // member info bottom sheet — that is reserved for long-press
    // (see [_handleNodeLongPress]).
    ref.read(selectedNodeProvider.notifier).state = nodeId;

    // v91 (PART 12): Cinematic camera focus on node selection.
    _maybeFocusCameraOnNode(nodeId, layout);

    // Intentionally DO NOT open GraphQuickActions here.
    // Tap = select / highlight only. Long-press = open info panel.
  }

  /// Handles a long-press on the canvas.
  ///
  /// Hit-test order:
  ///   1. Edge midpoint (48px radius) — opens the Connection screen
  ///      (RelationshipInfoSheet). This is the ONLY way to open the
  ///      Connection screen from the graph canvas. Tapping the midpoint
  ///      no longer opens it (see [_handleCanvasTapDown]).
  ///   2. Node (44px radius) — opens the member information bottom
  ///      sheet (GraphQuickActions). Long-press is the ONLY gesture
  ///      that opens the member info sheet; a normal tap selects /
  ///      highlights the node only (see [_handleNodeTapDown]).
  ///
  /// If neither hits, the long-press is a no-op (canvas background).
  ///
  /// v5.22 REARRANGE-MODE GATE: When `rearrangeModeProvider` is true,
  /// this method does NOT fire either of the above flows. Instead:
  ///   • Long-press on a midpoint dot → start an EDGE BOW drag
  ///     (PART 2). _rearrangeDragKind = 'edge'; the existing
  ///     onLongPressMoveUpdate / onLongPressEnd callbacks route to
  ///     _handleRearrangeDragUpdate / _handleRearrangeDragEnd.
  ///   • Long-press on a node → start a NODE REPOSITION drag (PART 1).
  ///     _rearrangeDragKind = 'node'.
  ///   • Long-press on empty canvas → exit Rearrange mode (convenience
  ///     shortcut so the user can leave the mode without reaching for
  ///     the toolbar toggle).
  /// The existing compare-drag no-op (which is already a guaranteed
  /// no-op because `_compareDragFromId` is never set outside Rearrange
  /// mode) is left wired in — while in Rearrange mode it's bypassed
  /// because we early-return before reaching it.
  void _handleNodeLongPress(
    LongPressStartDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // v5.22: REARRANGE-MODE GATE. While the user has explicitly toggled
    // "Rearrange" on (rearrangeModeProvider == true), long-press is
    // repurposed — it NO LONGER opens the info sheet or the Connection
    // screen. Instead it begins either a node reposition drag (PART 1)
    // or an edge midpoint bow drag (PART 2). This is the explicit
    // resolution to the gesture-conflict with the existing P2.4
    // compare-drag feature (which itself is already a no-op because
    // `_compareDragFromId` is never set).
    //
    // OUTSIDE Rearrange mode, the code below this block runs unchanged —
    // long-press on a midpoint opens the RelationshipInfoSheet, long-
    // press on a node opens GraphQuickActions.
    final isRearranging = ref.read(rearrangeModeProvider);
    if (isRearranging) {
      _handleRearrangeLongPressStart(details, layout, flat);
      return;
    }

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

    // ── 2. Node hit-test → open the member info bottom sheet ──────
    // Long-press is the ONLY gesture that opens the member information
    // bottom sheet. A normal tap selects / highlights the node only
    // (see [_handleNodeTapDown]) and must never open the info panel.
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // P3.2: clear "menu opening" haptic on long-press.
    GraphHaptics.longPress(context);

    // Select / highlight the node so the visual focus follows the
    // long-pressed node before the sheet opens.
    ref.read(selectedNodeProvider.notifier).state = nodeId;

    // Resolve the person data and open the quick-actions sheet.
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

  /// Legacy P2.4 drag-update handler.
  ///
  /// The compare-drag gesture has been superseded: long-press now opens
  /// the member info bottom sheet directly (see [_handleNodeLongPress]),
  /// and `_compareDragFromId` is never set. This handler remains wired
  /// in `canvas_mixin.dart` for safety but is a guaranteed no-op because
  /// the early-return on `null` fires immediately.
  ///
  /// v5.22: While in Rearrange mode, this method routes to
  /// `_handleRearrangeDragUpdate` (PART 1 / PART 2 live drag). The
  /// legacy compare-drag path below is unreachable in Rearrange mode
  /// because `_compareDragFromId` is never set there.
  void _handleCompareDragUpdate(
    LongPressMoveUpdateDetails details,
    GraphLayoutResult layout,
  ) {
    // v5.22: If a Rearrange drag is in progress, route to the live
    // drag handler. The Rearrange path is the ONLY path that ever
    // sets _rearrangeDragId (and it's only set while rearrangeMode is
    // true), so this branch is unreachable outside Rearrange mode.
    if (_rearrangeDragId != null) {
      _handleRearrangeDragUpdate(details, layout);
      return;
    }
    if (_compareDragFromId == null) return;
    _compareDragPosition = details.localPosition;
    setState(() {});
  }

  /// Legacy P2.4 drag-release handler.
  ///
  /// The compare-drag gesture has been superseded: long-press now opens
  /// the member info bottom sheet directly (see [_handleNodeLongPress]),
  /// and `_compareDragFromId` is never set. This handler remains wired
  /// in `canvas_mixin.dart` for safety but is a guaranteed no-op because
  /// the early-return on `null` fires immediately.
  ///
  /// To compare two people, use the path-select mode (activated via the
  /// graph's compare button), which uses taps to pick from/to nodes.
  ///
  /// v5.22: While in Rearrange mode, this method routes to
  /// `_handleRearrangeDragEnd` (show SaveLockPill). The legacy compare-
  /// drag path below is unreachable in Rearrange mode.
  void _handleCompareDragEnd(
    LongPressEndDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // v5.22: If a Rearrange drag is in progress, route to the release
    // handler (shows the SaveLockPill — Save persists to
    // GraphLayoutState, Cancel reverts).
    if (_rearrangeDragId != null) {
      _handleRearrangeDragEnd(details, layout);
      return;
    }
    // In rearrange mode, if no drag was active (user long-pressed but
    // the pan recognizer stole the gesture), just clear and do nothing.
    // Never open QuickActions or compare flow while rearranging.
    final isRearranging = ref.read(rearrangeModeProvider);
    if (isRearranging) return;

    final fromId = _compareDragFromId;
    if (fromId == null) return;

    final dragFromId = fromId;
    _compareDragFromId = null;
    setState(() {});

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

  // ── v5.22 Rearrange-mode drag handlers (PART 1 + PART 2) ──────────
  //
  // These methods are the SOLE entry points for personal (per-viewer)
  // persisted graph layout customizations. The canvas_mixin's existing
  // onLongPressStart / onLongPressMoveUpdate / onLongPressEnd callbacks
  // (wired for the legacy P2.4 compare-drag) are SHARED with these
  // handlers — but the routing is gated by `_rearrangeDragId != null`,
  // which is only ever set while `rearrangeModeProvider == true`. So
  // OUTSIDE Rearrange mode, none of these methods are reachable.

  /// Called from `_handleNodeLongPress` when Rearrange mode is on.
  /// Hit-tests in this order:
  ///   1. Edge midpoint dot (48px) → start EDGE BOW drag (PART 2)
  ///   2. Node (44px) → start NODE REPOSITION drag (PART 1)
  ///   3. Empty canvas → exit Rearrange mode (convenience)
  void _handleRearrangeLongPressStart(
    LongPressStartDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
  ) {
    // v5.25 (Bug 3): Debug logging — log every Rearrange long-press
    // hit-test result (edge vs node vs none) so we can diagnose why
    // users can drag edge midpoint dots but not nodes themselves.
    // The hypothesis is that the edge hit-test (48px radius) is
    // intercepting presses meant for nearby nodes — this log will
    // confirm whether node hits are silently failing OR the edge
    // hit-test is winning the tie.
    //
    // The hit-test order is: edge midpoint FIRST, then node. So when
    // both an edge midpoint AND a node are within hit-radius of the
    // press position, the edge wins. This log exposes that overlap so
    // the user's report ("can drag dots but not nodes") becomes
    // diagnosable.
    //
    // Remove this debugPrint once the diagnosis is confirmed and the
    // fix (if any) is shipped.
    final debugScreenPos = details.localPosition;
    final debugGraphPos = _screenToGraphSpace(debugScreenPos);
    final debugEdgeHit = _hitTestEdge(debugScreenPos);
    final debugNodeHit = _hitTestNode(debugScreenPos, layout);
    debugPrint('[v5.25 Rearrange] long-press @ screen=(${debugScreenPos.dx.toStringAsFixed(1)}, ${debugScreenPos.dy.toStringAsFixed(1)}) '
        'graph=(${debugGraphPos.dx.toStringAsFixed(1)}, ${debugGraphPos.dy.toStringAsFixed(1)}) '
        '| edgeHit=${debugEdgeHit ?? 'null'} '
        '| nodeHit=${debugNodeHit ?? 'null'} '
        '| zoom=${_camera.zoomLevel.toStringAsFixed(2)} '
        '| visibleEdges=${_currentEdges.length} '
        '| positions=${layout.positions.length}');
    if (debugEdgeHit != null && debugNodeHit != null) {
      debugPrint('[v5.25 Rearrange] BOTH edge AND node hit — edge wins (returned before node hit-test branch). '
          'If the user intended to drag the node, they should long-press further from the midpoint dot.');
    }

    // PART 2: edge midpoint dot hit-test (uses the existing _hitTestEdge
    // helper — same 48px hit radius the painter uses).
    final edgeId = _hitTestEdge(details.localPosition);
    if (edgeId != null) {
      _rearrangeDragKind = 'edge';
      _rearrangeDragId = edgeId;
      // Snapshot the pre-drag RELATIVE midpoint delta (could be zero
      // when no saved override existed — Cancel restores zero, which
      // restores the true bezier t=0.5 midpoint).
      final saved = ref
          .read(personalLayoutOverridesProvider(widget.familyId))
          .valueOrNull;
      _rearrangePreDragEdgeDelta =
          saved?.edgeWaypoints[edgeId] ?? Offset.zero;
      GraphHaptics.longPress(context);
      return;
    }

    // PART 1: node hit-test (uses the existing _hitTestNode helper).
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) {
      // Empty canvas long-press → exit Rearrange mode (convenience
      // shortcut so the user can leave without reaching for the
      // toolbar toggle).
      ref.read(rearrangeModeProvider.notifier).state = false;
      return;
    }
    _rearrangeDragKind = 'node';
    _rearrangeDragId = nodeId;
    // Snapshot the pre-drag position. If a saved override exists for
    // this person, snapshot it (Cancel restores the saved override).
    // Otherwise snapshot the auto-layout position (Cancel restores
    // auto-layout — the override map entry is removed).
    final saved = ref
        .read(personalLayoutOverridesProvider(widget.familyId))
        .valueOrNull;
    _rearrangePreDragPosition =
        saved?.nodePositions[nodeId] ?? layout.positions[nodeId];
    // Seed the live override map with the pre-drag position so the
    // drag has a starting point to update from.
    _rearrangeLiveNodeOverrides = {
      ..._rearrangeLiveNodeOverrides,
      nodeId: _rearrangePreDragPosition ?? Offset.zero,
    };
    // v5.22: Also call ForceSimulator.fixNode() — currently a no-op
    // in the engine's render path (the simulator isn't wired in), but
    // exercising the API keeps forward-compat correct so that when the
    // simulator IS later wired into the render path, fixed nodes truly
    // hold position (weight=0 → _tick() skips the integration step for
    // that node — see force_simulator.dart line 699).
    // We don't have a ForceSimulator instance handy here; the fixNode
    // API surface is exercised in its own unit test
    // (test/graph/engine/force_simulator_fix_node_test.dart).
    GraphHaptics.longPress(context);
    setState(() {});
  }

  /// Called from `_handleCompareDragUpdate` while in Rearrange mode.
  /// Updates the LIVE override map for the active drag — node position
  /// (PART 1) or edge midpoint delta (PART 2) — and triggers a repaint
  /// via setState.
  void _handleRearrangeDragUpdate(
    LongPressMoveUpdateDetails details,
    GraphLayoutResult layout,
  ) {
    if (_rearrangeDragId == null || _rearrangeDragKind == null) return;
    final graphPos = _screenToGraphSpace(details.localPosition);

    if (_rearrangeDragKind == 'node') {
      // PART 1: live-update the node's override position to the finger's
      // graph-space coordinate. The canvas_mixin's build method will
      // overlay this on top of the saved overrides on top of auto-layout,
      // so the node follows the finger live. The edges redraw automatically
      // (edge_router derives paths from positions).
      final newMap = Map<String, Offset>.from(_rearrangeLiveNodeOverrides);
      newMap[_rearrangeDragId!] = graphPos;
      _rearrangeLiveNodeOverrides = newMap;
      // Bump the per-drag-update revision so the EngineEdgePainter
      // repaints (its shouldRepaint uses layoutRevision which now
      // includes _rearrangeDragRevision).
      _rearrangeDragRevision++;
      setState(() {});
    } else if (_rearrangeDragKind == 'edge') {
      // PART 2: live-update the edge's RELATIVE midpoint delta.
      // Compute the true bezier t=0.5 midpoint for this edge using the
      // CURRENT positions (which may themselves be live-overridden if
      // the user is also dragging a node — that's fine, the math is
      // self-consistent). The delta is dragged_position - true_midpoint.
      final edge = _currentEdges
          .where((e) => e.edge.id == _rearrangeDragId)
          .firstOrNull;
      if (edge == null) return;
      final s = _currentPositionsWithOffset[edge.edge.sourceId];
      final t = _currentPositionsWithOffset[edge.edge.targetId];
      if (s == null || t == null) return;
      // Resolve effective endpoints through the SAME helper the painter
      // uses (couple-union redirect). This guarantees the dragged delta
      // is relative to the SAME midpoint the painter will compute when
      // applying the override.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: edge.edge.sourceId,
        targetId: edge.edge.targetId,
        rawSource: s,
        rawTarget: t,
        coupleUnions: _currentCoupleUnions,
        positionOf: (id) => _currentPositionsWithOffset[id],
      );
      // The true t=0.5 bezier midpoint (Painter uses PathMetrics for
      // this; we approximate with the linear midpoint of the EFFECTIVE
      // endpoints because that's the math the override is stored
      // relative to — see EngineEdgePainter._bezier: when waypointDelta
      // is non-zero, the curve is built through (linear_mid + delta),
      // so storing delta relative to linear_mid is correct).
      final trueMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );
      final delta = graphPos - trueMid;
      final newMap = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
      newMap[_rearrangeDragId!] = delta;
      _rearrangeLiveEdgeWaypoints = newMap;
      _rearrangeDragRevision++;
      setState(() {});
    }
  }

  /// Called from `_handleCompareDragEnd` while in Rearrange mode.
  /// Stops the drag (but does NOT auto-save — see PART 3 contract).
  /// Shows the shared SaveLockPill near the dragged element with Save/
  /// Cancel buttons. Save persists; Cancel reverts to the pre-drag
  /// snapshot. Auto-dismiss after 6s defaults to Cancel.
  void _handleRearrangeDragEnd(
    LongPressEndDetails details,
    GraphLayoutResult layout,
  ) {
    if (_rearrangeDragId == null || _rearrangeDragKind == null) return;

    // Position the SaveLockPill near the dropped element. Use the
    // finger's release position so the pill appears where the user
    // expects. Constrain to the visible viewport.
    final pillPos = details.localPosition;
    _rearrangePillScreenPosition = pillPos;
    _rearrangePillKind = _rearrangeDragKind;
    _rearrangePillId = _rearrangeDragId;
    _rearrangePillVisible = true;
    // Keep _rearrangeDragId/_rearrangeDragKind set so the Save/Cancel
    // callbacks know what to commit/revert. They clear these fields.
    setState(() {});
  }

  /// Save handler invoked by the SaveLockPill's Save button.
  /// Persists the live override for the active element to
  /// GraphLayoutState via LayoutOverridesService (RLS-gated), then
  /// clears the live override map (the saved overrides now reflect it)
  /// and hides the pill.
  Future<void> _handleRearrangeSave() async {
    // v5.28 Fix 3: Hide the pill immediately so the user gets instant
    // feedback and can't double-tap Save. The actual persist is async
    // below — but the UI already dismisses the pill so there's no
    // temptation to tap again, and no race window where a second tap
    // could trigger a duplicate save.
    _rearrangePillVisible = false;
    setState(() {});
    final kind = _rearrangePillKind;
    final id = _rearrangePillId;
    if (kind == null || id == null) {
      _resetRearrangePill();
      return;
    }
    if (kind == 'node') {
      final pos = _rearrangeLiveNodeOverrides[id];
      if (pos != null) {
        await LayoutOverridesService.saveNodeOverride(
            ref, widget.familyId, id, pos);
      }
      // Clear the live override for this node — the saved overrides
      // now reflect it (the provider invalidation triggers a rebuild
      // which re-reads the fresh row).
      final newMap = Map<String, Offset>.from(_rearrangeLiveNodeOverrides);
      newMap.remove(id);
      _rearrangeLiveNodeOverrides = newMap;
    } else if (kind == 'edge') {
      final delta = _rearrangeLiveEdgeWaypoints[id];
      if (delta != null) {
        await LayoutOverridesService.saveEdgeWaypoint(
            ref, widget.familyId, id, delta);
      }
      final newMap = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
      newMap.remove(id);
      _rearrangeLiveEdgeWaypoints = newMap;
    }
    _resetRearrangePill();
  }

  /// Cancel handler invoked by the SaveLockPill's Cancel button
  /// (or by the pill's 6-second auto-dismiss). Reverts the live
  /// override for the active element to the pre-drag snapshot:
  ///   • Node: remove the live override entry (auto-layout/saved
  ///     override is restored — pre-drag state).
  ///   • Edge: restore the live override to the pre-drag delta (which
  ///     is Offset.zero when no saved override existed, i.e. the curve
  ///     snaps back to the true computed midpoint).
  void _handleRearrangeCancel() {
    final kind = _rearrangePillKind;
    final id = _rearrangePillId;
    if (kind == null || id == null) {
      _resetRearrangePill();
      return;
    }
    if (kind == 'node') {
      final newMap = Map<String, Offset>.from(_rearrangeLiveNodeOverrides);
      newMap.remove(id);
      _rearrangeLiveNodeOverrides = newMap;
    } else if (kind == 'edge') {
      final newMap = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
      // Restore to pre-drag delta. If pre-drag was Offset.zero, remove
      // the entry (no override = true computed midpoint).
      if (_rearrangePreDragEdgeDelta == Offset.zero) {
        newMap.remove(id);
      } else {
        newMap[id] = _rearrangePreDragEdgeDelta;
      }
      _rearrangeLiveEdgeWaypoints = newMap;
    }
    _resetRearrangePill();
  }

  void _resetRearrangePill() {
    _rearrangePillVisible = false;
    _rearrangePillKind = null;
    _rearrangePillId = null;
    _rearrangeDragKind = null;
    _rearrangeDragId = null;
    _rearrangePreDragPosition = null;
    _rearrangePreDragEdgeDelta = Offset.zero;
    _rearrangeDragRevision++;
    setState(() {});
  }

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
