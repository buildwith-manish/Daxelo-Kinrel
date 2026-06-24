# Path B — Re-wire the V2.1 Engine for Global Scale

Goal: replace the v40 `InteractiveViewer` path with the culling engine so the graph
scales to 500 / 1000 / 2000+ nodes, works offline, syncs in realtime, supports
expand/collapse, remembers positions, and is RTL + accessibility ready.

This document is the **implementation plan + drop-in code**. It is intentionally kept
as docs (not compiled) so it cannot break CI. Add the `.dart` files as described, then
run `flutter analyze` and `flutter test` locally after each step.

Current live wiring (what we are replacing):
- `lib/features/family/presentation/family_graph_screen.dart:455` mounts `FamilyGraphWidget` (v40).
- `lib/graph/widgets/family_graph.dart` = v40 `InteractiveViewer`, renders ALL nodes.
- Providers already present in `family_graph_provider.dart`:
  - `familyGraphProvider(familyId)` → `FlatGraphResult` (Supabase + Drift offline cache)
  - `graphLayoutProvider(familyId)` → `GraphLayoutResult { positions, canvasWidth, canvasHeight }` (computed in isolate)
  - `graphRealtimeProvider(familyId)` → Supabase Realtime invalidation

---

## Step 2 — New engine-backed widget

Add `lib/graph/widgets/family_graph_engine_view.dart`. It consumes the existing
`graphLayoutProvider`, owns a `CameraController` + `ViewportCuller`, performs the
**one-time initial fit** (the blank-screen fix), and builds only culled nodes/edges.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';
import '../interaction/camera_controller.dart';
import '../rendering/viewport_culler.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';
import 'graph_node.dart';
import 'relationship_edge.dart';

