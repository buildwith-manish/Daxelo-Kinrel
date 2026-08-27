// lib/graph/widgets/engine/canvas_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains the _buildCanvas method — too large for the main file.

part of '../family_graph_engine_view.dart';

/// Mixin containing the canvas builder for _FamilyGraphEngineViewState.
/// Extracted to keep the main file under 1,500 lines.
extension _CanvasMethods on _FamilyGraphEngineViewState {
  Widget _buildCanvas(
      GraphLayoutResult layout, FlatGraphResult flat, String? viewerPersonId,
      {required PersonalLayoutOverrides savedOverrides,
      required bool rearrangeMode}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // v109.8: Fix keyboard/half-screen layout break.
        //
        // ROOT CAUSE: The previous code used a 25% height-shrink heuristic
        // to detect "keyboard push" and skipped updating _viewportSize.
        // This was WRONG for two reasons:
        //   1. On Flutter Web in half-screen/split-screen mode, the viewport
        //      genuinely shrinks by >25% — but this is a REAL resize, not a
        //      keyboard push. Skipping it meant the graph kept using stale
        //      (larger) viewport dimensions, causing overflow + white gaps.
        //   2. On Flutter Web, the on-screen keyboard doesn't resize the
        //      browser viewport — it overlays on top. So `viewInsets.bottom`
        //      is the correct signal, not a height-shrink heuristic.
        //
        // FIX: Always update _viewportSize to the actual constraints.
        // The graph's Scaffold has `resizeToAvoidBottomInset: false`
        // (line 208 of family_graph_screen.dart), so the body constraints
        // don't shrink when the keyboard opens on mobile. On web, the
        // keyboard doesn't resize the viewport at all. So we can safely
        // always use the real constraints.
        final newHeight = constraints.biggest.height;
        final newWidth = constraints.biggest.width;
        final sizeChanged = _viewportSize.width != newWidth ||
            _viewportSize.height != newHeight;
        _viewportSize = constraints.biggest;
        // v4.4: Push viewport size + safe area to the camera so it can
        // clamp panning and keep nodes fully visible.
        _camera.setViewportSize(_viewportSize);
        _camera.setSafeAreaInsets(MediaQuery.of(context).padding);
        // v4.8: Pass the app's own bottom UI chrome height (stats panel +
        // toolbar + FAB area) so fitToView centers content above the overlay.
        // Measured from family_graph_screen.dart: stats ~40 + toolbar 56 +
        // margins ~24 = ~120px. This prevents single-node graphs (brand-new
        // families) from being centered behind the bottom stats card.
        // v4.10: Use the REAL bottom/top chrome height passed from
        // family_graph_screen.dart via the widget constructor, instead of
        // hardcoded constants. This ensures fitToView centers content using
        // the actual overlay geometry (stats panel + toolbar + OS safe area).
        _camera.setAppBottomChromeHeight(widget.bottomChromeHeight);
        _camera.setAppTopChromeHeight(widget.topChromeHeight);
        // Invalidate the culler on any size change so the visible node
        // set is recomputed for the new viewport dimensions.
        if (sizeChanged) {
          _culler.invalidate();
        }

        // v5.22 (PART 1 + PART 2): Apply the viewer's saved personal
        // overrides (saved nodePositions + saved edgeWaypoints) on top
        // of the auto-computed layout positions, then layer any LIVE
        // drag deltas on top of THAT. The order is:
        //
        //   effectivePositions =
        //     autoLayout ⊕ savedOverrides.nodePositions ⊕ _rearrangeLiveNodeOverrides
        //
        //   effectiveEdgeWaypoints =
        //     savedOverrides.edgeWaypoints ⊕ _rearrangeLiveEdgeWaypoints
        //
        // LIVE overrides take precedence (the user is actively dragging
        // — the finger position is the truth). SAVED overrides come next
        // (last committed drag). Auto-layout fills in everything else.
        //
        // When NOT in Rearrange mode, the live maps are guaranteed
        // empty (see _handleRearrangeDragEnd's cleanup), so this
        // reduces to `autoLayout ⊕ savedOverrides`.
        //
        // When the viewer has no saved overrides at all (the normal
        // case — most viewers never customize their graph layout),
        // this reduces to `autoLayout` unchanged — no regression.
        //
        // Declared HERE at the top of the builder (not later) so the
        // camera content-bounds computation below can use it to
        // include any repositioned nodes in its bounding box —
        // otherwise panning would feel wrong if a node was dragged
        // outside the original auto-layout bounds.
        final Map<String, Offset> effectivePositions =
            savedOverrides.applyTo(layout.positions);
        // Layer the live drag deltas on top (only non-empty while a
        // drag is in progress in Rearrange mode).
        if (_rearrangeLiveNodeOverrides.isNotEmpty) {
          effectivePositions.addAll(_rearrangeLiveNodeOverrides);
        }
        final Map<String, Offset> effectiveEdgeWaypoints = {
          ...savedOverrides.edgeWaypoints,
          ..._rearrangeLiveEdgeWaypoints,
        };

        // v5.30 Issue 2: Load animation lerp.
        //
        // On first render with non-empty saved overrides, animate every
        // node from its auto-layout origin to its saved override
        // position over ~500ms easeOutCubic. This prevents the "snap or
        // flash" where nodes briefly appear at auto-layout before
        // jumping to saved positions.
        //
        // The lerp is FROM layout.positions (auto-layout) TO
        // effectivePositions (which includes saved overrides + live drag
        // overrides). At progress=0, all nodes are at auto-layout. At
        // progress=1, nodes with overrides are at their saved positions
        // and nodes without overrides stay at auto-layout (unchanged).
        //
        // Edges redraw automatically each frame since they derive paths
        // from positions (no separate edge animation needed).
        //
        // The _hasPlayedLoadAnimation one-time flag (set in
        // _maybeStartLoadAnimation) ensures this only fires once per
        // session load, not on every rebuild.
        //
        // Reduced-motion: _maybeStartLoadAnimation never sets
        // _animatingLoad=true if reduced motion is active, so this block
        // is a no-op.
        if (_animatingLoad && _loadController != null) {
          final rawProgress = _loadController!.value.clamp(0.0, 1.0);
          // easeOutCubic: 1 - (1 - t)^3
          final easedProgress = 1.0 -
              (1.0 - rawProgress) *
                  (1.0 - rawProgress) *
                  (1.0 - rawProgress);
          // Lerp from auto-layout (layout.positions) to effectivePositions
          // (which already includes saved overrides). Nodes without saved
          // overrides lerp from themselves to themselves (no visible
          // change), which is correct.
          final lerpedLoadPositions = <String, Offset>{};
          for (final entry in effectivePositions.entries) {
            final auto = layout.positions[entry.key];
            if (auto != null) {
              lerpedLoadPositions[entry.key] = Offset(
                auto.dx * (1.0 - easedProgress) +
                    entry.value.dx * easedProgress,
                auto.dy * (1.0 - easedProgress) +
                    entry.value.dy * easedProgress,
              );
            } else {
              lerpedLoadPositions[entry.key] = entry.value;
            }
          }
          effectivePositions
            ..clear()
            ..addAll(lerpedLoadPositions);
          // Edge waypoints don't need lerp during load — they start at
          // their saved values (no "from" state to lerp from, since the
          // user hasn't dragged anything yet on first load).
        }

        // v5.27 Task 1: Reset animation lerp.
        //
        // If a reset animation is in progress (_animatingReset is true),
        // lerp EVERY effective position + edge waypoint from its
        // pre-reset value to its post-reset (auto-layout) value by
        // _resetController.value (0.0→1.0 with Curves.easeOutCubic).
        //
        // The pre-reset snapshot (_preResetPositions +
        // _preResetEdgeWaypoints) was captured by _onResetTrigger
        // BEFORE the provider invalidation, so it includes the saved
        // overrides + live drag overrides that were in effect at trigger
        // time. The auto-layout positions are in `layout.positions`
        // (which always reflects the pure auto-layout — the saved
        // overrides are layered on top via savedOverrides.applyTo).
        //
        // Lerp math:
        //   effectivePosition = lerp(preReset, autoLayout, progress)
        //     = preReset * (1 - progress) + autoLayout * progress
        //   effectiveEdgeWaypoint = lerp(preResetDelta, Offset.zero, progress)
        //     = preResetDelta * (1 - progress)  (since (0,0) * progress = (0,0))
        //
        // Edges redraw automatically each frame since they derive paths
        // from positions (no separate edge animation needed).
        //
        // When the animation completes (_onResetAnimationStatus), the
        // state class clears _preResetPositions + _preResetEdgeWaypoints
        // and sets _animatingReset=false, so this block becomes a
        // no-op and effectivePositions falls back to pure auto-layout
        // (which is the correct post-reset state — savedOverrides is
        // empty after the provider invalidation).
        if (_animatingReset &&
            _preResetPositions != null &&
            _resetController != null) {
          // Convert the raw controller value through easeOutCubic so
          // the lerp feels weighted, not linear. The controller's
          // duration is already 350ms flat (not scaled per node count).
          final rawProgress = _resetController!.value.clamp(0.0, 1.0);
          // easeOutCubic: 1 - (1 - t)^3 — accelerates-decelerates.
          final easedProgress = 1.0 - (1.0 - rawProgress) * (1.0 - rawProgress) * (1.0 - rawProgress);
          // Lerp positions: for each personId, lerp from its pre-reset
          // position (if captured) to its auto-layout position. Persons
          // not in the pre-reset snapshot (rare — added between the
          // capture and the rebuild) just use the auto-layout.
          final lerpedPositions = <String, Offset>{};
          for (final entry in layout.positions.entries) {
            final pre = _preResetPositions![entry.key];
            if (pre != null) {
              lerpedPositions[entry.key] = Offset(
                pre.dx * (1.0 - easedProgress) +
                    entry.value.dx * easedProgress,
                pre.dy * (1.0 - easedProgress) +
                    entry.value.dy * easedProgress,
              );
            } else {
              lerpedPositions[entry.key] = entry.value;
            }
          }
          effectivePositions
            ..clear()
            ..addAll(lerpedPositions);
          // Lerp edge waypoints: each pre-reset delta fades linearly
          // toward (0,0) — i.e. effectiveDelta = preDelta * (1-progress).
          // Edges NOT in the pre-reset snapshot just use their current
          // value (which would be the auto-layout's default midpoint,
          // since savedOverrides is now empty after invalidation).
          if (_preResetEdgeWaypoints != null &&
              _preResetEdgeWaypoints!.isNotEmpty) {
            final lerpedWaypoints = <String, Offset>{};
            for (final entry in _preResetEdgeWaypoints!.entries) {
              lerpedWaypoints[entry.key] = Offset(
                entry.value.dx * (1.0 - easedProgress),
                entry.value.dy * (1.0 - easedProgress),
              );
            }
            effectiveEdgeWaypoints
              ..clear()
              ..addAll(lerpedWaypoints);
          } else {
            effectiveEdgeWaypoints.clear();
          }
        }

        // v4.5: Push content bounds to the camera (bounding box of all
        // node positions + expanded node size including visual effects).
        // Uses 220×256 (base 140×176 + glow/shadow/badges/indicators)
        // so pan clamping accounts for ALL visual elements, not just the
        // node circle. This ensures nodes are never partially clipped.
        if (effectivePositions.isNotEmpty) {
          const nodeWidth = 220.0;   // 140 base + 40 glow/shadow + 40 indicators
          const nodeHeight = 256.0;  // 176 base + 40 glow/shadow + 40 badges
          double minX = double.infinity;
          double minY = double.infinity;
          double maxX = double.negativeInfinity;
          double maxY = double.negativeInfinity;
          for (final pos in effectivePositions.values) {
            if (pos.dx < minX) minX = pos.dx;
            if (pos.dy < minY) minY = pos.dy;
            if (pos.dx + nodeWidth > maxX) maxX = pos.dx + nodeWidth;
            if (pos.dy + nodeHeight > maxY) maxY = pos.dy + nodeHeight;
          }
          if (minX != double.infinity) {
            _camera.setContentBounds(Rect.fromLTRB(minX, minY, maxX, maxY));
          }
        } else {
          _camera.setContentBounds(null);
        }

        // One-time framing AFTER the first frame — never during build, which
        // avoids the historical setState-during-build crash.
        // v5.75: Pass flat + viewerPersonId so _maybeFrame can center on the
        // viewer's own node instead of the bounding box center.
        // v5.118: Reset _framed if the layout went from empty to non-empty
        // (the proximity set was just initialized on a subsequent build).
        // Without this, the camera frames on the first (empty) layout and
        // never re-centers when the actual nodes arrive.
        if (layout.positions.isNotEmpty && _framed && _lastFramedPositionCount == 0) {
          _framed = false;
        }
        _lastFramedPositionCount = layout.positions.length;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeFrame(layout, flat, viewerPersonId));

