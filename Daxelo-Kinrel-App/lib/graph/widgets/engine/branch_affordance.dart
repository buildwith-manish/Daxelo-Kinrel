// lib/graph/widgets/engine/branch_affordance.dart
// Extracted from family_graph_engine_view.dart to keep the main file
// under ~900 lines.
//
// Contains the collapsed-branch chip builder, the per-node +N branch
// affordance wrapper, hidden-descendant counting, and the post-expand
// camera adjustment logic.

part of '../family_graph_engine_view.dart';

/// Mixin containing collapsed-branch affordance logic for
/// _FamilyGraphEngineViewState.
extension _BranchAffordanceMethods on _FamilyGraphEngineViewState {
  /// v102 (BUG-2 FIX): Builds positioned chips for each collapsed branch.
  ///
  /// Each chip is positioned near the branch root node's coordinates
  /// and displays the branch label (e.g. "Mother's branch · 38").
  /// Tapping the chip calls `expandBranch(rootPersonId)` to reveal
  /// the hidden members.
  ///
  /// This is the UI affordance that was missing — the collapse state
  /// was computed but never surfaced to the user, so they had no way
  /// to know a branch was collapsed or to expand it.
  List<Widget> _buildCollapsedBranchChips(
    GraphLayoutResult layout,
    BranchCollapseState collapseState,
  ) {
    if (collapseState.collapsedBranches.isEmpty) return const [];

    final chips = <Widget>[];
    for (final branch in collapseState.collapsedBranches) {
      final pos = layout.positions[branch.rootPersonId];
      if (pos == null) continue;

      // Position the chip slightly below and to the right of the root
      // node so it doesn't overlap the node circle.
      final chipLeft = pos.dx + 40;
      final chipTop =
          pos.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset + 40;

      chips.add(Positioned(
        left: chipLeft,
        top: chipTop,
        child: GestureDetector(
          onTap: () {
            // P3.2: "branch opening" haptic on branch expand.
            GraphHaptics.branchExpand(context);
            ref.read(branchCollapseProvider.notifier).expandBranch(branch.rootPersonId);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.darkBackground.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(1, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.unfold_more,
                  size: 14,
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  branch.branchLabel.isNotEmpty
                      ? branch.branchLabel
                      : 'Branch · ${branch.hiddenCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return chips;
  }

  /// v92 (PART 19): Wraps [node] in a Stack and overlays a "+N"
  /// collapsed-branch affordance chip when the node has hidden
  /// descendants. The chip is positioned at the bottom-right of the
  /// node box, outside the visual circle, so it does not cover the
  /// initials, name, or midpoint bead.
  ///
  /// The chip is only shown when:
  ///   • the node has hidden descendants (descendants not in the
  ///     current visible set)
  ///   • the node is rendered at FULL LOD (the chip is meaningless
  ///     at CHIP/DOT LOD where every node is already a dot)
  ///
  /// Tapping the chip calls `_toggleSubtree` to reveal the branch,
  /// then gently adjusts the camera if the revealed branch would be
  /// mostly outside the viewport.
  Widget _withBranchAffordance(Widget node, String nodeId, FlatGraphResult flat) {
    final hiddenCount = _hiddenDescendantsCount(nodeId, flat);
    if (hiddenCount <= 0) return node;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        node,
        // Position the chip at the bottom-right corner of the node box,
        // just outside the visual circle. The visual circle is ~72px
        // diameter centered at the top of the 140×176 box; the chip
        // sits at the bottom-right where it won't overlap the face
        // or the name.
        Positioned(
          right: -4,
          bottom: 28,
          child: BranchAffordanceChip(
            count: hiddenCount,
            onTap: () => _handleBranchExpand(nodeId, flat),
          ),
        ),
      ],
    );
  }

  /// v92 (PART 19): Computes the number of hidden descendants for
  /// [nodeId] — i.e. descendants that are NOT in the current visible
  /// set managed by ExpandCollapseController.
  ///
  /// Returns 0 when:
  ///   • the node has no descendants at all
  ///   • all descendants are already visible
  ///   • the visible set is empty (meaning "show everything")
  int _hiddenDescendantsCount(String nodeId, FlatGraphResult flat) {
    final allDescendants = _descendantsOf(nodeId, flat);
    if (allDescendants.isEmpty) return 0;

    // When visibleNodeIds is empty, the controller treats it as
    // "show everything" — so nothing is hidden.
    final visible = _expandCollapse.state.visibleNodeIds;
    if (visible.isEmpty) return 0;

    int hidden = 0;
    for (final d in allDescendants) {
      if (!visible.contains(d)) hidden++;
    }
    return hidden;
  }

  /// v92 (PART 19): Handle a tap on the +N branch affordance chip.
  /// Reveals the hidden branch via the existing `_toggleSubtree`
  /// architecture, then gently adjusts the camera if the revealed
  /// branch would be mostly outside the viewport.
  void _handleBranchExpand(String nodeId, FlatGraphResult flat) {
    // Reduced motion → reveal immediately (no camera animation).
    final bool reduced = MediaQuery.disableAnimationsOf(context);

    // Reveal the branch via the existing toggle architecture.
    _toggleSubtree(nodeId);

    // After the layout rebuilds, gently adjust the camera to bring
    // the newly-revealed descendants into view. We defer this to the
    // next frame so the new positions are available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeAdjustCameraAfterExpand(nodeId, flat, reduced);
    });
  }

  /// v92 (PART 19): After a branch is expanded, check whether the
  /// newly-revealed descendants are mostly outside the viewport. If
  /// so, gently pan the camera (preserving zoom) to bring them in.
  void _maybeAdjustCameraAfterExpand(
      String nodeId, FlatGraphResult flat, bool reduced) {
    if (_viewportSize == Size.zero) return;

    final layoutAsync = ref.read(graphLayoutProvider(widget.familyId));
    final layout = layoutAsync.valueOrNull;
    if (layout == null) return;

    final descendants = _descendantsOf(nodeId, flat);
    if (descendants.isEmpty) return;

    // Compute the bounding box of the revealed descendants.
    final revealedPositions = <Offset>[];
    for (final d in descendants) {
      final pos = layout.positions[d];
      if (pos != null) revealedPositions.add(pos);
    }
    if (revealedPositions.isEmpty) return;

    // Build the bounding box by folding the positions.
    var bounds = Rect.fromPoints(
      revealedPositions.first,
      revealedPositions.first,
    );
    for (final pos in revealedPositions.skip(1)) {
      bounds = Rect.fromPoints(
        Offset(
            min(bounds.left, pos.dx), min(bounds.top, pos.dy)),
        Offset(
            max(bounds.right, pos.dx), max(bounds.bottom, pos.dy)),
      );
    }

    // Expand the bounds a bit for padding.
    final paddedBounds = bounds.inflate(80);

    // Check if the bounds are mostly outside the current viewport.
    final viewport = _camera.computeViewport(_viewportSize);
    final intersection = paddedBounds.intersect(viewport);
    final visibleArea = intersection.width * intersection.height;
    final totalArea = paddedBounds.width * paddedBounds.height;
    if (totalArea <= 0) return;

    // If >50% of the revealed bounds are outside the viewport, pan.
    final visibleFraction = visibleArea / totalArea;
    if (visibleFraction > 0.5) return;

    // Pan the camera to center on the revealed bounds' center.
    // P3.1: route through the spring-based animator so the pan settles
    // with a cinematic spring instead of a curve tween.
    final center = paddedBounds.center;
    _camera.animateToWithSpring(
      -center.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -center.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      reducedMotion: reduced,
    );
  }
}