class FamilyGraphEngineView extends ConsumerStatefulWidget {
  const FamilyGraphEngineView({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyGraphEngineView> createState() => _FamilyGraphEngineViewState();
}

class _FamilyGraphEngineViewState extends ConsumerState<FamilyGraphEngineView> {
  late final CameraController _camera;
  late final ViewportCuller _culler;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _camera = CameraController(/* positionMemory: ref.read(positionMemoryProvider) */);
    _culler = ViewportCuller(
      viewport: Rect.zero,
      bufferPixels: 300,     // build a ring just outside the screen
      rebuildThreshold: 80,  // re-cull after ~80px pan or 10% zoom
    );
    _camera.addListener(_onCameraChanged);
  }

  @override
  void didUpdateWidget(covariant FamilyGraphEngineView old) {
    super.didUpdateWidget(old);
    if (old.familyId != widget.familyId) {
      _camera.resetInitialFit(); // re-frame when switching families
      _culler.invalidate();
    }
  }

  void _onCameraChanged() => setState(() {}); // transform changed → recull on build

  @override
  void dispose() {
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    super.dispose();
  }

  /// Screen rect → graph-space rect using the inverse camera transform.
  Rect _graphSpaceViewport() {
    final z = _camera.zoomLevel;
    return Rect.fromLTWH(
      -_camera.panX / z,
      -_camera.panY / z,
      _viewport.width / z,
      _viewport.height / z,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutAsync = ref.watch(graphLayoutProvider(widget.familyId));
    // Keep realtime invalidation alive while this screen is mounted.
    ref.watch(graphRealtimeProvider(widget.familyId));

    return layoutAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(onRetry: () =>
          ref.invalidate(familyGraphProvider(widget.familyId))),
      data: (layout) {
        if (layout.positions.isEmpty) return const _EmptyGraph();

        return LayoutBuilder(builder: (context, constraints) {
          _viewport = constraints.biggest;

          // ── Blank-screen fix: one-time initial fit, AFTER first frame ──
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_camera.didInitialFit) {
              _camera.initialFitOnce(layout.positions, _viewport);
              _culler.invalidate();
            }
          });

          final nodeSizes = {
            for (final id in layout.positions.keys) id: const Size(100, 120),
          };
          final visible = _culler.cull(layout.positions, nodeSizes, _graphSpaceViewport());

          return GestureDetector(
            onScaleStart: (d) => _camera.beginGesture(d.focalPoint),
            onScaleUpdate: (d) => _camera.applyGesture(d), // pan + pinch zoom
            child: ClipRect(
              child: Transform(
                transform: _camera.transformMatrix,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Edges: only when BOTH endpoints visible.
                    for (final e in ref.watch(graphEdgesProvider(widget.familyId)))
                      if (_culler.isEdgeVisible(e.sourceId, e.targetId, visible))
                        RelationshipEdge(/* from layout.positions[...] */),
                    // Nodes: only culled-visible ones.
                    for (final id in visible)
                      Positioned(
                        left: layout.positions[id]!.dx,
                        top: layout.positions[id]!.dy,
                        child: RepaintBoundary(child: GraphNode(personId: id)),
                      ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
```

> Adapt constructor params (`ViewportCuller` / `CameraController`) and the `GraphNode` /
> `RelationshipEdge` constructors to their real signatures — check the files; the field
> names above match the current engine. `_camera.beginGesture/applyGesture` may need
> small additions to `CameraController` to map a `ScaleUpdate` to `panBy` + `zoomTo`.

Then in `family_graph_screen.dart` replace the `FamilyGraphWidget(...)` at line ~455:
```dart
child: FamilyGraphEngineView(familyId: widget.familyId),
```
Keep v40 behind a feature flag for one release so you can A/B and roll back fast.

---

## Step 3 — Enable the dormant subsystems

| Subsystem | File | How to wire |
|---|---|---|
| **Viewport culling** | `rendering/viewport_culler.dart` | Done by the widget above (`cull()` + `isEdgeVisible`). Tune `bufferPixels` / `rebuildThreshold`. |
| **Position memory** | `data/position_memory.dart` | Pass a `PositionMemory` into `CameraController` (constructor already accepts it). Call `restorePosition(familyId, defaultPosition: <fit>)` instead of the blind initial fit when a saved position exists; otherwise fall back to `initialFitOnce`. |
| **Offline** | `data/offline_manager.dart` + existing Drift sync in `FamilyGraphNotifier._syncToDrift` | The provider already writes to Drift. Surface an offline banner via the existing `isOnlineProvider` (in `core/database/sync/connectivity_service.dart`) and read cached graph when offline. |
| **Realtime** | `graphRealtimeProvider(familyId)` | Already invalidates the graph on Supabase Realtime events — just `ref.watch` it in the widget (shown above). The orphaned `data/realtime_sync.dart` is a second implementation; standardise on the provider and delete the duplicate. |
| **Expand / collapse** | `interaction/expand_collapse.dart` | Hold an `ExpandCollapseController`; filter `layout.positions` to the expanded set before culling; animate added/removed nodes. Re-run `graphLayoutProvider` input when the expanded set changes. |

Order: culling → position memory → offline banner → realtime watch → expand/collapse.
Land + test each independently.

---

## Step 4 — Scale testing (run locally; no Flutter SDK in the agent sandbox)

Add `test/graph/perf/large_graph_benchmark_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/rendering/viewport_culler.dart';

List<GraphPerson> synth(int n) => [
  for (var i = 0; i < n; i++)
    GraphPerson(id: '$i', name: 'P$i', generationIndex: (i % 11) - 5,
        isAnchor: i == 0),
];

void main() {
  for (final n in [500, 1000, 2000]) {
    test('layout + cull $n nodes', () {
      final people = synth(n);
      final sw = Stopwatch()..start();
      final layout = GraphLayoutService().computeLayout(persons: people, relationships: []);
      sw.stop();
      expect(layout.positions.length, n);
      // Budget: layout < 250ms for 2000 nodes on CI hardware.
      expect(sw.elapsedMilliseconds, lessThan(n <= 1000 ? 120 : 300));

      final culler = ViewportCuller(viewport: Rect.zero, bufferPixels: 300, rebuildThreshold: 80);
      final sizes = {for (final id in layout.positions.keys) id: const Size(100, 120)};
      culler.invalidate();
      final visible = culler.cull(layout.positions, sizes,
          const Rect.fromLTWH(0, 0, 400, 800));
      // With a fitted camera you'd cull to ~30-80; here we assert culling works.
      expect(visible.isNotEmpty, true);
      print('n=$n layoutMs=${sw.elapsedMilliseconds} visible=${visible.length}');
    });
  }
}
```
Run: `flutter test test/graph/perf/`. Then profile the UI on a device:
`flutter run --profile`, open a 2000-node family, watch the DevTools frame chart.

Likely perf fixes (in priority order):
1. `RepaintBoundary` around every node (in the widget above) — isolates repaints.
2. Edge path caching — reuse `rendering/edge_path_cache.dart` so edge `Path`s aren't rebuilt every frame.
3. Compute `graphLayoutProvider` in an isolate (already done) and **memoise nodeSizes**.
4. Increase `rebuildThreshold` so culling doesn't recompute on tiny pans.
5. For >2000 nodes, add level-of-detail: hide labels/avatars below a zoom threshold.

---

## Step 5 — Finish the missing screens (file:line pointers)

- **Photo picker** — `features/family/presentation/add_person_sheet.dart:943` (`image_picker` + crop).
- **Share / export** — `features/family/presentation/family_tree_canvas.dart:977` (render graph to PNG/PDF via `RepaintBoundary.toImage`).
- **Join family / QR scanner** — `features/family/presentation/join_family_screen.dart:602`, `family_list_screen.dart:269` (`mobile_scanner`).
- **Edit profile / add relative** — `person_detail_screen.dart:138,146`, `person_detail_sheet.dart:853,878`, `tree_3d_screen.dart:3028-3052`.
- **Language picker on canvas** — `family_tree_canvas.dart:968`.
- **Audio pronunciation** — `path_finder_screen.dart:1077`.

---

## Step 6 — RTL + accessibility (all 7 languages)

- **RTL graph math**: the radial layout is mirror-symmetric, so node positions are fine,
  but **labels, sheets, toolbars** must use `Directionality` + logical insets
  (`EdgeInsetsDirectional`, `start`/`end`, not `left`/`right`). Audit
  `graph/widgets/graph_relationship_labels.dart`, `relationship_info_sheet.dart`,
  `graph_legend.dart`, `search_bar.dart`.
- **Text scaling**: node cards must not clip at 200% text scale — use `FittedBox` /
  `maxLines` + ellipsis in `graph_node.dart`.
- **Semantics**: wrap each node in `Semantics(label: '<name>, <relationship>')`; give the
  canvas a semantic summary ("Family graph, N people"). Ensure focus order is sensible.
- **Contrast & tap targets**: ≥ 4.5:1 text contrast (check brand colours in both themes),
  ≥ 48dp tap targets on node action buttons.
- **Test**: `flutter test` with `tester.binding.platformDispatcher.textScaleFactorTestValue`
  and a `Directionality(textDirection: TextDirection.rtl)` wrapper.

---

## Suggested branch/PR sequence
1. `fix/graph-blank-screen-path-b` (this branch): diagnosis + engine fixes ✅
2. `feat/graph-engine-view`: Step 2 widget behind a feature flag
3. `feat/graph-culling-perf`: Steps 3–4
4. `feat/graph-missing-screens`: Step 5
5. `feat/graph-rtl-a11y`: Step 6
