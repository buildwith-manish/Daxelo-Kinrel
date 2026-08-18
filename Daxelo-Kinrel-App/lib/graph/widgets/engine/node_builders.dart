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
  ) {
    // v2.2: If this node IS the viewer, show "You" as the relation label.
    final bool isViewer = viewerPersonId != null && id == viewerPersonId;
    // v5.9: Check if this person is "unlinked" (zero relationship edges).
    final unlinkedIds = ref.watch(unlinkedPersonIdsProvider(widget.familyId));
    final bool isUnlinked = unlinkedIds.contains(id);
    // §4: Wire selectedNodeProvider to the node's NodeState so
    // selection visually highlights the node.
    final selectedId = ref.watch(selectedNodeProvider);
    // v95 (Phase 1): Wire graphFocusProvider to NodeState.focused.
    final focusState = ref.watch(graphFocusProvider);
    final focusedId = focusState.focusedPersonId;

    // v99 (Phase 10): Use the centralized computeEmphasisLevel to
    // determine this node's emphasis. This replaces the old ad-hoc
    // if/else priority logic with ONE source of truth.
    final pathFocusState = ref.watch(graphPathFocusProvider).focus;
    final searchState = ref.watch(graphSearchProvider);
    final emphasis = computeEmphasisLevel(
      nodeId: id,
      focusedPersonId: focusedId,
      selectedPersonId: selectedId,
      pathNodeIds: pathFocusState?.orderedPersonIds.toSet(),
      pathEndpointIds: pathFocusState != null
          ? {pathFocusState.viewerPersonId, pathFocusState.targetPersonId}
          : null,
      searchMatchIds: searchState.isActive ? searchState.matchIdSet : null,
      firstDegreeIds: focusState.firstDegreeIds,
      searchActive: searchState.isActive,
      focusActive: focusedId != null,
    );

    // Map emphasis level to NodeState (visual treatment).
    final NodeState nodeState;
    if (emphasis == EmphasisLevel.focused || emphasis == EmphasisLevel.pathEndpoint) {
      nodeState = NodeState.focused;
    } else if (emphasis == EmphasisLevel.selected ||
               emphasis == EmphasisLevel.pathNode) {
      nodeState = NodeState.selected;
    } else {
      nodeState = NodeState.normal;
    }

    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      // P3.3: birthday glow — compute isNearBirthday from dateOfBirth
      // (now included in the graph RPC) and pass the shared pulse value.
      // Reduced motion → pass -1.0 as a sentinel so the painter uses a
      // static 0.45 alpha instead of reading the pulse.
      isNearBirthday: isNearBirthdayForPerson(p),
      birthdayPulseValue: isNearBirthdayForPerson(p)
          ? (MediaQuery.disableAnimationsOf(context)
              ? -1.0 // sentinel: static glow
              : ref.watch(birthdayPulseProvider).value)
          : 0.0,
      daysUntilBirthday: daysUntilBirthdayForPerson(p),
      // P3.4: memorial candle — deceased nodes get a flickering candle
      // at their center. All deceased nodes share one AnimationController
      // so they flicker in sync. Reduced motion → -1.0 sentinel = static
      // 0.75 alpha.
      memorialCandleFlickerValue: (p['isDeceased'] as bool?) ?? false
          ? (MediaQuery.disableAnimationsOf(context)
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
      onTap: () => ref.read(selectedNodeProvider.notifier).state = id,
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
  Widget _buildChipNode(Map<String, dynamic> p, {KinshipEdgeCategory? category, Map<String, dynamic>? customColors}) {
    final color = _dotColor(
      p['gender'] as String?,
      (p['isAnchor'] as bool?) ?? false,
      category: category,
      customColors: customColors,
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
