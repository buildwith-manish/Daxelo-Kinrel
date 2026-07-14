// lib/graph/widgets/engine/canvas_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains the _buildCanvas method — too large for the main file.

part of '../family_graph_engine_view.dart';

/// Mixin containing the canvas builder for _FamilyGraphEngineViewState.
/// Extracted to keep the main file under 1,500 lines.
extension _CanvasMethods on _FamilyGraphEngineViewState {
  Widget _buildCanvas(
      GraphLayoutResult layout, FlatGraphResult flat, String? viewerPersonId) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // FIX (keyboard-resize): Don't update _viewportSize if the height
        // shrank by more than 25% — that's a keyboard push, not a real
        // resize. The camera was fitted to the original viewport; using
        // a keyboard-shrunken viewport would cause the camera viewport
        // rect to be recalculated incorrectly, making nodes/edges
        // disappear and the background turn white.
        final newHeight = constraints.biggest.height;
        final newWidth = constraints.biggest.width;
        final isKeyboardPush = _viewportSize.height > 0 &&
            newHeight < _viewportSize.height * 0.75;
        if (!isKeyboardPush) {
          final sizeChanged = _viewportSize.width != newWidth ||
              _viewportSize.height != newHeight;
          _viewportSize = constraints.biggest;
          // FIX (culler-invalidation): After a REAL viewport size change
          // (orientation change, window resize — NOT keyboard), invalidate
          // the culler so the next build recalculates visibility with the
          // correct new viewport.
          if (sizeChanged) {
            _culler.invalidate();
          }
        }

        // One-time framing AFTER the first frame — never during build, which
        // avoids the historical setState-during-build crash.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeFrame(layout));