        final personById = <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p in flat.persons)
            if (p['id'] != null) p['id'] as String: p,
        };

        // v102 (semantic-zoom fix): Cache the member count so _lodFor
        // can pass it to computeSemanticTier. Small families (< 30)
        // are pinned to NEAR (full detail) regardless of zoom.
        _currentMemberCount = flat.persons.length;
        // LARGE-GRAPH BUFFER TIGHTENING: Scale the culler's buffer zone
        // down as the member count grows. The fixed 200px default is
        // generous for small/medium families (smooth entry/exit) but
        // wasteful for large graphs where on-screen density is already
        // high. See ViewportCuller.recommendedBufferForMemberCount.
        final recommendedBuffer = ViewportCuller
            .recommendedBufferForMemberCount(_currentMemberCount);
        if (_culler.bufferPixels != recommendedBuffer) {
          _culler.bufferPixels = recommendedBuffer;
          _culler.invalidate();
        }
        // PERF: Only recompute relation labels/keys when the underlying
        // flat data or viewer changes — NOT on every pan/zoom frame.
        if (!identical(_lastFlat, flat) || _lastViewerId != viewerPersonId) {
          // CRITICAL FIX: Invalidate the RelationshipEngine cache when
          // graph data changes. Without this, the engine returns stale
          // cached results from before the new person was added, so the
          // new person gets no relationship key → no label → no color.
          RelationshipEngine.instance.invalidateCache();
          // v84 FIX: Also invalidate the edge path cache so stale Path
          // objects (keyed to old positions) don't get reused after a
          // data refresh. Without this, edges to newly-positioned nodes
          // can render at their OLD position or not at all.
          _edgePathCache.clear();
          // v84 FIX: Invalidate the viewport culler so the new node
          // set is recomputed immediately (not waiting for a pan).
          _culler.invalidate();
          _cachedRelationLabels = _relationLabels(flat, viewerPersonId);
          _cachedRelationKeys = _relationKeys(flat, viewerPersonId);
          // v69: Compute authoritative categories — this is the SINGLE
          // source of truth for node/edge colors. No lossy string
          // round-trip through KinshipEdgeClassifier.classify().
          _cachedRelationCategories = _relationCategories(flat, viewerPersonId);
          // v83: Build custom colors map from relationship data
          _cachedCustomColors = _extractCustomColors(flat);
          _lastFlat = flat;
          _lastViewerId = viewerPersonId;
        }
        final relationLabelById = _cachedRelationLabels!;
        final relationKeyById = _cachedRelationKeys!;
        final relationCategoryById = _cachedRelationCategories!;
        final customColorsByPersonId = _cachedCustomColors!;

        // Expand/collapse filter — empty visible set means "show everything".
        final Set<String> allowed =
            _expandCollapse.state.visibleNodeIds.isEmpty
                ? effectivePositions.keys.toSet()
                : _expandCollapse.state.visibleNodeIds;

        // v99: Build RAW edge tuples from flat.relationships BEFORE
        // visibility filtering. These are needed for computeCollapse
        // which must run BEFORE the visible-set derivation so the
        // hidden IDs are current (not one-frame stale).
        final rawEdgeTuples = <({String fromId, String toId, String edgeId, String relationshipKey})>[
          for (final r in flat.relationships)
            (
              fromId: (r['fromPersonId'] ?? '').toString(),
              toId: (r['toPersonId'] ?? '').toString(),
              edgeId: (r['id'] ?? '').toString(),
              relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
            ),
        ];

        // v99: Watch focus + search + path state BEFORE computing
        // collapse, so collapse has the current protected sets.
        final focusState = ref.watch(graphFocusProvider);
        final searchState = ref.watch(graphSearchProvider);
        final pathFocusState = ref.watch(graphPathFocusProvider).focus;
        final selectedPerson = ref.read(selectedNodeProvider);

        // v99: Compute collapse BEFORE visible-set derivation.
        // This eliminates the one-frame lag where the visible set
        // used stale hidden IDs from the previous build.
        ref.read(branchCollapseProvider.notifier).computeCollapse(
              allPersons: {
                for (final p in flat.persons) (p['id'] ?? '').toString(),
              },
              allEdges: rawEdgeTuples,
              focusPersonId: focusState.focusedPersonId,
              firstDegreeIds: focusState.firstDegreeIds,
              secondDegreeIds: focusState.secondDegreeIds,
              pathNodeIds: pathFocusState?.orderedPersonIds.toSet(),
              searchMatchIds: searchState.isActive
                  ? searchState.matchIdSet
                  : null,
              selectedPersonId: selectedPerson,
              familyMemberCount: flat.persons.length,
              // v102 (BUG-2 FIX): Pass the person-name lookup so
              // CollapsedBranch.rootPersonName and branchLabel are
              // populated with real names (e.g. "Mother's branch · 38").
              personNameOf: (id) {
                final p = personById[id];
                if (p == null) return '';
                return (p['name'] as String?) ?? '';
              },
            );
        // Read the UPDATED collapse state (computeCollapse just ran).
        final collapseState = ref.watch(branchCollapseProvider);
        final hiddenIds = collapseState.allHiddenMemberIds;

        // v99: Recompute focus neighbours ONLY when the edge fingerprint
        // changes (not every build). This prevents a BFS walk over all
        // edges every frame during pan/zoom.
        final edgeFingerprint = rawEdgeTuples.length * 100003 + flat.persons.length;
        if (focusState.focusedPersonId != null &&
            edgeFingerprint != _lastEdgeFingerprint) {
          _lastEdgeFingerprint = edgeFingerprint;
          ref.read(graphFocusProvider.notifier).recomputeNeighbours(
                [for (final e in rawEdgeTuples) (fromId: e.fromId, toId: e.toId)],
              );
        }

        // v99: Animate camera to focused node ONLY when the focused
        // person ID changes (not every build).
        if (focusState.focusedPersonId != null &&
            focusState.focusedPersonId != _lastFocusedPersonId) {
          _lastFocusedPersonId = focusState.focusedPersonId;
          _maybeFocusCameraOnNode(focusState.focusedPersonId!, layout);
        } else if (focusState.focusedPersonId == null) {
          _lastFocusedPersonId = null;
        }

        // v97: Cull using LOD-aware node footprints, not always 140×176.
        final lod = _lodFor(_camera.zoomLevel);
        final metrics = computeLodMetrics(
          tier: _lodTierName(lod),
          zoom: _camera.zoomLevel,
        );
        final nodeSizes = <String, Size>{
          for (final String id in effectivePositions.keys)
            id: metrics.cullSize,
        };
        final Rect vp = _graphSpaceViewport();
        final Set<String> culled =
            _culler.cull(effectivePositions, nodeSizes, vp);
        // v99: Subtract branch-collapse hidden member IDs — now uses
        // the CURRENT collapse state (computed above, not stale).
        final Set<String> visiblePreCluster = hiddenIds.isEmpty
            ? culled.where(allowed.contains).toSet()
            : culled.where((id) => allowed.contains(id) && !hiddenIds.contains(id)).toSet();

        // v5.105: Density-driven budget collapse.
        // If visible nodes exceed kNodeBudget (50), collapse subtrees
        // largest-first until budget is met. Small trees (<50 visible)
        // bypass entirely — zero regression.
        // Build childrenOf adjacency from labelAtoB parent edges.
        final childrenOfAdj = <String, Set<String>>{};
        for (final Map<String, dynamic> r in flat.relationships) {
          final label = (r['labelAtoB'] as String?) ??
              (r['relationshipKey'] as String?) ?? '';
          if (label == 'father' || label == 'mother' || label == 'parent') {
            final from = r['fromPersonId'] as String?;
            final to = r['toPersonId'] as String?;
            if (from != null && to != null) {
              // "toPerson is fromPerson's parent" → fromPerson is child of toPerson
              childrenOfAdj.putIfAbsent(to, () => <String>{}).add(from);
            }
          }
        }
        // Build person name resolver.
        String personNameResolver(String pid) {
          for (final p in flat.persons) {
            if (p['id'] == pid) return (p['name'] as String?) ?? 'Unknown';
          }
          return 'Unknown';
        }
        // Build allEdges for hidden edge computation.
        final allEdgesForCollapse = <({String fromId, String toId, String edgeId, String relationshipKey})>[
          for (final Map<String, dynamic> r in flat.relationships)
            if (r['fromPersonId'] != null && r['toPersonId'] != null && r['id'] != null)
              (
                fromId: r['fromPersonId'] as String,
                toId: r['toPersonId'] as String,
                edgeId: r['id'] as String,
                relationshipKey: (r['relationshipKey'] as String?) ?? '',
              ),
        ];
        // Run density-driven collapse.
        // v5.106: Pass categoryOf so chip colors use dominant kinship category.
        final categoryMap = <String, String>{};
        final cats = _cachedRelationCategories;
        if (cats != null) {
          for (final entry in cats.entries) {
            categoryMap[entry.key] = entry.value.toString();
          }
        }
        ref.read(branchCollapseProvider.notifier).computeDensityCollapse(
          visibleNodeIds: visiblePreCluster,
          childrenOf: childrenOfAdj,
          personNameOf: personNameResolver,
          allEdges: allEdgesForCollapse,
          categoryOf: categoryMap,
        );
        // Re-read collapse state after density collapse.
        final densityCollapseState = ref.read(branchCollapseProvider);
        final densityHiddenIds = densityCollapseState.allHiddenMemberIds;
        final densityHiddenEdgeIds = densityCollapseState.allHiddenEdgeIds;

        // Apply clustering: remove hidden members from visible set.
        final Set<String> visible = visiblePreCluster
            .where((id) => !densityHiddenIds.contains(id))
            .toSet();

        // Record throttling baselines for _onCameraChanged.
        _lastCullViewport = vp;
        _lastLod = _lodFor(_camera.zoomLevel);

        // Edges: kept when at least one endpoint is visible OR the
        // connecting segment crosses the (buffered) viewport.
        //
        // ZOOM-IN FIX: The previous rule was "BOTH endpoints must be
        // visible". When the user zoomed in, the graph-space viewport
        // shrank (e.g. at zoom 5× a 400px screen shows only 80 graph
        // units), so BOTH endpoints of an edge could fall outside the
        // viewport even though the connecting line (and its midpoint
        // dot / heart) clearly crossed the visible area. Those edges
        // — and their midpoint symbols — silently disappeared, which
        // is the "connection lines and intermediate dots disappear
        // when zooming in" bug.
        //
        // The new rule uses `isEdgeVisibleWithViewport`:
        //   1. If at least one endpoint is in the visible node set,
        //      keep the edge (preserves smooth entry/exit + the
        //      original behaviour for nodes near the viewport edge).
        //   2. Otherwise, run a Liang–Barsky segment-vs-rect test
        //      between the endpoint POSITIONS and the buffer-expanded
        //      graph-space viewport. If the segment intersects, the
        //      edge is visible — even when both endpoint widgets are
        //      off-screen.
        //
        // v64 (BUG-2 FIX): We collect ALL edges first (no first-match-wins
        // dedup here), then pass them through EdgeDeduplicator.deduplicate()
        // which:
        //   - Collapses duplicate rows (A→B "father" + B→A "child") into ONE
        //     edge, picking the strongest category.
        //   - Keeps DISTINCT categories (e.g. parent + spouse) as separate
        //     edges with lateral offsets so they don't stack on each other.
        //
        // ZOOM-IN FIX note: We use the RAW node positions for the
        // segment test (not the union-redirected effective endpoints).
        // The union midpoint always sits between the two partner nodes,
        // which are themselves connected by a spouse edge that is also
        // being tested — so if the union midpoint is in the viewport,
        // at least one partner node is near the viewport and the
        // spouse edge's fast path keeps it. Using raw positions avoids
        // a circular dependency (coupleUnions is derived AFTER the
        // edge filter) and is a tight-enough approximation for the
        // short edges in a family tree.
        final expandedVp = _culler.expandedViewport(vp);
        // v5.103: Scale the segment-crossing fallback by zoom and edge count.
        // At low zoom with many edges, the graph-space viewport is huge, so
        // the segment-vs-rect test passes for almost every long edge — even
        // ones connecting nodes on opposite sides of the graph. This causes
        // the "hairball" of hundreds of full-length lines with no visible
        // endpoint nodes, and is the main cause of lag at 500+ members.
        //
        // Fix: only use the segment-crossing fallback when:
        //   - Edge count < 200 (small graph — fallback is cheap), OR
        //   - Zoom > 1.5 (genuinely zoomed in — the original bug case)
        // At low zoom with many edges, fall back to strict "both endpoints
        // visible" (isEdgeVisible). The original zoom-in bug this was fixing
        // doesn't apply at zoom-out anyway, since at zoom-out both endpoints
        // being off-screen simultaneously for a short edge is rare.
        // v5.108: Use the post-clustering visible set size for the
        // segment-fallback decision, not the total edge count. After
        // density clustering, the visible edge count is much lower
        // (collapsed branches hide their edges), so the segment
        // fallback becomes safe to use at lower zoom levels.
        // v5.110: When branches are collapsed (densityHiddenIds is
        // non-empty), ALWAYS use strict mode — the segment fallback
        // lets edges between collapsed (hidden) nodes bleed through,
        // creating the hairball. Only use the segment fallback when
        // NO branches are collapsed (small trees or zoomed-in views).
        final currentZoom = _camera.zoomLevel;
        final branchesCollapsed = densityHiddenIds.isNotEmpty;
        final useSegmentFallback =
            !branchesCollapsed && (visible.length < 200 || currentZoom > 1.5);

        final rawEdges = <GraphEdgeData>[];
        for (final Map<String, dynamic> r in flat.relationships) {
          final s = r['fromPersonId'] as String?;
          final t = r['toPersonId'] as String?;
          if (s == null || t == null) continue;
          // v5.116 (Task 6): Skip edges where either endpoint has no
          // position in the current layout. This prevents "dangling"
          // edges that converge on points with no rendered node.
          // The proximity filter (v5.114) means only ~30 nodes have
          // positions — edges to the other 684 nodes must be dropped.
          if (!effectivePositions.containsKey(s) ||
              !effectivePositions.containsKey(t)) {
            continue;
          }
          // v5.105: Skip edges that are hidden by collapsed branches.
          // An edge is hidden if either endpoint is a hidden member
          // (densityHiddenIds) OR the edge ID is in the hidden edge set.
          final edgeId = r['id']?.toString();
          if (densityHiddenIds.contains(s) || densityHiddenIds.contains(t)) {
            continue;
          }
          if (edgeId != null && densityHiddenEdgeIds.contains(edgeId)) {
            continue;
          }
          final sPos = effectivePositions[s];
          final tPos = effectivePositions[t];
          if (sPos == null || tPos == null) {
            // Position unknown — fall back to the conservative
            // both-endpoints-visible test so we don't crash.
            if (!_culler.isEdgeVisible(s, t, visible)) continue;
          } else if (useSegmentFallback) {
            // v5.103: Use the segment-crossing fallback (original behavior)
            if (!_culler.isEdgeVisibleWithViewport(
                  sourceId: s,
                  targetId: t,
                  sourcePos: sPos,
                  targetPos: tPos,
                  visibleNodeIds: visible,
                  viewport: expandedVp,
                )) {
              continue;
            }
          } else {
            // v5.103: Strict mode — both endpoints must be visible.
            // At low zoom with many edges, this prevents the hairball.
            if (!_culler.isEdgeVisible(s, t, visible)) continue;
          }
          final relKey = (r['relationshipKey'] ?? 'unknown').toString();
          // v5.69 (DATA CORRUPTION GUARD): Log a warning if the
          // relationshipKey is not one of the 4 fundamental edge types
          // required by the DB CHECK constraint. This catches data
          // corruption from failed update attempts (e.g. a row with
          // relationshipKey='mother_in_law' that shouldn't be in this
          // column) BEFORE it silently renders with the wrong style.
          // The graph still renders the edge (using the fallback
          // classifier), but the warning makes the corruption visible
          // in dev logs for diagnosis.
          if (relKey != 'parent' &&
              relKey != 'spouse' &&
              relKey != 'adoptive_parent' &&
              relKey != 'step_parent' &&
              relKey != 'unknown') {
            debugPrint('[GRAPH WARNING] Edge $s→$t has non-fundamental '
                'relationshipKey="$relKey" (expected parent/spouse/'
                'adoptive_parent/step_parent). This may indicate data '
                'corruption from a failed relationship update. The edge '
                'will still render with a fallback style.');
          }
          rawEdges.add(GraphEdgeData(
            id: (r['id'] ?? '$s-$t').toString(),
            sourceId: s,
            targetId: t,
            relationshipKey: relKey,
            isPrivate: r['isPrivate'] as bool? ?? false,
          ));
        }

        // v70 (FIX): REMOVED the synthetic edge fallback.
        //
        // Previously, when a person had NO relationship row in the DB
        // (e.g. they were added without selecting a relationship type),
        // the code drew a FAKE dashed 'related' edge to the anchor.
        // This was misleading — it made the graph look connected when
        // it wasn't, and the fake 'related' key classified as 'extended'
        // (grey), making the node appear grey with no label.
        //
        // Now, unlinked nodes simply have NO edge drawn. They appear as
        // floating circles with no connecting line, which truthfully
        // represents their state: the user hasn't specified how they're
        // related to the anchor. The node still renders with its name,
        // and the user can tap it to add a relationship.
        //
        // The "Links: 0" stat in the home screen correctly reflects
        // this — it counts actual DB rows, not visual edges.

        // v64 (BUG-2 FIX): Deduplicate with smart category-strength
        // selection + lateral offsets for parallel edges.
        final edges = EdgeDeduplicator.deduplicate(rawEdges);

        // Phase 6: Derive couple unions from the SAME deduped edge list
        // the painter will iterate. This is the SINGLE place unions are
        // derived for this build — both the painter (via the wrapper)
        // and the hit-tester (via `_currentCoupleUnions`) read from
        // this exact list. Deriving twice would risk divergence.
        final coupleUnions = deriveCoupleUnions(
          [
            for (final d in edges)
              (
                fromId: d.edge.sourceId,
                toId: d.edge.targetId,
                edgeId: d.edge.id,
                relationshipKey: d.edge.relationshipKey,
              ),
          ],
        );

        // v69: Resolve each edge's color from the authoritative category
        // map (relationCategoryById) — no lossy string round-trip.
        //
        // v83: Also check customColors — if an edge has customColors in
        // the relationship data, use the custom line color instead.
        final String? anchorId = _SubtreeMethods._findAnchorId(flat, viewerPersonId);
        final edgeCategories = <String, KinshipEdgeCategory>{};
        final edgeCustomColors = <String, Map<String, dynamic>>{};
        if (anchorId != null) {
          for (final deduped in edges) {
            final e = deduped.edge;
            // Check for custom colors on this edge
            final customColors = customColorsByPersonId[e.sourceId] ??
                customColorsByPersonId[e.targetId];
            if (customColors != null) {
              edgeCustomColors[e.id] = customColors;
            }
            // Determine which endpoint is the anchor and which is the
            // relative. Use the relative's authoritative category.
            KinshipEdgeCategory? cat;
            if (e.sourceId == anchorId) {
              cat = relationCategoryById[e.targetId];
            } else if (e.targetId == anchorId) {
              cat = relationCategoryById[e.sourceId];
            }
            if (cat != null) {
              edgeCategories[e.id] = cat;
            }
          }
        }

        // v92 (PARTS 14–16): Resolve the viewer→target kinship path.
        // This is the SINGLE place path resolution happens — the
        // painter NEVER calls RelationshipEngine. The resolved path
        // is cached in `graphPathFocusProvider` and invalidated
        // automatically when target / viewer / graphRevision change.
        //
        // The selected node IS the path target. When no node is
        // selected the path is cleared.
        final GraphKinshipPathFocus? pathFocus =
            _resolvePathFocus(
          viewerPersonId: viewerPersonId,
          flat: flat,
          edges: edges,
          anchorId: anchorId,
        );
        // v99: Path focus, focus, search, and collapse are all watched
        // + computed ABOVE (before visible-set derivation). No duplicate
        // watches or mutations here.

        // v92 (PART 17): Cache the current edges + positions + categories
        // so the canvas tap handler can do midpoint hit-testing without
        // recomputing them. The positions map includes the visual-circle
        // Y offset so midpoint hit-testing matches the rendered edge
        // geometry exactly.
        _currentEdges = edges;
        _currentEdgeCategories = edgeCategories;
        _currentEdgeCustomColors = edgeCustomColors;
        _currentCoupleUnions = coupleUnions;
        _currentPositionsWithOffset = {
          for (final entry in effectivePositions.entries)
            entry.key: Offset(
              entry.value.dx,
              entry.value.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset,
            ),
        };

        // Build the (transform-independent) content once. The AnimatedBuilder
        // below re-applies only the camera Transform per frame, so the cached
        // raster is reused while panning/zooming.
        //
        // v2.2 Fix 7: The entire graph canvas (edges + nodes together) is
        // wrapped in ONE RepaintBoundary. Previously, separate boundaries
        // around the edge layer caused it to not repaint when node positions
        // updated during pan/zoom.
        final Widget content = RepaintBoundary(
          child: SizedBox(
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // P3.5: Ambient particle layer — drawn FIRST (below
                // edges and nodes) so the gold motes sit behind the
                // graph content. 25 deterministic motes drift around
                // the anchor node in a 6-second cycle. Reduced motion
                // → static motes (no drift).
                ..._buildAmbientParticleLayer(layout, flat),
                // v2.2 Fix 2: Edge layer is FIRST in the Stack (drawn
                // beneath nodes). This ensures edges never cover nodes
                // and are never clipped by node RepaintBoundaries.
                //
                // v2.2 Fix 1: CustomPaint uses size: Size.infinite via
                // Positioned.fill + child: SizedBox.expand() so the paint
                // canvas covers the full Stack area. Without this, the
                // canvas defaults to zero/child size and clips all lines.
                Positioned.fill(
                  // PERF: Wrap the edge painter in a ConsumerWidget that
                  // watches selectedEdgeProvider independently. This way,
                  // tapping an edge to select it only rebuilds the edge
                  // painter — NOT the entire canvas (nodes, layout, etc).
                  // v85 FIX: Add ValueKey with edges length + positions
                  // length so the wrapper rebuilds when data changes on
                  // Flutter Web (where identical() can be unreliable).
                  //
                  // v103 (FLICKER FIX): DO NOT include the LOD tier name
                  // in the ValueKey. The old key included
                  // `_lodFor(_camera.zoomLevel).name`, which meant every
                  // time the zoom crossed a tier boundary (0.72, 0.34),
                  // the ENTIRE EdgeSelectionWrapper was destroyed and
                  // recreated from scratch — causing all edges to
                  // momentarily disappear and reappear (the "connection
                  // line disappearing and coming back" bug).
                  //
                  // The painter's shouldRepaint already handles LOD
                  // changes via the edgeQuality parameter + revision
                  // counters. The ValueKey should only change when the
                  // actual edge/position DATA changes, not when the
                  // zoom-driven presentation tier changes.
                  child: EdgeSelectionWrapper(
                    key: ValueKey('edge_layer_${edges.length}_${effectivePositions.length}'),
                    // BUG 1 FIX: Apply Y offset so edge endpoints connect
                    // to the visual circle center, not the Positioned box
                    // center. The circle is at the TOP of the Column
                    // (72px diameter in a 120px tall box), so the visual
                    // circle center is 24px above the box center.
                    positions: {
                      for (final entry in effectivePositions.entries)
                        entry.key: Offset(
                          entry.value.dx,
                          entry.value.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset,
                        ),
                    },
                    // v5.22 (PART 2): Personal RELATIVE edge midpoint
                    // bow offsets, keyed by relationshipId. The painter
                    // applies these to the bezier's middle control
                    // point(s) for that edge, bowing the curve through
                    // the dragged point instead of the default
                    // computed midpoint.
                    //
                    // HARD CONSTRAINT: dragging the dot may ONLY change
                    // the visual path geometry. The drag handler MUST
                    // NOT modify the underlying Relationship row's
                    // fromPersonId, toPersonId, relationshipKey, or
                    // labelAtoB. See the assertion comment at
                    // _handleRearrangeDragUpdate.
                    //
                    // When this map is empty (the normal case for an
                    // edge that hasn't been manually adjusted), the
                    // painter falls back to the EXISTING _bezier +
                    // PathMetric t=0.5 midpoint calculation — the
                    // default "always correctly centered" behavior
                    // is unchanged for every non-adjusted edge.
                    edgeWaypoints: effectiveEdgeWaypoints,
                    edges: edges,
                    edgeCategories: edgeCategories,
                    edgeCustomColors: edgeCustomColors,
                    // Phase 6: Pass the couple unions derived above so the
                    // painter can apply the SAME union-redirect the
                    // hit-tester applies. This is the painter's ONLY
                    // source of union truth — it never recomputes.
                    coupleUnions: coupleUnions,
                    cache: _edgePathCache,
                    // v91 (PART 10): LOD-aware edge quality.
                    edgeQuality:
                        _edgeQualityFor(_lodFor(_camera.zoomLevel)),
                    // v91 (PART 11): Revision-based repaint correctness.
                    // The painter compares these in `shouldRepaint`
                    // instead of deep-comparing maps every frame.
                    //
                    //   graphRevision    — bumped when edges/positions
                    //                      counts change (add/remove
                    //                      member, edge add/delete).
                    //   layoutRevision   — bumped when layout positions
                    //                      change (re-layout, drag).
                    //   edgeVisualRevision — bumped when categories or
                    //                      custom colours change.
                    //
                    // v91 (PART 11): Revision-based repaint correctness.
                    // The painter compares these in `shouldRepaint`
                    // instead of deep-comparing maps every frame.
                    //
                    //   graphRevision    — bumped when edges/positions
                    //                      counts change (add/remove
                    //                      member, edge add/delete).
                    //                      Phase 6: also includes
                    //                      `coupleUnions.length` so a
                    //                      spouse-edge add/remove/change
                    //                      (which changes the union list
                    //                      without necessarily changing
                    //                      edge count if it's a key change)
                    //                      still triggers a repaint.
                    //   layoutRevision   — bumped when layout positions
                    //                      change (re-layout, drag).
                    //   edgeVisualRevision — bumped when categories or
                    //                      custom colours change.
                    //
                    // We use a combined length-based fingerprint for
                    // graphRevision and edgeVisualRevision, and the
                    // layout's canvasWidth/Height + positions length
                    // for layoutRevision. This is O(1) and catches
                    // every real mutation that affects rendering.
                    graphRevision:
                        edges.length * 100003 +
                            effectivePositions.length +
                            coupleUnions.length * 17,
                    layoutRevision:
                        (layout.canvasWidth * 1000).round() +
                            (layout.canvasHeight).round() +
                            effectivePositions.length +
                            // v5.22: Include the per-drag-update revision
                            // so the painter repaints while a Rearrange
                            // drag is in progress (position VALUES are
                            // changing even though counts aren't).
                            _rearrangeDragRevision,
                    edgeVisualRevision:
                        edgeCategories.length * 100003 +
                            edgeCustomColors.length,
                    // v91 (PART 13): Relationship focus mode. When a
                    // node is selected, unrelated edges are dimmed.
                    // Computed here (cheaply) from the current
                    // selectedNodeProvider + the edge list.
                    dimmedEdgeIds: _computeDimmedEdgeIds(edges),
                    // v92 (PART 14): Kinship path focus. When a path is
                    // resolved, its edges retain full clarity while
                    // unrelated edges dim.
                    pathFocusedEdgeIds: pathFocus?.orderedEdgeIds.toSet(),
                    pathFocusActive: pathFocus != null,
                    // v5.27 Task 2: Connect-on-open animation state.
                    // The engine view state's _connectOnOpenController
                    // (a second GraphPathTraceController instance —
                    // reuses the EXISTING pattern) drives a one-shot
                    // sequential edge reveal on the FIRST render after
                    // opening the graph screen. The painter uses these
                    // values to:
                    //   • Hide non-revealed edges (alpha=0) while
                    //     connectOnOpenActive is true.
                    //   • Fade in the current edge from alpha=0 to 1
                    //     over its time slot (using connectOnOpenProgress).
                    //   • Show revealed edges (connectOnOpenRevealedEdgeIds)
                    //     at full alpha.
                    connectOnOpenActive: _connectOnOpenController != null &&
                        _connectOnOpenController!.state.traceActive,
                    connectOnOpenCurrentEdgeId:
                        _connectOnOpenController?.state.currentEdgeId,
                    connectOnOpenProgress:
                        _connectOnOpenController?.state.traceProgress ?? 0.0,
                    connectOnOpenRevealedEdgeIds:
                        _connectOnOpenController?.state.completedEdgeIds ??
                            const <String>{},
                    connectOnOpenCurrentEdgeIds:
                        _connectOnOpenController?.state.currentEdgeIds ??
                            const <String>{},
                    zoom: _camera.zoomLevel,  // v5.107: zoom-aware stroke
                  ),
                ),
                // Node layer — LOD-dependent. Drawn ON TOP of edges.
                // v5.31 Issue 1: Pass effectivePositions (merged map)
                // to the node layer so node widgets are positioned at the
                // SAME coordinates the edge layer uses. Previously the node
                // layer received only `layout` and read layout.positions
                // (auto-layout only), causing nodes to stay at their
                // auto-layout positions while edges used the overridden
                // positions — creating "detached" connections.
                ..._buildNodeLayer(
                    layout, effectivePositions, visible, personById, relationLabelById, relationCategoryById, customColorsByPersonId, viewerPersonId, flat),
                // v102 (BUG-2 FIX): Collapsed-branch affordances.
                // Render a chip near each collapsed branch root showing
                // the branch label (e.g. "Mother's branch · 38").
                // Tapping the chip expands the branch (reveals hidden
                // members); long-pressing a node re-collapses via the
                // existing _handleNodeLongPress path.
                ..._buildCollapsedBranchChips(layout, collapseState),
              ],
            ),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 1.3,
              colors: [
                Color.lerp(KinrelColors.darkBackground, KinshipEdgeColors.self, 0.06)!,
                KinrelColors.darkBackground,
              ],
              stops: const [0.0, 0.75],
            ),
          ),
          child: CustomPaint(
            painter: DotGridPainter(color: Colors.white.withValues(alpha: 0.025)),
            // P4.4: Wrap the canvas in a Focus widget so keyboard events
            // (arrows, +/-, Tab, Enter, Escape) are handled by the graph.
            // The Focus is autofocus=false so it doesn't steal focus on
            // mount — the user must tap/click the graph first.
            child: Focus(
              autofocus: false,
              onKeyEvent: (node, event) {
                final handled = handleGraphKeyEvent(
                  event: event,
                  camera: _camera,
                  ref: ref,
                  viewportSize: _viewportSize,
                  visibleNodeIds: flat.persons
                      .map((p) => p['id']?.toString())
                      .whereType<String>()
                      .toList(),
                  onFocusNode: (nodeId) {
                    // Treat Enter as a tap on the keyboard-focused node.
                    final graphPos = effectivePositions[nodeId];
                    if (graphPos == null) return;
                    // Convert graph-space to screen-space via camera transform.
                    final screenPos = Offset(
                      graphPos.dx * _camera.zoomLevel + _camera.panX,
                      graphPos.dy * _camera.zoomLevel + _camera.panY,
                    );
                    _handleCanvasTapDown(
                      TapDownDetails(
                        globalPosition: screenPos,
                        localPosition: screenPos,
                      ),
                      layout,
                      flat,
                      viewerPersonId,
                    );
                  },
                  context: context,
                );
                return handled ? KeyEventResult.handled : KeyEventResult.ignored;
              },
              child: GestureDetector(
            // v72 FIX: Use translucent (NOT opaque) so child GraphNode
            // gesture detectors can receive tap/long-press events.
            // The previous `opaque` setting swallowed all touch events
            // before they reached the nodes, making taps/long-press
            // impossible on both web and app.
            behavior: HitTestBehavior.translucent,
            onScaleStart: _onScaleStart,
            // v5.29 Fix 4: Reverted the v5.28 onScaleUpdate closure back
            // to a direct _onScaleUpdate reference. The rearrange node
            // drag interception now lives INSIDE _onScaleUpdate itself
            // (see interaction_mixin.dart _onScaleUpdate) — this is
            // cleaner because the gesture handling is in one place and
            // _onScaleEnd can detect the active node drag and show the
            // SaveLockPill on finger lift (was previously handled by
            // _handleRearrangeDragEnd via the long-press end callback,
            // which never fired because the Scale recognizer won the
            // gesture arena).
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            // v72 FIX: Add onTapDown + onLongPress for geometric node
            // hit-testing. The parent ScaleGestureRecognizer competes
            // with the child's TapGestureRecognizer in the gesture arena.
            // On web, the scale recognizer wins for ANY pointer sequence,
            // so node taps never fire. We do a geometric hit-test here
            // (convert screen pos → graph space → check if inside any
            // node circle) and handle the tap directly.
            onTapDown: (details) => _handleCanvasTapDown(details, layout, flat, viewerPersonId),
            onLongPressStart: (details) => _handleNodeLongPress(details, layout, flat, viewerPersonId),
            // P2.4: Two-node select-and-compare drag gesture.
            onLongPressMoveUpdate: (details) => _handleCompareDragUpdate(details, layout),
            onLongPressEnd: (details) => _handleCompareDragEnd(details, layout, flat, viewerPersonId),
            // v62: Double-tap to zoom in 2× toward the focal point,
            // toggles back to 1× on second double-tap.
            //
            // v5.23 (PART 2.5 reset): In Rearrange mode, a double-tap
            // on a midpoint dot resets that edge's custom bow override
            // (calls LayoutOverridesService.removeEdgeWaypoint) and
            // snaps the curve back to the true computed t=0.5 bezier
            // midpoint. Matches the pattern already used for the node's
            // "Reset to auto layout" option in graph_quick_actions.dart.
            // Double-tap NOT on a dot still zooms (so users in Rearrange
            // mode can still zoom — only double-tap ON A DOT resets).
            onDoubleTapDown: (details) =>
                _doubleTapPosition = details.localPosition,
            onDoubleTap: () => _handleDoubleTap(layout, flat, viewerPersonId),
            child: Stack(
              clipBehavior: Clip.none, // v4.7: Stack doesn't clip; the _OverscanClipper below handles clipping
              children: [
                // v4.7: Use _OverscanClipper instead of raw ClipRect or Clip.none.
                // The clipper expands the clip rect by 48px on each side, so nodes
                // near the edge render fully (circle + glow + shadow + badges + labels)
                // while far-away content is still clipped (prevents graph from drawing
                // over UI elements like the app bar, FABs, etc.).
                // This matches what camera_controller.dart's _edgeMargin (48px) assumes.
                // v4.17: Removed ClipRect + _OverscanClipper entirely.
                // The graph is now an infinite canvas with NO clipping.
                // The graph area is bounded by the parent widget's padding
                // (added in family_graph_screen.dart) so it doesn't extend
                // behind the stats panel/toolbar. No clipping = no dark edges.
                AnimatedBuilder(
                      animation: _camera,
                      child: content,
                      builder: (BuildContext context, Widget? child) {
                  // P2.2: Cinematic depth-of-field — when focus is active,
                  // desaturate the entire graph canvas to 40% and apply a
                  // subtle blur on non-web platforms. The focus subgraph
                  // (focused node + first-degree neighbours) renders at
                  // full saturation via the GraphNode's own emphasis logic.
                  //
                  // v5.65 (ISOLATE CONNECTIONS): The canvas-wide desaturation
                  // + blur has been REMOVED. The isolation effect is now
                  // achieved purely through per-node + per-edge opacity
                  // dimming (non-isolated nodes → 0.18 opacity, non-isolated
                  // edges → 0.18 alpha). This is more precise than the old
                  // whole-canvas ColorFilter matrix, which also desaturated
                  // the isolated nodes themselves. With per-element dimming,
                  // the isolated person + their direct connections stay at
                  // full colour + full opacity, while everything else fades
                  // to a uniform 18% — a cleaner, clearer isolation visual.
                  final isFocusActive = focusState.focusedPersonId != null;

                  Widget transformed = Transform(
                    transform: _camera.transformMatrix,
                    child: child,
                  );

                  // v5.65: No canvas-wide ColorFilter / BackdropFilter when
                  // focus is active. The per-node opacity (node_builders.dart)
                  // + per-edge dimAlpha (engine_edge_painter.dart) handle the
                  // isolation visual. The `isFocusActive` read is kept only
                  // to avoid an unused-variable warning if future code needs
                  // to query focus state here.
                  // ignore: unused_local_variable
                  final _ = isFocusActive;

                      return transformed;
                    },
                  ),
                // P2.4: Visual drag line for the two-node select-and-compare gesture.
                // Drawn as a screen-space overlay (NOT inside the camera transform)
                // because the drag position is in screen coordinates.
                if (_compareDragFromId != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CompareDragLinePainter(
                        fromPosition: _cameraTransformToScreen(
                          effectivePositions[_compareDragFromId] ?? Offset.zero,
                          layout,
                        ),
                        toPosition: _compareDragPosition,
                      ),
                    ),
                  ),
                // v5.22 (PART 3): Shared SaveLockPill, shown after a
                // Rearrange drag release. Rendered as a screen-space
                // overlay so it sits above the camera-transformed graph
                // content (the pill should NOT pan/zoom with the graph).
                // Auto-dismiss after 6 seconds defaults to Cancel/revert
                // so unconfirmed changes never silently persist.
                //
                // v5.25 (PART 3 fix): Clamp `left` against the pill's
                // ACTUAL max width (SaveLockPill.kMaxPillWidth = 280.0),
                // not a guessed 240.0. The previous constant under-
                // corrected — the pill's actual rendered width (icon +
                // "Save this curve?" text + two buttons + padding)
                // exceeded 240px, so the right edge (Save/Cancel
                // buttons) rendered off-screen near the right edge.
                // Now: left ∈ [8, viewportWidth - kMaxPillWidth - 8]
                // guarantees the pill is fully on-screen + has 8px
                // margin on both sides. When the drag release position
                // would push the pill past the right edge, the clamp
                // shifts it left so the right edge aligns to
                // viewportWidth - 8.
                // v5.34: SaveLockPill REMOVED from the per-drag flow.
                // The new workflow uses a persistent Save button in the
                // top toolbar (family_graph_screen.dart's
                // _buildRearrangeControlsCluster). Users can move
                // multiple nodes freely, then click Save once to commit
                // all changes. No per-drag interruption.
              ],
            ),
          ), // GestureDetector close
          ), // P4.4: Focus close
        ),
    );
  },
);
  }

  /// P2.4: Converts a graph-space position to screen-space for the
  /// compare drag line overlay. Applies the camera transform manually.
  Offset _cameraTransformToScreen(Offset graphPos, GraphLayoutResult layout) {
    final zoom = _camera.zoomLevel;
    final panX = _camera.panX;
    final panY = _camera.panY;
    return Offset(
      graphPos.dx * zoom + panX,
      graphPos.dy * zoom + panY,
    );
  }

  // ── P3.5: Ambient particle layer ────────────────────────────────────

  /// Builds the ambient particle layer that drifts around the anchor
  /// node. Returns an empty list when there's no anchor (rare) so the
  /// Stack just skips this layer.
  ///
  /// The motes are drawn in GRAPH-SPACE coordinates inside the camera
  /// Transform, so they pan/zoom with the graph automatically. The
  /// painter is wrapped in a RepaintBoundary so only the particle
  /// layer repaints on each animation tick (not the entire canvas).
  ///
  /// The painter receives the buffer-expanded graph-space viewport so
  /// it can short-circuit the paint call (via a single circle-vs-rect
  /// intersection test) when the anchor's mote cloud is entirely
  /// off-screen — e.g. when the user has panned far away from the
  /// anchor or zoomed out far. This saves 25 drawCircle calls per
  /// frame in those cases.
  List<Widget> _buildAmbientParticleLayer(
      GraphLayoutResult layout, FlatGraphResult flat) {
    // Find the anchor person's ID.
    final anchorId = flat.persons
        .firstWhere(
          (p) => (p['isAnchor'] as bool?) ?? false,
          orElse: () => const <String, dynamic>{},
        )['id']
        ?.toString();
    if (anchorId == null) return const [];
    // v5.22 fix: use layout.positions (not effectivePositions) here
    // because _buildAmbientParticleLayer is called OUTSIDE the
    // LayoutBuilder builder scope, so effectivePositions (a local in
    // that scope) is not in scope here. The mote cloud follows the
    // anchor node, which is rarely user-overridden; if it is, the
    // motes drift slightly — a non-user-visible decorative cosmetic.
    final anchorPosition = layout.positions[anchorId];
    if (anchorPosition == null) return const [];

    // Buffer-expanded graph-space viewport for the painter's cull test.
    // Reusing the SAME expanded viewport the edge culler uses keeps the
    // mote fade-in/out at the viewport edge consistent with edges.
    final expandedVp = _culler.expandedViewport(_graphSpaceViewport());

    final bool reduced = MediaQuery.disableAnimationsOf(context);
    // Reduced motion → don't watch the animation (no ticks). The
    // painter receives reducedMotion: true and draws static motes.
    if (reduced) {
      return [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: AmbientParticlePainter(
                t: 0.0,
                anchorPosition: anchorPosition,
                reducedMotion: true,
                visibleViewport: expandedVp,
              ),
            ),
          ),
        ),
      ];
    }

    // Normal motion → watch the animation provider and repaint on tick.
    final animation = ref.watch(ambientParticleProvider);
    return [
      AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return RepaintBoundary(
            child: CustomPaint(
              painter: AmbientParticlePainter(
                t: animation.value,
                anchorPosition: anchorPosition,
                visibleViewport: expandedVp,
              ),
            ),
          );
        },
      ),
    ];
  }

}

