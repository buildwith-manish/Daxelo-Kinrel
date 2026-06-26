// lib/graph/widgets/family_graph_engine_view.dart
//
// DAXELO KINREL — Family Graph (V2.1 Engine view)
//
// The scalable, engine-backed alternative to the v40 `InteractiveViewer`
// widget (`family_graph.dart`). Gated behind `kUseV21Engine`
// (feature_flags.dart) so it cannot affect production until verified.
//
// Performance design (Steps 3/4 of Path B — see docs/graph/PATH_B_REWIRE.md):
//
//   • Viewport culling      — ViewportCuller builds only on-screen nodes/edges.
//   • Edge path caching      — EdgePathCache memoises bezier Paths keyed by
//                             quantized endpoints. Graph-space positions don't
//                             change during pan/zoom, so paths are pure cache
//                             hits across frames (no per-frame recompute, and
//                             NO per-edge O(N) collision scan).
//   • Level of detail (LOD)  — zoomed in: full GraphNode; mid: lightweight name
//                             chips; zoomed out: a SINGLE CustomPainter draws
//                             every node as a dot (no per-node widgets), which
//                             is what keeps 1000–2000 nodes smooth.
//   • Cheap pan/zoom         — content is built once per cull/LOD change and
//                             wrapped in a RepaintBoundary; an AnimatedBuilder
//                             re-applies only the camera Transform on each
//                             frame, so panning reuses the cached raster.
//
// Also wired to the live providers:
//   • Initial fit   — CameraController.initialFitOnce() (blank-screen fix).
//   • Position memory — CameraController persists/restores pan+zoom per family.
//   • Realtime       — graphRealtimeProvider invalidation while mounted.
//   • Offline        — isOnlineProvider banner; Drift cache serves data offline.
//   • Expand/collapse — long-press a node to toggle its descendants.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/sync/connectivity_service.dart' show isOnlineProvider;
import '../../core/services/analytics_service.dart';
import '../../core/services/graph_layout_service.dart' show GraphLayoutResult;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show
        FlatGraphResult,
        familyGraphProvider,
        graphLayoutProvider,
        graphRealtimeProvider,
        selectedEdgeProvider,
        selectedNodeProvider;
import '../data/family_graph_repository.dart' show GraphEdgeData;
import '../data/position_memory.dart' show PositionMemory;
import '../interaction/camera_controller.dart' show CameraController;
import '../interaction/expand_collapse.dart'
    show ExpandCollapseController, ExpandCollapseState;
import '../../core/constants/feature_flags.dart' show kEnableGraphShareExport;
import '../../core/kinship/kinship_service.dart' show KinshipService;
import '../../core/relationship/relationship_engine.dart' show RelationshipEngine;
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../features/family/presentation/services/graph_export_service.dart'
    show GraphExportService;
import '../rendering/edge_path_cache.dart' show EdgePathCache;
import '../rendering/viewport_culler.dart' show ViewportCuller;
import 'graph_node.dart' show GraphNode;
import 'graph_quick_actions.dart' show GraphQuickActions;
import 'graph_relationship_labels.dart' show GraphPersonData;

/// LOD tiers, chosen by camera zoom.
enum _Lod {
  /// Full interactive node cards.
  full,

  /// Lightweight name-only chips.
  chip,

  /// Single painter draws every node as a dot (max scale).
  dot,
}

/// Engine-backed family graph view (see file header).
class FamilyGraphEngineView extends ConsumerStatefulWidget {
  const FamilyGraphEngineView({
    super.key,
    required this.familyId,
    this.highlightedGeneration,
    this.recenterKey,
  });

  /// The family whose graph to render.
  final String familyId;

  /// v62: Generation to highlight (null = show all). When set, nodes
  /// NOT in this generation are dimmed to 15% opacity. Passed from
  /// the parent screen's generation filter chip bar.
  final int? highlightedGeneration;

  /// v62: When this value changes, the camera re-centers on the
  /// anchor node. Passed from the parent screen's "Center on Root"
  /// button.
  final int? recenterKey;

  @override
  ConsumerState<FamilyGraphEngineView> createState() =>
      _FamilyGraphEngineViewState();
}

