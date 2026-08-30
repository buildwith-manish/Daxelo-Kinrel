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
    // v5.29 Fix 4: In rearrange mode, a new scale gesture starting
    // (finger down after a prior long-press) should NOT reset the drag
    // — it IS the drag. Do not clear _rearrangeDragId here.
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // v5.34: New workflow — NO SaveLockPill after each drag. The live
    // override stays in _rearrangeLiveNodeOverrides as an unsaved
    // change. The user clicks the persistent Save button in the top
    // toolbar to commit ALL changes at once.
    //
    // Just clear the drag state so the next gesture can start fresh.
    // The live override map entry persists (it's the unsaved change).
    if (_rearrangeDragId != null && _rearrangeDragKind == 'node') {
      _rearrangeDragKind = null;
      _rearrangeDragId = null;
      _rearrangePreDragPosition = null;
      _rearrangePreDragEdgeDelta = Offset.zero;
      _rearrangeDragRevision++;
      setState(() {});
      _isPinching = false;
      return;
    }

    // Normal camera fling — only on single-finger pan release.
    // v97: Never fling after a pinch — the velocity is unreliable
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
    // v5.29 Fix 4: REARRANGE NODE DRAG. When rearrange mode is active
    // and a node drag has been started (via onLongPressStart), the
    // Scale recognizer wins the gesture arena and fires onScaleUpdate
    // instead of onLongPressMoveUpdate. We intercept it here and
    // route finger movement to the node reposition logic instead of
    // panning the camera. Only single-finger movement routes to node
    // drag — a two-finger pinch still zooms normally even in
    // rearrange mode.
    if (_rearrangeDragId != null &&
        _rearrangeDragKind == 'node' &&
        d.pointerCount == 1) {
      final graphPos = _screenToGraphSpace(d.focalPoint);
      final newMap = Map<String, Offset>.from(_rearrangeLiveNodeOverrides);
      newMap[_rearrangeDragId!] = graphPos;
      _rearrangeLiveNodeOverrides = newMap;
      _rearrangeDragRevision++;
      _lastFocal = d.focalPoint;
      // v5.38: Mark that there are unsaved changes so the Save button
      // enables. Only set on the first move (avoid per-frame provider
      // writes — setting the same value is a no-op anyway).
      if (!ref.read(hasUnsavedChangesProvider)) {
        ref.read(hasUnsavedChangesProvider.notifier).state = true;
      }
      // v5.35: Debug logging (first move only — too noisy per frame otherwise).
      if (newMap.length == 1) {
        debugPrint('[v5.35 Drag] first move — node ${_rearrangeDragId} → $graphPos, liveMap size=${newMap.length}');
      }
      setState(() {});
      return;
    }

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

  /// v5.137: Geometric hit-test for branch chips.
  ///
  /// On Flutter Web, the parent GestureDetector's ScaleGestureRecognizer
  /// wins the gesture arena for any pointer sequence, so the branch chip's
  /// own onTap/onLongPress never fire (same bug that affected nodes before
  /// the v72 geometric hit-test fix).
  ///
  /// This method reproduces the chip's on-screen rect using the SAME
  /// geometry formula as _buildCollapsedBranchChips in branch_affordance.dart:
  ///   chipLeft = pos.dx + 40
  ///   chipTop = pos.dy + _kCircleCenterYOffset + 40 (+ 36px per collision)
  ///
  /// Returns the CollapsedBranch whose chip rect contains [screenPos],
  /// or null if no chip is hit.
  CollapsedBranch? _hitTestBranchChip(Offset screenPos, GraphLayoutResult layout) {
    if (_currentCollapsedBranches.isEmpty) return null;
    final graphPos = _screenToGraphSpace(screenPos);

    // Reproduce the chip placement logic from branch_affordance.dart.
    // We must use the SAME positions map the chip builder uses
    // (layout.positions, NOT _currentPositionsWithOffset) because the
    // chip builder uses layout.positions directly.
    final placedRects = <Rect>[];
    const chipWidth = 200.0;
    const chipHeight = 32.0;

    for (final branch in _currentCollapsedBranches) {
      final pos = layout.positions[branch.rootPersonId];
      if (pos == null) continue;

      final chipLeft = pos.dx + 40;
      var chipTop = pos.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset + 40;

      // Reproduce the collision-avoidance stacking
      while (placedRects.any((r) => r.overlaps(
          Rect.fromLTWH(chipLeft, chipTop, chipWidth, chipHeight)))) {
        chipTop += 36;
      }
      placedRects.add(Rect.fromLTWH(chipLeft, chipTop, chipWidth, chipHeight));

      // Check if the graph-space tap point falls inside this chip rect.
      // Use a slightly larger hit area (padding) for easier tapping.
      const hitPadding = 8.0;
      final hitRect = Rect.fromLTWH(
        chipLeft - hitPadding,
        chipTop - hitPadding,
        chipWidth + hitPadding * 2,
        chipHeight + hitPadding * 2,
      );
      if (hitRect.contains(graphPos)) {
        return branch;
      }
    }
    return null;
  }

  /// v91 (PART 13): Computes the set of edge IDs that should be dimmed
  /// when relationship focus mode is active.
  ///
  /// When a node is selected, DIRECTLY CONNECTED edges retain normal
  /// (or increased) clarity, while UNRELATED edges gently reduce
  /// opacity by ~30%. The selected edge (if any) and any sweep edge
  /// are never dimmed.
  ///
  /// v5.65 (ISOLATE CONNECTIONS): When a person is FOCUSED (via
  /// graphFocusProvider), the dimming now uses ONLY the focused
  /// person + their FIRST-DEGREE (direct) connections. Everything
  /// else — including 2nd-degree relatives — is dimmed to a low
  /// opacity (~18%). This is the "Isolate connections" feature:
  /// the user picks a person, and only that person + their direct
  /// relationships stay fully visible; the rest of the graph fades
  /// into the background to reduce visual noise.
  ///
  /// Previously (v95 Phase 1), the dimming kept 1st+2nd degree
  /// bright. The user found this too permissive — they wanted to
  /// see ONLY the direct connections, with everything else faded.
  /// The 2nd-degree set is still computed (used by GraphFocusState
  /// for other purposes like path focus) but is no longer used for
  /// dimming.
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
      // v5.66 (BUG 2 FIX): An edge stays bright ONLY if at least one
      // endpoint is the FOCUSED PERSON themselves — NOT just any
      // 1st-degree relative.
      //
      // Previously (v5.65), an edge stayed bright if EITHER endpoint was
      // in {focusedPerson ∪ firstDegreeIds}. This was too permissive:
      // when isolating MA (whose 1st-degree relatives include both JD
      // and HD), the JD↔HD spouse edge stayed bright because both JD
      // and HD were in the emphasised set — even though that edge does
      // NOT connect MA to anyone. The user reported this as "the
      // connection line between two dimmed, unrelated nodes does not
      // dim."
      //
      // The fix: only keep edges bright if they DIRECTLY involve the
      // focused person (sourceId == focusedPerson OR targetId ==
      // focusedPerson). Edges between two 1st-degree relatives (e.g.
      // JD↔HD when isolating MA) are now dimmed, matching the node
      // dimming (both JD and HD nodes are bright, but the edge between
      // them fades since it's not part of the focused person's direct
      // relationship circle).
      //
      // The NODE-level dimming (node_builders.dart) is unchanged: the
      // focused person + their 1st-degree neighbours stay at full
      // opacity. Only the EDGE dimming is stricter here.
      final connected = <String>{};
      for (final deduped in edges) {
        final e = deduped.edge;
        if (e.sourceId == focusedPerson || e.targetId == focusedPerson) {
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

    // v5.67 (BUG 1 FIX): The selection-based dimming fallback has been
    // REMOVED. Previously, when no person was focused (isolation off)
    // but a node was selected (selectedNodeProvider non-null), edges
    // NOT connected to the selected node were dimmed. This was a v91
    // behavior designed for a subtle 15% dim (dimAlpha was 0.85).
    //
    // With v5.65's stronger dimAlpha (0.18 = 82% reduction), this
    // fallback became too aggressive: after "Show all" cleared the
    // focus, the selectedNodeProvider still had a value (from the
    // long-press that opened the menu), so edges stayed dimmed even
    // though the user had exited isolation mode. The user reported:
    // "Show all restores nodes but not connection lines."
    //
    // The fix: node selection (tap) should ONLY highlight the node
    // visually — it should NOT dim edges. Edge dimming is now EXCLUSIVELY
    // driven by the Isolate Connections feature (focus mode). When no
    // person is focused, ALL edges are at full opacity.
    //
    // Returns null (nothing to dim) when no person is focused.
    return null;
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
    // v5.37: In Rearrange mode, suppress ALL tap interactions.
    // The only allowed interaction is dragging/repositioning nodes.
    // Tapping should NOT trigger Focus Mode, open profile details,
    // or perform any standard graph actions.
    if (ref.read(rearrangeModeProvider)) return;

    // v5.137: Branch chip hit-test FIRST. On Flutter Web, the chip's own
    // GestureDetector loses the gesture arena to the parent's
    // ScaleGestureRecognizer, so we must intercept chip taps here at the
    // parent level (same pattern as the v72 node hit-test fix).
    //
    // v5.137.2: DON'T expand immediately. Start a 500ms timer instead.
    // If the timer fires (no long-press happened), expand the branch.
    // If onLongPressStart fires first, it cancels the timer and opens
    // the action sheet. This is the reliable way to distinguish tap from
    // long-press on Flutter Web where the gesture arena is unreliable.
    //
    // v5.138.2: Guard against stale chip cache. If the branch is already
    // in expandedBranchRoots, DON'T start the expand timer — the chip is
    // gone and the user might be long-pressing the root NODE to collapse.
    final branch = _hitTestBranchChip(details.localPosition, layout);
    if (branch != null) {
      // v5.138.2: Skip if already expanded (stale cache / chip gone).
      final collapseState = ref.read(branchCollapseProvider);
      if (collapseState.expandedBranchRoots.contains(branch.rootPersonId)) {
        _pendingChipTapBranch = null;
        _chipExpandTimer?.cancel();
        // Fall through to node tap handler — the user might be tapping
        // the root node of an already-expanded branch.
      } else {
        _pendingChipTapBranch = branch;
        _chipExpandTimer?.cancel();
        _chipExpandTimer = Timer(const Duration(milliseconds: 500), () {
          // Timer fired — no long-press happened. Expand the branch.
          final b = _pendingChipTapBranch;
          _pendingChipTapBranch = null;
          if (b != null) {
            GraphHaptics.branchExpand(context);
            _fetchAndExpandBranch(b);
          }
        });
        return;
      }
    }

    _handleNodeTapDown(details, layout, flat, viewerPersonId);
  }

  /// v5.137: Fires when a quick tap is recognized (pointer released before
  /// the long-press threshold). Kept for backward compatibility but the
  /// actual chip expansion is now handled by the timer in _handleCanvasTapDown.
  void _handleCanvasTap() {
    if (ref.read(rearrangeModeProvider)) return;
    // v5.137.2: The timer-based approach in _handleCanvasTapDown handles
    // the expand. Cancel the pending timer here (pointer was released
    // quickly = tap, but the timer may not have fired yet).
    // Actually, DON'T cancel — let the timer fire. The timer is the
    // reliable signal. This method is kept as a no-op for the onTap
    // callback so Flutter's gesture arena doesn't complain.
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
    // v5.62: 50px screen-space touch target. Bumped from 48px for a
    // slightly more forgiving grab radius — the heart is visually
    // smaller than a circular dot, so a touch extra padding helps
    // mobile users grab it without having to pixel-aim. This is the
    // "invisible circular touch target of roughly 40-44px" the user
    // asked for (50px gives a small margin above that range).
    final hitRadius = 50.0 / safeZoom;

    // v5.59: Read the saved edge waypoints so the hit-test accounts for
    // the user's dragged control point position. Without this, the
    // hit-test always checks the LINEAR midpoint (the original center
    // between the two nodes), even when the control point has been
    // dragged far away from that center.
    final savedOverrides = ref
        .read(personalLayoutOverridesProvider(widget.familyId))
        .valueOrNull;
    final Map<String, Offset> allEdgeWaypoints = {
      ...?savedOverrides?.edgeWaypoints,
      ..._rearrangeLiveEdgeWaypoints,
    };

    // v5.66 (BUG 1 FIX): When multiple edges have the SAME visual
    // midpoint (which happens when couple-union-redirected parent→child
    // edges share the same union midpoint as their effective source),
    // the old tiebreaker (strict `dist < bestDist`) picked whichever
    // edge appeared FIRST in _currentEdges — which is non-deterministic
    // and could be the WRONG edge (e.g. tapping HD↔MA but getting
    // JD↔MA because JD→MA appeared first in the list).
    //
    // The fix: track ALL edges within the hit radius, then pick the one
    // whose ACTUAL (non-redirected, raw) source/target nodes are closest
    // to the tap point. This breaks the tie correctly: if the user taps
    // closer to HD's node than JD's, the HD→MA edge wins.
    //
    // We compute a "raw proximity score" = the distance from the tap
    // point to the NEAREST of the two raw endpoints (source or target,
    // BEFORE the couple-union redirect). The edge whose nearest raw
    // endpoint is closest to the tap wins.
    final candidates = <_EdgeHitCandidate>[];

    // v5.125 (Step 6): Compute the anchor-sector fan-outs + bow inputs
    // with the SAME cached state the painter renders from, so the tap
    // target is exactly the rendered curve's midpoint (never a stale
    // pre-fan-out position).
    final anchorFanOuts = EngineEdgePainter.computeAnchorSectorFanOuts(
      edges: _currentEdges,
      positions: _currentPositionsWithOffset,
      anchorId: _currentAnchorId,
      anchorCenter: _currentAnchorCenter,
    );

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
      // v5.62: Compute the EXACT visual midpoint — the SAME position
      // the painter renders the dot/heart marker at. This is the
      // single source of truth (EngineEdgePainter.computeVisualMidpoint),
      // shared between the painter and this hit-tester so they can
      // NEVER drift apart.
      final waypointDelta = allEdgeWaypoints[e.id] ?? Offset.zero;
      // v5.125 (Step 6): the TOTAL offset (parallel-edge lateralOffset +
      // anchor-sector fan-out) and the anchor center — identical to what
      // the painter's paint loop passes, keeping the marker and the tap
      // target at the same point.
      final visualMid = EngineEdgePainter.computeVisualMidpoint(
        resolved.source,
        resolved.target,
        lateralOffset:
            deduped.lateralOffset + (anchorFanOuts[e.id] ?? 0.0),
        waypointDelta: waypointDelta,
        anchorCenter: _currentAnchorCenter,
      );

      final dist = (visualMid - graphPos).distance;
      if (dist < hitRadius) {
        // v5.66: Compute the raw-endpoint proximity score for tiebreaking.
        // This is the distance from the tap to the NEAREST raw endpoint
        // (before the couple-union redirect). When two edges share the
        // same visual midpoint (e.g. HD→MA and JD→MA both redirect
        // through the HD-JD union midpoint), the one whose raw parent
        // node is closer to the tap wins.
        final rawSourceDist = (s - graphPos).distance;
        final rawTargetDist = (t - graphPos).distance;
        final rawProximity = rawSourceDist < rawTargetDist
            ? rawSourceDist
            : rawTargetDist;
        candidates.add(_EdgeHitCandidate(
          edgeId: e.id,
          midpointDist: dist,
          rawProximity: rawProximity,
        ));
      }
    }

    if (candidates.isEmpty) return null;

    // v5.66: Sort by (1) midpoint distance ascending, then (2) raw
    // endpoint proximity ascending. This means: pick the closest
    // midpoint; on ties, pick the edge whose raw endpoints are closest
    // to the tap. The raw proximity tiebreaker only matters when two
    // edges have nearly-identical midpoints (within 1px), which is the
    // couple-union redirect case.
    candidates.sort((a, b) {
      final midCompare = a.midpointDist.compareTo(b.midpointDist);
      if (midCompare.abs() > 0.5) return midCompare; // >0.5px difference
      // Midpoints are nearly identical — use raw proximity as tiebreaker.
      return a.rawProximity.compareTo(b.rawProximity);
    });

    return candidates.first.edgeId;
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
    //   • v5.64: "Change relationship" + "Remove relationship" action
    //     buttons (shown when familyId + edgeId + ref are all non-null
    //     AND the user has permission — admin/owner can edit any
    //     relationship, regular members can edit relationships that
    //     involve themselves).
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
      // v5.64: Pass the family ID, edge ID, and ref so the sheet can
      // show the "Change relationship" and "Remove relationship"
      // action buttons. Without these, the buttons are hidden (the
      // sheet falls back to display-only mode — used by the
      // path-focus view in relationship_view.dart which doesn't
      // edit a specific edge).
      familyId: widget.familyId,
      edgeId: e.id,
      ref: ref,
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

    // v5.74 (BUG 2 FIX): Removed the tap-to-zoom camera animation
    // entirely. The user reported that tapping a node causes a zoom
    // animation that "keeps going" or loops. The root cause was the
    // interaction between _maybeFocusCameraOnNode (which animates the
    // camera) and the 18s focus auto-timeout (which clears focus,
    // resetting _lastFocusedPersonId, causing the next rebuild to
    // re-animate).
    //
    // The Isolate Connections feature (long-press → "Isolate
    // connections") already handles the camera-centering use case
    // with its own timeout + cleanup. A simple tap should ONLY select
    // the node (visual highlight) — it should NOT move the camera.
    // The user can pan/zoom manually or use "Isolate connections" if
    // they want the camera to center on a specific node.
    //
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

    // v5.137: Branch chip hit-test FIRST. On Flutter Web, the chip's own
    // GestureDetector loses the gesture arena to the parent's
    // ScaleGestureRecognizer, so we must intercept chip long-presses here
    // at the parent level (same pattern as the v72 node hit-test fix).
    //
    // v5.137.2: Cancel the expand timer — the long-press was recognized,
    // so we should open the action sheet instead of expanding the branch.
    _chipExpandTimer?.cancel();
    _pendingChipTapBranch = null;
    final branch = _hitTestBranchChip(details.localPosition, layout);
    if (branch != null) {
      // Fire the SAME haptic + action sheet handler the chip's onLongPress
      // would have called.
      GraphHaptics.branchMenuOpen(context);
      _showBranchActionSheet(context, branch);
      return;
    }

    // v5.63 (ISSUE 2 FIX): NODE HIT-TEST RUNS FIRST, THEN EDGES.
    //
    // Previously the edge midpoint hit-test ran FIRST (50px radius),
    // which meant that long-pressing a node that happened to be near
    // a relationship line would open the EDGE sheet (RelationshipInfo)
    // instead of the NODE sheet (GraphQuickActions with "Relate to
    // another person"). The user reported that "holding a node does
    // not surface this 'relate to another person' action for all
    // nodes — only some" — those "some" were the nodes NOT near a
    // relationship line.
    //
    // The fix: check NODES first. If a node is under the finger,
    // open the node menu (which always includes "Relate to another
    // person" — see GraphQuickActions). Only when NO node is hit do
    // we fall through to the edge midpoint hit-test.
    //
    // This ensures long-pressing ANY node always opens the node's
    // context menu, regardless of how many relationship lines pass
    // near it.

    // ── 1. Node hit-test → open the member info bottom sheet ──────
    // Long-press is the ONLY gesture that opens the member information
    // bottom sheet. A normal tap selects / highlights the node only
    // (see [_handleNodeTapDown]) and must never open the info panel.
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId != null) {
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

      // v5.140: Check if this node is an EXPANDED branch root. If so,
      // pass BranchCollapseInfo to GraphQuickActions so the combined
      // sheet shows "Collapse this branch" + "Preview full names list"
      // as plain items in the same list as the standard actions.
      // If NOT an expanded branch root, branchCollapseInfo is null and
      // the sheet shows ONLY the standard actions (no branch items).
      final collapseState = ref.read(branchCollapseProvider);
      BranchCollapseInfo? branchInfo;
      if (collapseState.expandedBranchRoots.contains(nodeId)) {
        // Resolve visible branch members via BFS from rootPersonId.
        final visibleNames = _resolveExpandedBranchMemberNames(flat, nodeId);
        branchInfo = BranchCollapseInfo(
          onCollapse: () {
            // v5.140: Show confirmation dialog before collapsing.
            _showCollapseConfirmationDialog(context, nodeId, graphPersonData.name);
          },
          onPreviewNames: () {
            _showExpandedBranchNamesList(context, graphPersonData.name, visibleNames);
          },
        );
      }

      GraphQuickActions.show(
        context,
        graphPersonData,
        familyId: widget.familyId,
        isOwner: _canRemove,
        isSelf: isAnchor,
        ref: ref,
        onFocusPerson: _onFocusPerson,
        onViewRelationship: _onViewRelationship,
        branchCollapseInfo: branchInfo,
      );
      return;
    }

    // ── 2. Edge midpoint hit-test (opens Connection screen) ───────
    // Only reached when NO node was under the finger. The Connection
    // screen opens ONLY on long-press of the midpoint indicator
    // (dot/heart). This is deliberate: tapping the midpoint used to
    // open it, but that caused accidental opens when users were trying
    // to select a nearby node. Long-press is a more intentional gesture.
    final edgeId = _hitTestEdge(details.localPosition);
    if (edgeId != null) {
      _handleEdgeTap(edgeId, flat, viewerPersonId);
      return;
    }
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
      // v5.32 FIX: Previously this block EXITED Rearrange mode
      // (ref.read(rearrangeModeProvider.notifier).state = false)
      // as a "convenience shortcut" so the user could leave without
      // reaching for the toolbar toggle. But this was the ROOT CAUSE
      // of the context menu reappearing after repeated interactions:
      //
      // When a node was dragged to a new position (via a previous
      // drag+Save), the user's NEXT long-press might miss the node
      // (pressing where the node USED to be, or the hit-test radius
      // being too small for the new position). The miss triggered
      // this "empty canvas → exit" path, setting rearrangeModeProvider
      // to false. Then the NEXT long-press went through
      // _handleNodeLongPress WITHOUT the rearrange gate (because the
      // mode was now off), and opened GraphQuickActions — the context
      // menu the user reported seeing "after some time".
      //
      // The fix: DON'T exit Rearrange mode on empty canvas long-press.
      // The user exits via the explicit X toggle button. This is more
      // predictable and prevents unintentional mode exits from hit-test
      // misses. Just silently ignore the press.
      debugPrint('[v5.32 Rearrange] long-press missed all nodes — ignoring (not exiting rearrange mode)');
      return;
    }

    // v5.60: The viewer's OWN node must NOT be draggable in Rearrange
    // mode. It represents "you" and should stay anchored as the fixed
    // reference point other nodes are positioned relative to.
    final viewerPersonId = ref
        .read(viewerPersonIdProvider(widget.familyId))
        .valueOrNull;
    if (viewerPersonId != null && nodeId == viewerPersonId) {
      debugPrint('[v5.60 Rearrange] Cannot drag own node ($nodeId == viewer) — ignoring');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Your own node is locked and cannot be moved.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      // v5.39: Mark that there are unsaved changes so the Save (✓)
      // button enables. This is the path used by
      // onLongPressMoveUpdate (LongPressGestureRecognizer wins the
      // arena on mobile and some Flutter Web configs). The sibling
      // setter in _onScaleUpdate covers the alternate path where
      // ScaleGestureRecognizer wins. Setting both ensures the flag
      // flips to true regardless of which recognizer fires.
      if (!ref.read(hasUnsavedChangesProvider)) {
        ref.read(hasUnsavedChangesProvider.notifier).state = true;
      }
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
      // The LINEAR midpoint of the EFFECTIVE endpoints. The override
      // is stored relative to this position (NOT the visual midpoint).
      //
      // v5.62: This is correct because the painter's _bezier (waypoint
      // case) now uses a CUBIC bezier constructed so its t=0.5 point
      // (the visual midpoint, where the dot/heart is rendered) equals
      // EXACTLY `linearMid + waypointDelta`. So:
      //   - User drags finger to position X.
      //   - We store `delta = X - linearMid`.
      //   - Painter renders the curve with `waypointDelta = delta`.
      //   - The curve's visual midpoint = `linearMid + delta` = X.
      //   - The dot/heart appears EXACTLY where the finger is.
      //   - The hit-test (using computeVisualMidpoint) checks the same
      //     position, so the dot stays grabbable at every zoom level.
      //
      // v5.58–v5.61 used a QUADRATIC bezier, where the visual midpoint
      // was `linearMid + delta/2` — the dot lagged behind the finger
      // by half the drag distance, and the hit-test (which checked
      // `linearMid + delta`) was offset from the rendered dot by
      // `delta/2`. The cubic bezier eliminates this drift entirely.
      final trueMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );
      final delta = graphPos - trueMid;
      final newMap = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
      newMap[_rearrangeDragId!] = delta;
      _rearrangeLiveEdgeWaypoints = newMap;
      _rearrangeDragRevision++;
      // v5.39: Mark unsaved changes for edge-midpoint drags too —
      // previously only node drags flipped this flag (and only via
      // _onScaleUpdate). Edge drags are equally real layout changes
      // and must enable the Save button.
      if (!ref.read(hasUnsavedChangesProvider)) {
        ref.read(hasUnsavedChangesProvider.notifier).state = true;
      }
      setState(() {});
    }
  }

  /// Called from `_handleCompareDragEnd` while in Rearrange mode.
  /// v5.34: New workflow — just clears drag state. NO SaveLockPill.
  /// The live override stays as an unsaved change until the user
  /// clicks the persistent Save button in the top toolbar.
  void _handleRearrangeDragEnd(
    LongPressEndDetails details,
    GraphLayoutResult layout,
  ) {
    if (_rearrangeDragId == null || _rearrangeDragKind == null) return;

    // v5.34: Clear drag state so the next gesture can start fresh.
    // The live override map entry persists (it's the unsaved change).
    _rearrangeDragKind = null;
    _rearrangeDragId = null;
    _rearrangePreDragPosition = null;
    _rearrangePreDragEdgeDelta = Offset.zero;
    _rearrangeDragRevision++;
    setState(() {});
  }

  /// Save handler invoked by the SaveLockPill's Save button.
  /// Persists the live override for the active element to
  /// GraphLayoutState via LayoutOverridesService (RLS-gated), then
  /// clears the live override map (the saved overrides now reflect it)
  /// and hides the pill.
  Future<void> _handleRearrangeSave() async {
    final kind = _rearrangePillKind;
    final id = _rearrangePillId;
    if (kind == null || id == null) {
      _resetRearrangePill();
      return;
    }
    // v5.29 Fix 1: Hide the pill IMMEDIATELY before any async work so
    // the user gets instant feedback and a mid-save rebuild can't
    // re-show it. Also clear _rearrangePillKind + _rearrangePillId so
    // a rebuild during the await doesn't see a stale pill kind/id
    // and re-render the pill (which would let the user tap Save again).
    _rearrangePillVisible = false;
    _rearrangePillKind = null;
    _rearrangePillId = null;
    setState(() {});

    if (kind == 'node') {
      final pos = _rearrangeLiveNodeOverrides[id];
      if (pos != null) {
        await LayoutOverridesService.saveNodeOverride(
            ref, widget.familyId, id, pos);
        // v5.30 Issue 1: Wait for the provider to re-fetch and emit
        // the new persisted value (which includes this node's saved
        // override) BEFORE removing the live override entry. This
        // prevents the one-frame gap where neither the saved override
        // nor the live override is present, which would cause the node
        // to visually snap back to its auto-layout position.
        //
        // Without this await: saveNodeOverride calls
        // ref.invalidate(personalLayoutOverridesProvider) which starts
        // an async re-fetch. The await for saveNodeOverride returns
        // after the DB upsert + invalidate call (NOT after the re-fetch
        // completes). Then we immediately remove the live override —
        // but the provider's re-fetch may not have resolved yet, so
        // the canvas reads PersonalLayoutOverrides.empty for one frame
        // (or longer), and the node snaps back. The user sees this as
        // a "cancel," taps Save again, and this time the provider has
        // resolved so it holds.
        await ref.read(
            personalLayoutOverridesProvider(widget.familyId).future);
      }
      final newMap = Map<String, Offset>.from(_rearrangeLiveNodeOverrides);
      newMap.remove(id);
      _rearrangeLiveNodeOverrides = newMap;
    } else if (kind == 'edge') {
      final delta = _rearrangeLiveEdgeWaypoints[id];
      if (delta != null) {
        await LayoutOverridesService.saveEdgeWaypoint(
            ref, widget.familyId, id, delta);
        // v5.30 Issue 1: Same fix as for nodes above — wait for the
        // provider to resolve with the new persisted edge waypoint
        // BEFORE removing the live override entry. Prevents the curve
        // from visually snapping back to the default midpoint during
        // the async gap between invalidate and re-fetch completion.
        await ref.read(
            personalLayoutOverridesProvider(widget.familyId).future);
      }
      final newMap = Map<String, Offset>.from(_rearrangeLiveEdgeWaypoints);
      newMap.remove(id);
      _rearrangeLiveEdgeWaypoints = newMap;
    }
    // Clear drag state after DB write completes.
    _rearrangeDragKind = null;
    _rearrangeDragId = null;
    _rearrangePreDragPosition = null;
    _rearrangePreDragEdgeDelta = Offset.zero;
    _rearrangeDragRevision++;
    if (mounted) setState(() {});
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

/// v5.66 (BUG 1 FIX): Helper class for edge hit-testing tiebreaking.
/// When multiple edges share the same visual midpoint (due to
/// couple-union redirects), this holds the info needed to pick the
/// correct one based on raw endpoint proximity.
class _EdgeHitCandidate {
  const _EdgeHitCandidate({
    required this.edgeId,
    required this.midpointDist,
    required this.rawProximity,
  });

  final String edgeId;

  /// Distance from the tap to the edge's visual midpoint (the dot/heart
  /// position). Primary sort key — closer midpoints win.
  final double midpointDist;

  /// Distance from the tap to the NEAREST raw endpoint (before the
  /// couple-union redirect). Secondary sort key — when two edges have
  /// nearly-identical midpoints (within 0.5px), the one whose raw
  /// parent/child node is closest to the tap wins. This ensures tapping
  /// near HD's node picks the HD→MA edge, not the JD→MA edge (even when
  /// both redirect through the same HD-JD union midpoint).
  final double rawProximity;
}
