// lib/graph/widgets/family_graph_engine_view.dart
//
// DAXELO KINREL — Family Graph (V2.1 Engine view)
//
// The scalable, engine-backed alternative to the v40 `InteractiveViewer`
// widget (`family_graph.dart`). It wires the previously-orphaned engine
// layers back into the live providers:
//
//   • Viewport culling  — ViewportCuller builds only on-screen nodes/edges,
//                         so the graph scales to 500/1000/2000+ nodes.
//   • Initial fit        — CameraController.initialFitOnce() frames the graph
//                         on first load (THE blank-screen fix). See
//                         docs/graph/BLANK_SCREEN_DIAGNOSIS.md.
//   • Position memory    — CameraController persists pan/zoom per family via
//                         PositionMemory; restored on next open.
//   • Realtime sync      — graphRealtimeProvider invalidates the graph on
//                         Supabase Realtime events while this view is mounted.
//   • Offline            — isOnlineProvider drives an offline banner; the
//                         provider's Drift cache already serves graph data
//                         offline. (OfflineManager's write-queue is a follow-up.)
//   • Expand / collapse  — ExpandCollapseController filters which subtrees are
//                         rendered; long-press a node to toggle its descendants.
//
// This widget is gated behind `kUseV21Engine` (feature_flags.dart) and is NOT
// in the live path until that flag is flipped, so it cannot affect production
// until verified with `flutter analyze` + `flutter test test/graph/`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/sync/connectivity_service.dart' show isOnlineProvider;
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
import '../rendering/viewport_culler.dart' show ViewportCuller;
import 'graph_node.dart' show GraphNode;
import 'relationship_edge.dart' show RelationshipEdge;

/// Engine-backed family graph view (see file header).
class FamilyGraphEngineView extends ConsumerStatefulWidget {
  const FamilyGraphEngineView({super.key, required this.familyId});

  /// The family whose graph to render.
  final String familyId;

  @override
  ConsumerState<FamilyGraphEngineView> createState() =>
      _FamilyGraphEngineViewState();
}

class _FamilyGraphEngineViewState
    extends ConsumerState<FamilyGraphEngineView> {
  /// Bounding box used for culling + node placement (circle + label).
  static const Size _kNodeSize = Size(96, 120);

  late final PositionMemory _positionMemory;
  late final CameraController _camera;
  late final ViewportCuller _culler;
  late final ExpandCollapseController _expandCollapse;

  Size _viewportSize = Size.zero;
  bool _framed = false; // one-time initial framing per family

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
      _expandCollapse.updateVisibleNodes(<String>{});
    }
  }

  @override
  void dispose() {
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    _expandCollapse.dispose();
    _positionMemory.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep Supabase Realtime invalidation alive while this view is mounted.
    ref.watch(graphRealtimeProvider(widget.familyId));

    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final layoutAsync = ref.watch(graphLayoutProvider(widget.familyId));
    final flat = ref.watch(familyGraphProvider(widget.familyId)).valueOrNull;
    // Watched here (in build), not inside LayoutBuilder, per Riverpod rules.
    final String? selectedEdgeId = ref.watch(selectedEdgeProvider);

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
                child: _buildCanvas(layout, flat, selectedEdgeId)),
            if (!isOnline)
              const Positioned(left: 0, right: 0, top: 0, child: _OfflineBanner()),
          ],
        );
      },
    );
  }

  Widget _buildCanvas(
      GraphLayoutResult layout, FlatGraphResult flat, String? selectedEdgeId) {
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
        final relationLabelById = _relationLabels(flat);

        // Expand/collapse filter — empty visible set means "show everything".
        final Set<String> allowed =
            _expandCollapse.state.visibleNodeIds.isEmpty
                ? layout.positions.keys.toSet()
                : _expandCollapse.state.visibleNodeIds;

        // Cull to the on-screen set, then intersect with the allowed set.
        final nodeSizes = <String, Size>{
          for (final String id in layout.positions.keys) id: _kNodeSize,
        };
        final Set<String> culled =
            _culler.cull(layout.positions, nodeSizes, _graphSpaceViewport());
        final Set<String> visible =
            culled.where(allowed.contains).toSet();

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

        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: ClipRect(
            child: Transform(
              transform: _camera.transformMatrix,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Edge layer — single CustomPaint over the full canvas,
                  // fed only the culled-visible edges.
                  Positioned(
                    left: 0,
                    top: 0,
                    width: layout.canvasWidth,
                    height: layout.canvasHeight,
                    child: CustomPaint(
                      size: Size(layout.canvasWidth, layout.canvasHeight),
                      painter: RelationshipEdge(
                        positions: layout.positions,
                        edges: edges,
                        zoomLevel: _camera.zoomLevel,
                        selectedEdgeId: selectedEdgeId,
                      ),
                    ),
                  ),
                  // Node layer — only culled-visible nodes, each isolated in
                  // a RepaintBoundary so pan/zoom doesn't repaint them.
                  for (final String id in visible)
                    if (layout.positions[id] != null &&
                        personById[id] != null)
                      Positioned(
                        left: layout.positions[id]!.dx - _kNodeSize.width / 2,
                        top: layout.positions[id]!.dy - _kNodeSize.height / 2,
                        width: _kNodeSize.width,
                        height: _kNodeSize.height,
                        child: RepaintBoundary(
                          child: _buildNode(
                              id, personById[id]!, relationLabelById),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNode(
    String id,
    Map<String, dynamic> p,
    Map<String, String> labels,
  ) {
    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      relationLabel: labels[id] ?? '',
      onTap: () =>
          ref.read(selectedNodeProvider.notifier).state = id,
      onLongPress: () => _toggleSubtree(id),
    );
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

  Map<String, String> _relationLabels(FlatGraphResult flat) {
    final labels = <String, String>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final t = r['toPersonId'] as String?;
      final key = r['relationshipKey'] as String?;
      if (t != null && key != null && !labels.containsKey(t)) {
        labels[t] = key;
      }
    }
    return labels;
  }
}

// ── Small presentational helpers ───────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
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