class _FamilyGraphEngineViewState
    extends ConsumerState<FamilyGraphEngineView> {
  /// Bounding box used for culling + node placement (circle + label).
  static const Size _kNodeSize = Size(96, 120);

  /// Zoom thresholds for LOD tiers.
  static const double _kChipZoom = 0.55;
  static const double _kDotZoom = 0.3;

  late final PositionMemory _positionMemory;
  late final CameraController _camera;
  late final ViewportCuller _culler;
  late final ExpandCollapseController _expandCollapse;
  final EdgePathCache _edgePathCache = EdgePathCache();

  /// Wraps the on-screen graph so it can be captured for share/export.
  final GlobalKey _graphBoundaryKey = GlobalKey();

  /// v62: Periodic telemetry timer — logs edge cache hit rate + cull
  /// stats every 30 seconds while the graph is mounted.
  Timer? _telemetryTimer;
  int _lastCullVisibleCount = 0;

  /// v62: Position of the last double-tap, for zoom-toward-focal-point.
  Offset _doubleTapPosition = Offset.zero;

  Size _viewportSize = Size.zero;
  bool _framed = false; // one-time initial framing per family

  // Repaint/recull throttling.
  Rect _lastCullViewport = Rect.zero;
  _Lod _lastLod = _Lod.full;

  // Gesture bookkeeping for pan + pinch-zoom.
  Offset _lastFocal = Offset.zero;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _positionMemory = PositionMemory();
    _camera = CameraController(positionMemory: _positionMemory)
      ..setFamilyId(widget.familyId)
      ..addListener(_onCameraChanged);
    _culler = ViewportCuller(
      viewport: Rect.zero,
      bufferPixels: 300,
      rebuildThreshold: 80,
    );
    _expandCollapse =
        ExpandCollapseController(const ExpandCollapseState());

    // v62: Start periodic telemetry — log edge cache + cull stats every
    // 30 seconds so we can monitor production performance.
    _telemetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Fire-and-forget — never let telemetry break the build.
      AnalyticsService.instance
          .logEvent('graph_render_stats', {
            'edge_cache_size': _edgePathCache.size,
            'edge_cache_hit_rate': _edgePathCache.hitRate,
            'edge_cache_hits': _edgePathCache.hits,
            'edge_cache_misses': _edgePathCache.misses,
            'visible_node_count': _culler.visibleCount,
            'zoom_level': double.parse(_camera.zoomLevel.toStringAsFixed(2)),
          })
          .catchError((Object e) {
        debugPrint('⚠️ Analytics (suppressed): $e');
      });
    });
  }

  @override
  void didUpdateWidget(covariant FamilyGraphEngineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) {
      _framed = false;
      _camera
        ..resetInitialFit()
        ..setFamilyId(widget.familyId);
      _culler.invalidate();
      _edgePathCache.clear();
      _expandCollapse.updateVisibleNodes(<String>{});
    }
    // v62: Re-center when recenterKey changes (Center on Root button).
    if (oldWidget.recenterKey != widget.recenterKey) {
      _framed = false;
      _camera.resetInitialFit();
      _culler.invalidate();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    _expandCollapse.dispose();
    _positionMemory.dispose();
    super.dispose();
  }

  /// Rebuild content ONLY when the visible set or LOD tier would change.
  /// Otherwise the AnimatedBuilder pans/zooms the Transform layer for free.
  void _onCameraChanged() {
    if (!mounted) return;
    final Rect vp = _graphSpaceViewport();
    final _Lod lod = _lodFor(_camera.zoomLevel);
    if (lod != _lastLod || _culler.shouldRebuild(_lastCullViewport, vp)) {
      setState(() {});
    }
  }

  _Lod _lodFor(double zoom) {
    if (zoom >= _kChipZoom) return _Lod.full;
    if (zoom >= _kDotZoom) return _Lod.chip;
    return _Lod.dot;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep Supabase Realtime invalidation alive while this view is mounted.
    ref.watch(graphRealtimeProvider(widget.familyId));

    final bool isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final layoutAsync = ref.watch(graphLayoutProvider(widget.familyId));
    final flat = ref.watch(familyGraphProvider(widget.familyId)).valueOrNull;
    // Watched here (in build), not inside LayoutBuilder, per Riverpod rules.
    final String? selectedEdgeId = ref.watch(selectedEdgeProvider);
    // v2.2: Resolve the viewer's Person ID for perspective-based rendering.
    final viewerPersonId =
        ref.watch(viewerPersonIdProvider(widget.familyId)).valueOrNull;

    return layoutAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => _ErrorRetry(
        onRetry: () =>
            ref.invalidate(familyGraphProvider(widget.familyId)),
      ),
      data: (GraphLayoutResult layout) {
        if (layout.positions.isEmpty || flat == null) {
          return const _EmptyGraph();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _graphBoundaryKey,
                child: _buildCanvas(layout, flat, selectedEdgeId, viewerPersonId),
              ),
            ),
            if (!isOnline)
              const Positioned(
                  left: 0, right: 0, top: 0, child: _OfflineBanner()),
            if (kEnableGraphShareExport)
              // Directional alignment so the FAB sits at the bottom-end
              // edge (bottom-right in LTR, bottom-left in RTL) instead of
              // always at the physical right.
              Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FloatingActionButton.small(
                    heroTag: 'graph_share_export',
                    onPressed: _shareGraph,
                    tooltip: 'Share graph',
                    child: const Icon(Icons.ios_share),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCanvas(
      GraphLayoutResult layout, FlatGraphResult flat, String? selectedEdgeId, String? viewerPersonId) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewportSize = constraints.biggest;

        // One-time framing AFTER the first frame — never during build, which
        // avoids the historical setState-during-build crash.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeFrame(layout));

        final personById = <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p in flat.persons)
            if (p['id'] != null) p['id'] as String: p,
        };
        // v2.2: Compute every node's relation label from the VIEWER's
        // perspective using RelationshipEngine. No hardcoded labels.
        final relationLabelById = _relationLabels(flat, viewerPersonId);

        // Expand/collapse filter — empty visible set means "show everything".
        final Set<String> allowed =
            _expandCollapse.state.visibleNodeIds.isEmpty
                ? layout.positions.keys.toSet()
                : _expandCollapse.state.visibleNodeIds;

        // Cull to the on-screen set, then intersect with the allowed set.
        final nodeSizes = <String, Size>{
          for (final String id in layout.positions.keys) id: _kNodeSize,
        };
        final Rect vp = _graphSpaceViewport();
        final Set<String> culled =
            _culler.cull(layout.positions, nodeSizes, vp);
        final Set<String> visible = culled.where(allowed.contains).toSet();

        // Record throttling baselines for _onCameraChanged.
        _lastCullViewport = vp;
        _lastLod = _lodFor(_camera.zoomLevel);

        // Edges: only when BOTH endpoints are visible.
        final edges = <GraphEdgeData>[];
        for (final Map<String, dynamic> r in flat.relationships) {
          final s = r['fromPersonId'] as String?;
          final t = r['toPersonId'] as String?;
          if (s == null || t == null) continue;
          if (!_culler.isEdgeVisible(s, t, visible)) continue;
          edges.add(GraphEdgeData(
            id: (r['id'] ?? '$s-$t').toString(),
            sourceId: s,
            targetId: t,
            relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
            isPrivate: r['isPrivate'] as bool? ?? false,
          ));
        }

        // Build the (transform-independent) content once. The AnimatedBuilder
        // below re-applies only the camera Transform per frame, so the cached
        // raster is reused while panning/zooming.
        final Widget content = RepaintBoundary(
          child: SizedBox(
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Edge layer — single cached painter over the full canvas.
                // v62 FIX: CustomPaint has no `behavior` parameter, so we
                // give it a transparent ColoredBox as `child` to make the
                // entire canvas claim hit-test events. Without this, pan/zoom
                // gestures only register when fingers land on a node.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EngineEdgePainter(
                      positions: layout.positions,
                      edges: edges,
                      cache: _edgePathCache,
                      selectedEdgeId: selectedEdgeId,
                    ),
                    child: const ColoredBox(
                      color: Color(0x00000000),
                    ),
                  ),
                ),
                // Node layer — LOD-dependent.
                ..._buildNodeLayer(
                    layout, visible, personById, relationLabelById, viewerPersonId),
              ],
            ),
          ),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          // v62: Double-tap to zoom in 2× toward the focal point,
          // toggles back to 1× on second double-tap.
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: _handleDoubleTapZoom,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _camera,
              child: content,
              builder: (BuildContext context, Widget? child) {
                return Transform(
                  transform: _camera.transformMatrix,
                  child: child,
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Builds the node layer for the current LOD tier.
  List<Widget> _buildNodeLayer(
    GraphLayoutResult layout,
    Set<String> visible,
    Map<String, Map<String, dynamic>> personById,
    Map<String, String> relationLabelById,
    String? viewerPersonId,
  ) {
    final _Lod lod = _lodFor(_camera.zoomLevel);

    // Dot tier: one painter for ALL visible nodes — no per-node widgets.
    if (lod == _Lod.dot) {
      final dots = <_Dot>[];
      for (final String id in visible) {
        final pos = layout.positions[id];
        final p = personById[id];
        if (pos == null || p == null) continue;
        dots.add(_Dot(
          pos,
          _dotColor(p['gender'] as String?, (p['isAnchor'] as bool?) ?? false),
        ));
      }
      return <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _NodeDotPainter(dots),
            child: const ColoredBox(
              color: Color(0x00000000),
            ),
          ),
        ),
      ];
    }

    // Full / chip tiers: individual widgets (culling keeps the count small).
    final widgets = <Widget>[];
    final highlightedGen = widget.highlightedGeneration;
    for (final String id in visible) {
      final pos = layout.positions[id];
      final p = personById[id];
      if (pos == null || p == null) continue;
      final Widget node = lod == _Lod.full
          ? _buildFullNode(id, p, relationLabelById, viewerPersonId)
          : _buildChipNode(p);

      // v62: Dim nodes not in the highlighted generation (if set).
      final int personGen =
          (p['generationIndex'] as num?)?.toInt() ?? 0;
      final double opacity = (highlightedGen != null &&
              personGen != highlightedGen)
          ? 0.15
          : 1.0;

      widgets.add(Positioned(
        left: pos.dx - _kNodeSize.width / 2,
        top: pos.dy - _kNodeSize.height / 2,
        width: _kNodeSize.width,
        height: _kNodeSize.height,
        child: Opacity(
          opacity: opacity,
          child: RepaintBoundary(child: node),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildFullNode(
    String id,
    Map<String, dynamic> p,
    Map<String, String> labels,
    String? viewerPersonId,
  ) {
    // v2.2: If this node IS the viewer, show "You" as the relation label.
    final bool isViewer = viewerPersonId != null && id == viewerPersonId;
    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      // v2.2: "You" label for the viewer's node; otherwise use the
      // computed relation label from the viewer's perspective.
      relationLabel: isViewer ? 'You' : (labels[id] ?? ''),
      onTap: () => ref.read(selectedNodeProvider.notifier).state = id,
      // v62.2 FIX: Long-press shows the quick-actions sheet (matching
      // the v40 FamilyGraphWidget behavior) instead of toggling the
      // subtree (which was hiding nodes — confusing and unexpected).
      onLongPress: () {
        final personData = GraphPersonData(
          id: id,
          name: (p['name'] as String?) ?? '',
          gender: p['gender'] as String?,
          generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
          isAnchor: (p['isAnchor'] as bool?) ?? false,
          photoUrl: p['photoUrl'] as String?,
          isDeceased: (p['isDeceased'] as bool?) ?? false,
        );
        GraphQuickActions.show(context, personData);
      },
    );
  }

  /// Lightweight mid-zoom node: a coloured dot + the name, no avatar/animations.
  Widget _buildChipNode(Map<String, dynamic> p) {
    final color =
        _dotColor(p['gender'] as String?, (p['isAnchor'] as bool?) ?? false);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Text(
            (p['name'] as String?) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ── Share / export ───────────────────────────────────────────────────────

  Future<void> _shareGraph() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final bool ok =
        await GraphExportService.shareGraph(_graphBoundaryKey);
    if (!ok && mounted) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not capture the graph to share.')),
      );
    }
  }

  // ── Camera / culling helpers ─────────────────────────────────────────────

  /// Screen rect → graph-space rect using the inverse camera transform.
  Rect _graphSpaceViewport() {
    final double z = _camera.zoomLevel == 0 ? 1.0 : _camera.zoomLevel;
    return Rect.fromLTWH(
      -_camera.panX / z,
      -_camera.panY / z,
      _viewportSize.width / z,
      _viewportSize.height / z,
    );
  }

  Future<void> _maybeFrame(GraphLayoutResult layout) async {
    if (_framed) return;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    if (layout.positions.isEmpty) return;
    _framed = true;

    // v2.2: Center on the viewer's position if available, otherwise
    // use the saved camera position or fit-to-view.
    final viewerId =
        ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
    if (viewerId != null && layout.positions.containsKey(viewerId)) {
      // Center on the viewer's node using fitToView (which includes
      // the viewer's position in the bounding box calculation).
      _camera.initialFitOnce(layout.positions, _viewportSize);
      _culler.invalidate();
      if (mounted) setState(() {});
      return;
    }

    // Prefer a previously-saved camera position; otherwise frame the graph.
    final saved = await _camera.restorePosition(widget.familyId);
    if (saved == null) {
      _camera.initialFitOnce(layout.positions, _viewportSize);
    }
    _culler.invalidate();
    if (mounted) setState(() {});
  }

  // ── Gestures ───────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.focalPoint;
    _baseZoom = _camera.zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Pan (works for one- and two-finger drags).
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

  // ── Expand / collapse ────────────────────────────────────────────────────

  void _toggleSubtree(String id) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) return;

    final all = <String>{
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null) p['id'] as String,
    };
    final Set<String> visible = _expandCollapse.state.visibleNodeIds.isEmpty
        ? Set<String>.of(all)
        : Set<String>.of(_expandCollapse.state.visibleNodeIds);

    final Set<String> descendants = _descendantsOf(id, flat);
    final bool isExpanded = descendants.any(visible.contains);
    if (isExpanded) {
      visible.removeAll(descendants);
    } else {
      visible.addAll(descendants);
    }
    _expandCollapse.updateVisibleNodes(visible);
    _culler.invalidate();
    if (mounted) setState(() {});
  }

  Set<String> _descendantsOf(String root, FlatGraphResult flat) {
    final children = <String, List<String>>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final s = r['fromPersonId'] as String?;
      final t = r['toPersonId'] as String?;
      if (s == null || t == null) continue;
      children.putIfAbsent(s, () => <String>[]).add(t);
    }
    final out = <String>{};
    final queue = <String>[...?children[root]];
    while (queue.isNotEmpty) {
      final String n = queue.removeLast();
      if (out.add(n)) {
        queue.addAll(children[n] ?? const <String>[]);
      }
    }
    return out;
  }

  /// v2.2: Computes a relation label for every person in the graph from
  /// the VIEWER's perspective using [RelationshipEngine.resolveKey].
  ///
  /// The viewer's own node is omitted (the UI shows "You" for it).
  ///
  /// Falls back to the stored `relationshipKey` only when no viewer is
  /// available (e.g., anonymous mode), preserving legacy behavior.
  Map<String, String> _relationLabels(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final labels = <String, String>{};

    // No viewer → use legacy stored relationshipKey (architecture §3
    // invariant 7: isAnchor legacy fallback path).
    if (viewerPersonId == null) {
      for (final Map<String, dynamic> r in flat.relationships) {
        final t = r['toPersonId'] as String?;
        final key = r['relationshipKey'] as String?;
        if (t != null && key != null && !labels.containsKey(t)) {
          labels[t] = key;
        }
      }
      return labels;
    }

    // Build typed inputs for RelationshipEngine.
    final graphPersons = <GraphPerson>[
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null)
          GraphPerson(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? '',
            gender: p['gender'] as String?,
            generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
            isAnchor: (p['isAnchor'] as bool?) ?? false,
            photoUrl: p['photoUrl'] as String?,
            isDeceased: (p['isDeceased'] as bool?) ?? false,
          ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final Map<String, dynamic> r in flat.relationships)
        if (r['fromPersonId'] != null &&
            r['toPersonId'] != null &&
            r['relationshipKey'] != null)
          (
            fromId: r['fromPersonId'] as String,
            toId: r['toPersonId'] as String,
            type: r['relationshipKey'] as String,
          ),
    ];

    final engine = RelationshipEngine.instance;
    for (final GraphPerson p in graphPersons) {
      if (p.id == viewerPersonId) continue; // viewer's own label is "You"
      final key = engine.resolveKey(
        viewerPersonId: viewerPersonId,
        targetPersonId: p.id,
        persons: graphPersons,
        relationships: graphRels,
      );
      if (key != null) {
        // Translate the kinship key → display name via KinshipService.
        // The engine returns keys only; localization lives in
        // KinshipService per architecture §12.
        final displayName = _localizeKinshipKey(key);
        labels[p.id] = displayName;
      }
    }
    return labels;
  }

  /// Resolves a kinship key (e.g. "father", "mothers_brother") to a
  /// human-readable display name using [KinshipService]. Returns the
  /// pretty-printed raw key if no translation is available.
  String _localizeKinshipKey(String key) {
    try {
      final kinship = KinshipService.instance;
      if (kinship.isLoaded) {
        // English is always available; the app's localization layer can
        // re-translate this key per the user's preferred language later.
        final rel = kinship.getRelationship(key);
        final term = rel?.englishTerm;
        if (term != null && term.isNotEmpty) {
          return term;
        }
      }
    } catch (_) {
      // Fall through to the pretty-printed key.
    }
    // Pretty-print the raw key as a fallback
    // ("mothers_brother" → "Mothers Brother").
    final pretty = key
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    return pretty;
  }

  Color _dotColor(String? gender, bool isAnchor) {
    if (isAnchor) return Colors.orange;
    switch (gender) {
      case 'male':
        return Colors.blue;
      case 'female':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

/// Draws relationship edges using cached bezier paths.
///
/// Paths are memoised in [EdgePathCache] keyed by quantized endpoint
/// positions. Because graph-space positions are constant during pan/zoom,
/// repeated frames hit the cache and skip path construction entirely. The
/// factory is O(1) (no per-edge node-collision scan).
class _EngineEdgePainter extends CustomPainter {
  _EngineEdgePainter({
    required this.positions,
    required this.edges,
    required this.cache,
    this.selectedEdgeId,
  });

  final Map<String, Offset> positions;
  final List<GraphEdgeData> edges;
  final EdgePathCache cache;
  final String? selectedEdgeId;

  static Path _bezier(Offset s, Offset t) {
    final double dy = t.dy - s.dy;
    final double dx = t.dx - s.dx;
    final double lateral = dx.abs() < 10.0 ? 50.0 : 0.0;
    final cp1 = Offset(s.dx + lateral, s.dy + dy * 0.35);
    final cp2 = Offset(t.dx + lateral, t.dy - dy * 0.35);
    return Path()
      ..moveTo(s.dx, s.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF)
      ..isAntiAlias = true;
    final selected = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.orange
      ..isAntiAlias = true;

    for (final GraphEdgeData e in edges) {
      final Offset? s = positions[e.sourceId];
      final Offset? t = positions[e.targetId];
      if (s == null || t == null) continue;
      final Path path = cache.getOrCreate(
        edgeId: e.id,
        sourceId: e.sourceId,
        targetId: e.targetId,
        sourcePos: s,
        targetPos: t,
        pathFactory: _bezier,
      );
      canvas.drawPath(path, e.id == selectedEdgeId ? selected : base);
    }
  }

  @override
  bool shouldRepaint(covariant _EngineEdgePainter old) {
    return old.edges.length != edges.length ||
        old.selectedEdgeId != selectedEdgeId ||
        !identical(old.edges, edges);
  }
}

/// A single node rendered as a coloured dot at the lowest LOD tier.
class _Dot {
  const _Dot(this.pos, this.color);
  final Offset pos;
  final Color color;
}

/// Draws every visible node as a dot in ONE painter — avoids thousands of
/// widgets when fully zoomed out (the 2000-node case).
class _NodeDotPainter extends CustomPainter {
  _NodeDotPainter(this.dots);

  final List<_Dot> dots;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (final _Dot d in dots) {
      paint.color = d.color;
      canvas.drawCircle(d.pos, 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeDotPainter old) =>
      old.dots.length != dots.length || !identical(old.dots, dots);
}

// ── Small presentational helpers ───────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Offline. Showing cached graph.',
      liveRegion: true,
      child: Material(
        color: Colors.orange.shade800,
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Offline — showing cached graph',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyGraph extends StatelessWidget {
  const _EmptyGraph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No family members yet.\nAdd someone to start the graph.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('Could not load the family graph.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
