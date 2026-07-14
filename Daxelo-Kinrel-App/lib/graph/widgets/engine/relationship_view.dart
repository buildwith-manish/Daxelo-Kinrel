// lib/graph/widgets/engine/relationship_view.dart
// Extracted from family_graph_engine_view.dart to keep the main file
// under ~900 lines.
//
// Contains the focus enter/back handlers and the "How are we related?"
// relationship-resolution callback that opens RelationshipInfoSheet.

part of '../family_graph_engine_view.dart';

/// Mixin containing focus + relationship-view handlers for
/// _FamilyGraphEngineViewState.
extension _RelationshipViewMethods on _FamilyGraphEngineViewState {
  void _onFocusPerson(String personId, String personName) {
    // P3.2: clear "moment" haptic on focus enter.
    GraphHaptics.focusEnter(context);

    // Build real edge tuples from the current deduped edges.
    final edgeTuples = [
      for (final d in _currentEdges)
        (fromId: d.edge.sourceId, toId: d.edge.targetId),
    ];
    // Capture the current camera viewport for history restore.
    final viewport = FocusViewportSnapshot(
      panX: _camera.panX,
      panY: _camera.panY,
      zoom: _camera.zoomLevel,
    );
    ref.read(graphFocusProvider.notifier).focus(
          personId: personId,
          personName: personName,
          edges: edgeTuples,
          currentViewport: viewport,
        );
  }

  /// v99 (Phase 1): Focus Back — restores the previous focused person
  /// + viewport from focus history.
  void _onFocusBack() {
    final popped = ref.read(graphFocusProvider.notifier).back();
    if (popped == null) return;

    // P3.2: gentle release haptic on focus exit (back).
    GraphHaptics.focusExit(context);

    // Restore the camera viewport from the popped history entry.
    // P3.1: route through the spring-based animator so the focus-back
    // settles with a cinematic spring instead of a curve tween.
    final viewport = popped.viewport;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    _camera.animateToWithSpring(
      viewport.panX,
      viewport.panY,
      viewport.zoom,
      reducedMotion: reduced,
    );

    // Force re-animation + neighbour recompute for restored focus.
    _lastFocusedPersonId = null;
    final currentFocus = ref.read(graphFocusProvider).focusedPersonId;
    if (currentFocus != null) {
      final edgeTuples = [
        for (final d in _currentEdges)
          (fromId: d.edge.sourceId, toId: d.edge.targetId),
      ];
      ref.read(graphFocusProvider.notifier).recomputeNeighbours(edgeTuples);
    }
  }

  /// v98 (Phase 2): Engine-owned "View relationship" callback.
  ///
  /// Resolves the kinship path from the viewer to [targetPersonId]
  /// using the existing RelationshipEngine + graphPathFocusProvider,
  /// then opens RelationshipInfoSheet with the resolved path.
  ///
  /// This is the "How are we related?" hero flow — reachable from
  /// any person's quick-actions menu, not just from edge taps.
  void _onViewRelationship(String targetPersonId) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) return;

    // Resolve viewerPersonId from the provider.
    final viewerPersonId =
        ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
    if (viewerPersonId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not resolve your family identity. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (viewerPersonId == targetPersonId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is you!')),
        );
      }
      return;
    }

    // v99 (Phase 2): Resolve the path SYNCHRONOUSLY before opening
    // the sheet. The existing _resolvePathFocus method does this via
    // RelationshipEngine.resolvePath — we call it directly here so
    // the sheet opens with the RESOLVED path, not a placeholder.
    final pathFocus = _resolvePathFocus(
      viewerPersonId: viewerPersonId,
      flat: flat,
      edges: _currentEdges,
      anchorId: _SubtreeMethods._findAnchorId(flat, viewerPersonId),
    );

    // Select the target so the edge painter highlights the path edges
    // and dims non-path context.
    ref.read(selectedNodeProvider.notifier).state = targetPersonId;

    final targetPerson = flat.persons
        .where((p) => p['id'] == targetPersonId)
        .firstOrNull;
    final viewerPerson = flat.persons
        .where((p) => p['id'] == viewerPersonId)
        .firstOrNull;
    if (targetPerson == null || viewerPerson == null) return;

    final targetName = (targetPerson['name'] as String?) ?? '';
    final viewerName = (viewerPerson['name'] as String?) ?? 'You';

    if (pathFocus == null) {
      // No path found — show a clear "no relationship" state.
      RelationshipInfoSheet.show(
        context,
        sourceId: viewerPersonId,
        sourceName: viewerName,
        sourceGender: viewerPerson['gender'] as String?,
        targetId: targetPersonId,
        targetName: targetName,
        targetGender: targetPerson['gender'] as String?,
        relationshipKey: 'unknown',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No confirmed family relationship path found.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Path resolved — open sheet with the ACTUAL resolved kinship term.
    RelationshipInfoSheet.show(
      context,
      sourceId: viewerPersonId,
      sourceName: viewerName,
      sourceGender: viewerPerson['gender'] as String?,
      targetId: targetPersonId,
      targetName: targetName,
      targetGender: targetPerson['gender'] as String?,
      relationshipKey: pathFocus.resolvedRelationshipKey ?? 'related',
      pathFocus: pathFocus,
    );
  }
}