/// P2.4: Painter for the visual connection line during the two-node
/// select-and-compare drag gesture. Draws a dashed orange line from the
/// source node's screen position to the user's finger position.
class _CompareDragLinePainter extends CustomPainter {
  const _CompareDragLinePainter({
    required this.fromPosition,
    required this.toPosition,
  });

  final Offset fromPosition;
  final Offset toPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8612A).withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw a dashed line from source to finger.
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final dx = toPosition.dx - fromPosition.dx;
    final dy = toPosition.dy - fromPosition.dy;
    final distance = (dx * dx + dy * dy);
    if (distance < 1) return;
    final dist = sqrt(distance);
    final stepX = dx / dist;
    final stepY = dy / dist;

    double drawn = 0;
    bool draw = true;
    while (drawn < dist) {
      final len = draw ? dashWidth : dashGap;
      final start = Offset(
        fromPosition.dx + stepX * drawn,
        fromPosition.dy + stepY * drawn,
      );
      final end = Offset(
        fromPosition.dx + stepX * (drawn + len).clamp(0, dist),
        fromPosition.dy + stepY * (drawn + len).clamp(0, dist),
      );
      if (draw) {
        canvas.drawLine(start, end, paint);
      }
      drawn += len;
      draw = !draw;
    }

    // Draw a small circle at the finger position.
    canvas.drawCircle(
      toPosition,
      8.0,
      Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      toPosition,
      8.0,
      Paint()
        ..color = const Color(0xFFE8612A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _CompareDragLinePainter old) =>
      fromPosition != old.fromPosition || toPosition != old.toPosition;
}

// ═══════════════════════════════════════════════════════════════════════
// v4.7: Overscan Clipper — expands the clip rect beyond the viewport
// ═══════════════════════════════════════════════════════════════════════
// A raw ClipRect clips to its own render box size (exactly the viewport).
// Padding inside a ClipRect only shifts content inward — it does NOT
// enlarge the clip region. This CustomClipper actually expands the clip
// rect by [overscan] pixels on each side, so nodes near the edge render
// fully (circle + glow + shadow + badges + labels) without being clipped.
//
// This matches what camera_controller.dart's _edgeMargin (48px) assumes:
// the camera lets you pan a node into a 48px "buffer zone" at the edge,
// and this clipper ensures that zone is actually visible (not clipped).
class _OverscanClipper extends CustomClipper<Rect> {
  const _OverscanClipper({required this.overscan});
  final double overscan;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        -overscan,
        -overscan,
        size.width + overscan,
        size.height + overscan,
      );

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) =>
      oldClipper is! _OverscanClipper || oldClipper.overscan != overscan;
}