        final personById = <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p in flat.persons)
            if (p['id'] != null) p['id'] as String: p,
        };

        // v102 (semantic-zoom fix): Cache the member count so _lodFor
        // can pass it to computeSemanticTier. Small families (< 30)
        // are pinned to NEAR (full detail) regardless of zoom.
        _currentMemberCount = flat.persons.length;
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
                ? layout.positions.keys.toSet()
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
          for (final String id in layout.positions.keys)
            id: metrics.cullSize,
        };
        final Rect vp = _graphSpaceViewport();
        final Set<String> culled =
            _culler.cull(layout.positions, nodeSizes, vp);
        // v99: Subtract branch-collapse hidden member IDs — now uses
        // the CURRENT collapse state (computed above, not stale).
        final Set<String> visible = hiddenIds.isEmpty
            ? culled.where(allowed.contains).toSet()
            : culled.where((id) => allowed.contains(id) && !hiddenIds.contains(id)).toSet();

        // Record throttling baselines for _onCameraChanged.
        _lastCullViewport = vp;
        _lastLod = _lodFor(_camera.zoomLevel);

        // Edges: only when BOTH endpoints are visible.
        //
        // v64 (BUG-2 FIX): We collect ALL edges first (no first-match-wins
        // dedup here), then pass them through EdgeDeduplicator.deduplicate()
        // which:
        //   - Collapses duplicate rows (A→B "father" + B→A "child") into ONE
        //     edge, picking the strongest category.
        //   - Keeps DISTINCT categories (e.g. parent + spouse) as separate
        //     edges with lateral offsets so they don't stack on each other.
        final rawEdges = <GraphEdgeData>[];
        for (final Map<String, dynamic> r in flat.relationships) {
          final s = r['fromPersonId'] as String?;
          final t = r['toPersonId'] as String?;
          if (s == null || t == null) continue;
          if (!_culler.isEdgeVisible(s, t, visible)) continue;
          rawEdges.add(GraphEdgeData(
            id: (r['id'] ?? '$s-$t').toString(),
            sourceId: s,
            targetId: t,
            relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
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
        // Relationship label text per edge ID — resolved from the
        // relationship key via KinshipService (englishTerm) or
        // _prettyPrintKey fallback. Passed to EngineEdgePainter via
        // EdgeSelectionWrapper so labels render on every edge.
        final edgeLabels = <String, String>{};
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
            // Resolve the relationship label from the key.
            // Try KinshipService first (localized), fall back to
            // pretty-printed key ("father" → "Father").
            final label = _resolveEdgeLabel(e.relationshipKey);
            if (label != null && label.isNotEmpty) {
              edgeLabels[e.id] = label;
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
          for (final entry in layout.positions.entries)
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
                    key: ValueKey('edge_layer_${edges.length}_${layout.positions.length}'),
                    // BUG 1 FIX: Apply Y offset so edge endpoints connect
                    // to the visual circle center, not the Positioned box
                    // center. The circle is at the TOP of the Column
                    // (72px diameter in a 120px tall box), so the visual
                    // circle center is 24px above the box center.
                    positions: {
                      for (final entry in layout.positions.entries)
                        entry.key: Offset(
                          entry.value.dx,
                          entry.value.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset,
                        ),
                    },
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
                            layout.positions.length +
                            coupleUnions.length * 17,
                    layoutRevision:
                        (layout.canvasWidth * 1000).round() +
                            (layout.canvasHeight).round() +
                            layout.positions.length,
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
                    // Relationship labels on edges (e.g. "Father", "Son").
                    // Show when zoomed in enough for labels to be readable.
                    edgeLabels: edgeLabels,
                    showEdgeLabels: _camera.zoomLevel >=
                        _FamilyGraphEngineViewState._kEdgeLabelShowZoom,
                  ),
                ),
                // Node layer — LOD-dependent. Drawn ON TOP of edges.
                ..._buildNodeLayer(
                    layout, visible, personById, relationLabelById, relationCategoryById, customColorsByPersonId, viewerPersonId, flat),
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
                    final graphPos = layout.positions[nodeId];
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
            onDoubleTapDown: (details) =>
                _doubleTapPosition = details.localPosition,
            onDoubleTap: _handleDoubleTapZoom,
            child: Stack(
              children: [
                ClipRect(
              child: AnimatedBuilder(
                animation: _camera,
                child: content,
                builder: (BuildContext context, Widget? child) {
                  // P2.2: Cinematic depth-of-field — when focus is active,
                  // desaturate the entire graph canvas to 40% and apply a
                  // subtle blur on non-web platforms. The focus subgraph
                  // (focused node + first-degree neighbours) renders at
                  // full saturation via the GraphNode's own emphasis logic.
                  //
                  // The desaturation is applied as a ColorFilter.matrix
                  // over the whole canvas. Individual focus-subgraph nodes
                  // compensate by boosting their own saturation back up
                  // via their emphasis level (EmphasisLevel.focused /
                  // EmphasisLevel.immediateRelative have full opacity).
                  final isFocusActive = focusState.focusedPersonId != null;
                  final reduced = MediaQuery.disableAnimationsOf(context);

                  Widget transformed = Transform(
                    transform: _camera.transformMatrix,
                    child: child,
                  );

                  if (isFocusActive && !reduced) {
                    // Desaturation matrix: 40% saturation
                    // (0.299, 0.587, 0.114 are the luminance weights)
                    final s = 0.4;
                    final inv = 1.0 - s;
                    transformed = ColorFiltered(
                      colorFilter: ColorFilter.matrix([
                        s + inv * 0.299, inv * 0.587, inv * 0.114, 0, 0,
                        inv * 0.299, s + inv * 0.587, inv * 0.114, 0, 0,
                        inv * 0.299, inv * 0.587, s + inv * 0.114, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                      child: transformed,
                    );

                    // P2.2: Subtle depth-of-field blur on mobile only.
                    // ImageFilter.blur can be slow on web — skip it via kIsWeb.
                    if (!kIsWeb) {
                      transformed = BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 2.0,
                          sigmaY: 2.0,
                          tileMode: TileMode.decal,
                        ),
                        child: transformed,
                      );
                    }
                  }

                  return transformed;
                },
              ),
                ),
                // P2.4: Visual drag line for the two-node select-and-compare gesture.
                // Drawn as a screen-space overlay (NOT inside the camera transform)
                // because the drag position is in screen coordinates.
                if (_compareDragFromId != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CompareDragLinePainter(
                        fromPosition: _cameraTransformToScreen(
                          layout.positions[_compareDragFromId] ?? Offset.zero,
                          layout,
                        ),
                        toPosition: _compareDragPosition,
                      ),
                    ),
                  ),
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

  // ── Edge label resolution ─────────────────────────────────────────────

  /// Resolves a relationship key (e.g. "father", "son", "spouse",
  /// "father_in_law") into a human-readable label for display on the
  /// edge midpoint.
  ///
  /// Tries KinshipService first (localized englishTerm), falls back to
  /// a pretty-printed version of the key ("father_in_law" → "Father In Law").
  /// Returns null for empty/null keys.
  String? _resolveEdgeLabel(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    try {
      final kinship = KinshipService.instance;
      if (kinship.isLoaded) {
        final rel = kinship.getRelationship(key);
        final term = rel?.englishTerm;
        if (term != null && term.isNotEmpty) {
          return term;
        }
      }
    } catch (_) {
      // Fall through to pretty-print.
    }
    return _prettyPrintKey(key);
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
    final anchorPosition = layout.positions[anchorId];
    if (anchorPosition == null) return const [];

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
