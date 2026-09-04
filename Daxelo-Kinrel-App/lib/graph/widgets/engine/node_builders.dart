// lib/graph/widgets/engine/node_builders.dart
// P0.4/P5.2: Extracted from family_graph_engine_view.dart to keep the
// main file under 1500 lines.
//
// Contains _buildFullNode and _buildChipNode — the LOD-dependent node
// construction methods.

part of '../family_graph_engine_view.dart';

/// Mixin containing node builder methods for _FamilyGraphEngineViewState.
/// Extracted to keep the main file under 1500 lines (P0.4 decomposition).
extension _NodeBuilders on _FamilyGraphEngineViewState {

  Widget _buildFullNode(
    String id,
    Map<String, dynamic> p,
    Map<String, String> labels,
    Map<String, KinshipEdgeCategory> relationCategoryById,
    Map<String, Map<String, dynamic>> customColorsByPersonId,
    String? viewerPersonId,
    FlatGraphResult? flat, {
    /// v5.143 (HIDDEN-NODE AUDIT): Pre-computed first-degree neighbor
    /// IDs for the currently-selected node, built ONCE in canvas_mixin
    /// via the FilteredGraph adjacency map. When non-null + non-empty
    /// + tap-highlight is active, this replaces the per-node iteration
    /// of flat.relationships (1000 edges × 50 nodes = 50,000 ops).
    /// When null, falls back to the old per-node loop (rare — only
    /// when _buildFullNode is called from a non-canvas context).
    Set<String>? precomputedFirstDegreeIds,
  }) {
    // v2.2: If this node IS the viewer, show "You" as the relation label.
    final bool isViewer = viewerPersonId != null && id == viewerPersonId;

    // v5.140 (PERF): Use `.select()` on set-returning providers so the
    // parent state only rebuilds when THIS NODE'S membership in the set
    // changes — NOT when any other node's membership changes. Previously
    // any change to unlinkedPersonIds (e.g. a new node being linked
    // elsewhere in the family) rebuilt every visible GraphNode. With
    // 100 visible nodes and one node-linking operation, that was 100
    // wasted rebuilds. Now only the previously-unlinked + newly-linked
    // nodes rebuild.
    final bool isUnlinked = ref.watch(
      unlinkedPersonIdsProvider(widget.familyId)
          .select((Set<String> s) => s.contains(id)),
    );
    final bool isIndirectRelation = ref.watch(
      indirectRelationIdsProvider(widget.familyId)
          .select((Set<String> s) => s.contains(id)),
    );

    // v5.140 (PERF): Scope selectedNodeProvider to whether THIS node is
    // selected. The full selectedId is still read below (for the tap-
    // highlight first-degree computation) but that read uses ref.read
    // which doesn't subscribe — only the boolean scoping matters for
    // rebuild triggering.
    final bool isSelected = ref.watch(
      selectedNodeProvider.select((String? s) => s == id),
    );
    final String? selectedId = ref.read(selectedNodeProvider);

    // v95 (Phase 1): Wire graphFocusProvider to NodeState.focused.
    // v5.140 (PERF): Scope focus-state watches to only the fields this
    // node actually reads. The previous `ref.watch(graphFocusProvider)`
    // subscribed to the entire state object — any change to
    // firstDegreeIds (e.g. when a different node is focused and its
    // neighbors are computed) rebuilt every visible GraphNode. Now we
    // split into:
    //   - focusedId: the focused person id (or null) — used for emphasis
    //   - isFirstDegree: whether THIS node is in the first-degree set
    //     — used for the isolation opacity calc
    final String? focusedId = ref.watch(
      graphFocusProvider.select((s) => s.focusedPersonId),
    );
    final bool isFirstDegree = ref.watch(
      graphFocusProvider.select((s) => s.firstDegreeIds.contains(id)),
    );
    final Set<String> focusFirstDegreeIds =
        ref.read(graphFocusProvider).firstDegreeIds;

    // v99 (Phase 10): Use the centralized computeEmphasisLevel to
    // determine this node's emphasis. This replaces the old ad-hoc
    // if/else priority logic with ONE source of truth.
    final pathFocusState = ref.watch(graphPathFocusProvider).focus;
    final searchState = ref.watch(graphSearchProvider);

    // v5.x (tap-highlight fix): when a plain tap selects a node (but
    // focus mode is NOT active), compute the selected node's
    // first-degree neighbors from the edge list and pass them as
    // firstDegreeIds. This ensures the person nodes at the other end
    // of the connecting edges ALSO light up (not just the edges).
    //
    // Previously, firstDegreeIds only came from graphFocusProvider
    // (long-press "Isolate Connections" mode). A plain tap set
    // selectedNodeProvider but never populated firstDegreeIds — so
    // the edges dimmed/brightened correctly but the neighbor nodes
    // stayed at normal opacity, same as unrelated nodes.
    Set<String>? effectiveFirstDegreeIds = focusFirstDegreeIds;
    final bool tapHighlightActive =
        selectedId != null && focusedId == null && !searchState.isActive;
    if (tapHighlightActive && flat != null) {
      // v5.143 (HIDDEN-NODE AUDIT): Use the pre-computed first-degree
      // IDs from the FilteredGraph adjacency map (passed in from
      // canvas_mixin) instead of iterating flat.relationships per node.
      //
      // OLD: 50 nodes × 1000 edges = 50,000 ops per rebuild
      // NEW: O(1) — the Set was built once in canvas_mixin
      if (precomputedFirstDegreeIds != null) {
        effectiveFirstDegreeIds = precomputedFirstDegreeIds;
      } else {
        // Fallback: only hit when _buildFullNode is called from a
        // non-canvas context (rare — tests, legacy callers).
        effectiveFirstDegreeIds = <String>{};
        for (final r in flat.relationships) {
          final from = r['fromPersonId']?.toString();
          final to = r['toPersonId']?.toString();
          if (from == selectedId && to != null) {
            effectiveFirstDegreeIds.add(to);
          } else if (to == selectedId && from != null) {
            effectiveFirstDegreeIds.add(from);
          }
        }
      }
    }

    final emphasis = computeEmphasisLevel(
      nodeId: id,
      focusedPersonId: focusedId,
      selectedPersonId: selectedId,
      pathNodeIds: pathFocusState?.orderedPersonIds.toSet(),
      pathEndpointIds: pathFocusState != null
          ? {pathFocusState.viewerPersonId, pathFocusState.targetPersonId}
          : null,
      searchMatchIds: searchState.isActive ? searchState.matchIdSet : null,
      firstDegreeIds: effectiveFirstDegreeIds,
      searchActive: searchState.isActive,
      focusActive: focusedId != null,
    );

    // Map emphasis level to NodeState (visual treatment).
    final NodeState nodeState;
    if (emphasis == EmphasisLevel.focused || emphasis == EmphasisLevel.pathEndpoint) {
      nodeState = NodeState.focused;
    } else if (emphasis == EmphasisLevel.selected ||
               emphasis == EmphasisLevel.pathNode) {
      // v5.140 (PERF): Use the scoped `isSelected` boolean instead of
      // recomputing `selectedId == id`. Functionally identical.
      nodeState = (isSelected || emphasis == EmphasisLevel.pathNode)
          ? NodeState.selected
          : NodeState.normal;
    } else {
      nodeState = NodeState.normal;
    }

    // v5.65 (ISOLATE CONNECTIONS): When isolation/focus is active, fade
    // nodes that are NOT part of the isolated subgraph (the focused
    // person + their direct 1st-degree connections) to 18% opacity.
    // This matches the edge dimming (dimAlpha = 0.18 in the painter)
    // so the whole graph fades uniformly — nodes AND lines — while
    // the isolated person's immediate relationship circle stays fully
    // visible.
    //
    // v5.x (tap-highlight fix): ALSO apply the three-tier hierarchy
    // on a plain TAP (not just focus mode). When a node is tapped:
    //   - Tapped node: full opacity (1.0)
    //   - Direct connections: elevated opacity (0.90)
    //   - Everyone else: dimmed (0.40) — faintly visible, not hidden
    // This matches the EmphasisLevel values in emphasis_priority.dart.
    // The node's emphasis.opacity is already computed above — use it
    // directly for the opacity. This is the SINGLE source of truth
    // for both the visual treatment (glow/selected) AND the opacity.
    final double nodeOpacity;
    if (focusedId != null) {
      // Focus mode (long-press "Isolate Connections"): 18% for
      // non-isolated nodes, matching the edge dimAlpha.
      // v5.140 (PERF): Use the scoped `isFirstDegree` boolean instead
      // of calling `focusState.firstDegreeIds.contains(id)` again.
      final bool isIsolated = id == focusedId || isFirstDegree;
      nodeOpacity = isIsolated ? 1.0 : 0.18;
    } else if (tapHighlightActive) {
      // Plain tap: use the emphasis level's opacity directly.
      // This gives: selected (1.0), immediateRelative (0.90),
      // dimmed (0.40) — the three-tier hierarchy the user wants.
      nodeOpacity = emphasis.opacity;
    } else {
      nodeOpacity = 1.0;
    }

    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      // v5.74 (BUG 1 FIX): Pass isAnchor as the viewer's own node flag,
      // NOT the Person.isAnchor DB field. The viewer's node should get
      // the steady green "self" styling (distinct from the tap-selected
      // glow). Using isViewer instead of p['isAnchor'] ensures that
      // when a non-creator member logs in, THEIR node (not the family
      // creator's) gets the green styling.
      isAnchor: isViewer,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      // v5.65 (ISOLATE CONNECTIONS): Pass the computed node opacity so
      // non-isolated nodes fade to 18% when a person is focused. When
      // no focus is active, this is 1.0 (no change).
      opacity: nodeOpacity,
      // P3.3: birthday glow — compute isNearBirthday from dateOfBirth
      // (now included in the graph RPC) and pass the shared pulse value.
      // Reduced motion → pass -1.0 as a sentinel so the painter uses a
      // static 0.45 alpha instead of reading the pulse.
      // v5.141 (LOW-END PERF): Also pass -1.0 on low-end devices (the
      // profile's allowBirthdayPulseAnimation flag is false). The ring
      // is still visible at the static 0.45 alpha — just not animated.
      isNearBirthday: isNearBirthdayForPerson(p),
      birthdayPulseValue: isNearBirthdayForPerson(p)
          ? (MediaQuery.disableAnimationsOf(context) ||
                  !_perfProfile.allowBirthdayPulseAnimation
              ? -1.0 // sentinel: static glow
              : ref.watch(birthdayPulseProvider).value)
          : 0.0,
      daysUntilBirthday: daysUntilBirthdayForPerson(p),
      // P3.4: memorial candle — deceased nodes get a flickering candle
      // at their center. All deceased nodes share one AnimationController
      // so they flicker in sync. Reduced motion → -1.0 sentinel = static
      // 0.75 alpha.
      // v5.141 (LOW-END PERF): Also pass -1.0 on low-end devices (the
      // profile's allowMemorialCandleFlicker flag is false). The candle
      // is still visible at the static 0.75 alpha — just not flickering.
      memorialCandleFlickerValue: (p['isDeceased'] as bool?) ?? false
          ? (MediaQuery.disableAnimationsOf(context) ||
                  !_perfProfile.allowMemorialCandleFlicker
              ? -1.0 // sentinel: static candle
              : ref.watch(memorialCandleFlickerProvider).value)
          : 0.0,
      isRecentlyDeceased: isRecentlyDeceasedForPerson(p),
      // P3.7: "On this day" badge — appears when today is the person's
      // birthday or anniversary. Computed in-memory so it appears in the
      // same render frame as the graph nodes (1-frame requirement).
      onThisDayEvent: onThisDayEventForPerson(p),
      nodeState: nodeState,
      // The "Pending" badge was previously shown for ANY person without
      // a linkedUserId (i.e., not yet claimed by a Kinrel account). But
      // most family tree members (grandparents, children, etc.) are
      // added as Person nodes without Kinrel accounts — they're real
      // family members, not pending invitations. Showing "Pending" on
      // them is misleading.
      //
      // The badge is now disabled by default. It should only be shown
      // when there's an actual pending invitation for this person,
      // which requires checking the FamilyInvite table — not available
      // at the graph node level without an additional query.
      isUnclaimed: false,
      // v5.9: Pass isUnlinked so GraphNode renders the dashed ring + badge.
      isUnlinked: isUnlinked,
      // v5.85: Pass the indirect-relation flag so GraphNode renders the
      // interlocking-rings badge on indirectly-related nodes.
      isIndirectRelation: isIndirectRelation,
      // v5.86: When the badge is tapped, open the Connection sheet
      // (same as long-press → View relationship).
      onBadgeTap: isIndirectRelation
          ? () => _onViewRelationship(id)
          : null,
      // Pass familyId so GraphNode can render the Kinrel role glyph badge
      // (root/anchor/bridge/weaver/leaf/twin_node) on the node when
      // kEnableKinrel is true.
      familyId: widget.familyId,
      // v69: Pass the AUTHORITATIVE category directly — no lossy string
      // round-trip. GraphNode uses styleForCategory(category) for its
      // border/tint color, which is always correct.
      category: relationCategoryById[id],
      // v2.2: "You" label for the viewer's node; otherwise use the
      // computed relation label from the viewer's perspective.
      relationLabel: isViewer ? 'You' : (labels[id] ?? ''),
      // v104 (LABEL FADE FIX): Pass the camera so GraphNode can drive
      // a SMOOTH zoom-fade for the relation label via an internal
      // AnimatedBuilder (see GraphNode._buildRelationLabel). The old
      // hard [showRelationLabel] toggle is now only a fallback used
      // when [camera] is null. The primary member name is ALWAYS
      // visible regardless of the relation label fade.
      camera: _camera,
      memberCount: _currentMemberCount,
      focusActive:
          ref.read(graphFocusProvider).focusedPersonId != null,
      // v5.36: Pass rearrangeMode to GraphNode so it can OMIT the
      // per-node LongPressGestureRecognizer entirely when Rearrange
      // mode is ON. This prevents the per-node recognizer from
      // competing with the canvas-level drag handler in the gesture
      // arena — which was the root cause of unreliable dragging +
      // Save/Reset appearing to do nothing.
      rearrangeMode: ref.read(rearrangeModeProvider),
      // v93 (ZOOM FIX) legacy fallback — still computed for the
      // camera-null case (e.g. tests). When [camera] is non-null this
      // flag is ignored by GraphNode.
      showRelationLabel: shouldShowLabel(_camera.zoomLevel),
      // Tap = select / highlight ONLY. A normal tap must never open
      // the member information bottom sheet — that is reserved for
      // long-press (see onLongPress below). This mirrors the parent
      // canvas gesture handler in interaction_mixin.dart.
      // v5.37: In Rearrange mode, suppress per-node tap completely.
      // Tapping a node should NOT trigger Focus Mode, select the node,
      // or perform any standard graph action. The only allowed
      // interaction in Rearrange mode is dragging/repositioning.
      onTap: () {
        if (ref.read(rearrangeModeProvider)) return;
        ref.read(selectedNodeProvider.notifier).state = id;
        // v5.114: Tap-to-expand — if this node is on the outermost visible
        // ring, expand its immediate neighborhood into the visible set.
        // This is incremental: only the tapped node's direct neighbors
        // are added, the rest of the graph is unchanged.
        if (flat != null) _maybeExpandFromPerson(id, flat);
      },
      // Long-press = open the member information bottom sheet. This is
      // the ONLY gesture that opens the info panel from a node.
      // v62.2 FIX: Long-press shows the quick-actions sheet (matching
      // the v40 FamilyGraphWidget behavior) instead of toggling the
      // subtree (which was hiding nodes — confusing and unexpected).
      // v5.33 Issue 3: Guard with rearrangeModeProvider — if Rearrange
      // mode is active, this per-node onLongPress MUST no-op completely.
      // The canvas-level GestureDetector already handles rearrange long-
      // press routing (→ _handleRearrangeLongPressStart). Without this
      // guard, the per-node handler fires INDEPENDENTLY (because the
      // canvas GestureDetector uses HitTestBehavior.translucent which
      // allows child gesture detectors to also receive events) and opens
      // QuickActions even in Rearrange mode — the exact bug the user
      // reported ("long-press on non-spouse nodes still opens the
      // QuickActions sheet instead of initiating a drag").
      onLongPress: () {
        // v5.33: If Rearrange mode is active, suppress the per-node
        // long-press completely — the canvas-level handler takes over.
        if (ref.read(rearrangeModeProvider)) return;
        final personData = GraphPersonData(
          id: id,
          name: (p['name'] as String?) ?? '',
          gender: p['gender'] as String?,
          generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
          isAnchor: (p['isAnchor'] as bool?) ?? false,
          photoUrl: p['photoUrl'] as String?,
          isDeceased: (p['isDeceased'] as bool?) ?? false,
          dateOfBirth: p['dateOfBirth'] as String?,
        );
        // v87: Pass familyId + isOwner + isSelf for Remove Member
        final isAnchor = (p['isAnchor'] as bool?) ?? false;
        // v99 (Phase 8): Resolve actual family role from provider.
        // Previously hardcoded isOwner: true — anyone could remove
        // any member from the UI. Now only admins/owners see Remove.
        final role = ref.read(currentUserFamilyRoleProvider(widget.familyId));
        final canRemove = role == 'admin' || role == 'owner';
        GraphQuickActions.show(
          context,
          personData,
          familyId: widget.familyId,
          isOwner: canRemove,
          isSelf: isAnchor,
          ref: ref, // v95: enables "Focus on person" action
          onFocusPerson: _onFocusPerson, // v98: real edges + viewport
          onViewRelationship: _onViewRelationship, // v98: "How are we related?"
        );
      },
    );
  }

  /// Lightweight mid-zoom node: a coloured dot + the name, no avatar/animations.
  /// v97: Zoom-aware geometry — chip dimensions are computed from desired
  /// screen-space sizes and converted to graph space so the parent camera
  /// Transform restores them to stable screen-space sizes.
  Widget _buildChipNode(Map<String, dynamic> p, {KinshipEdgeCategory? category, Map<String, dynamic>? customColors, bool isViewer = false}) {
    final color = _dotColor(
      p['gender'] as String?,
      (p['isAnchor'] as bool?) ?? false,
      category: category,
      customColors: customColors,
      isViewer: isViewer,
    );
    // v97: Compute graph-space dimensions from desired screen-space targets.
    final zoom = _camera.zoomLevel;
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    // Screen-space targets (constants):
    const screenMarkerDiameter = 8.0;  // 8px screen marker
    const screenMarkerBorder = 1.5;    // 1.5px screen border
    const screenFontSize = 11.0;       // 11px screen font
    const screenSpacing = 4.0;         // 4px screen gap
    // Graph-space values (divided by zoom so Transform restores them):
    final graphMarkerDiameter = screenMarkerDiameter / safeZoom;
    final graphMarkerBorder = screenMarkerBorder / safeZoom;
    final graphFontSize = screenFontSize / safeZoom;
    final graphSpacing = screenSpacing / safeZoom;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: graphMarkerDiameter,
          height: graphMarkerDiameter,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: graphMarkerBorder,
            ),
          ),
        ),
        SizedBox(height: graphSpacing),
        Flexible(
          child: Text(
            (p['name'] as String?) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: graphFontSize),
          ),
        ),
      ],
    );
  }

}
