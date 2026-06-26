# Graph Blank-Screen Bug — Root-Cause Diagnosis & Fix

> Status: **Root cause identified + base fix landed.** This branch begins the
> Path B effort (re-wire the V2.1 engine for global scale). See
> `PATH_B_REWIRE.md` for the full integration plan.

## TL;DR

The blank screen was **not** a single bug — it was three individually-correct
behaviours that combine into a fatal interaction on the first frame:

1. The layout centres the anchor in a **large canvas** → all nodes are far from `(0,0)`.
2. The camera starts at the **origin** (pan 0,0 / zoom 1.0) and is forbidden from auto-centering.
3. The viewport culler builds only nodes **overlapping the viewport** → on frame 1 that
   viewport is the empty top-left corner → **zero widgets built → blank canvas**.

v40 "fixed" this by deleting the culler and rendering everything inside an
`InteractiveViewer`. That removes the blank screen but **does not scale** past a
few hundred nodes — which is why we are reverting to the engine (Path B).

## Evidence (exact files / lines)

### 1. Layout places nodes far from the origin
`lib/core/services/graph_layout_service.dart`
```dart
// "Places the anchor person at the exact center of the canvas"
final center = Offset(0.0, 0.0); // will translate later
positions[anchor] = center;
// ... later every position is translated so the anchor sits at
// (canvasWidth / 2, canvasHeight / 2). For a multi-ring family this is
// hundreds-to-thousands of px from (0,0).
```

### 2. Camera starts at origin and never auto-fits
`lib/graph/interaction/camera_controller.dart`
```dart
double _panX = 0.0;
double _panY = 0.0;
double _zoomLevel = 1.0;

Matrix4 get transformMatrix => Matrix4.identity()
  ..translate(_panX, _panY)
  ..scale(_zoomLevel, _zoomLevel);

// Design rule, verbatim from the header:
//   "No auto-center. No auto-zoom without user action."
// `fitToView()` exists but nothing calls it on data load.
// `reset()` returns to the ORIGIN — it is not a fit.
```

### 3. Culler builds only nodes inside the viewport
`lib/graph/rendering/viewport_culler.dart`
```dart
bool isNodeVisible(String id, Offset position, Size nodeSize, Rect viewport) {
  final nodeRect = Rect.fromCenter(
    center: position, width: nodeSize.width, height: nodeSize.height);
  return viewport.overlaps(nodeRect); // graph-space overlap test
}
```
On the first frame the graph-space viewport is `Rect.fromLTWH(0, 0, W, H)` (camera at
origin) — the **canvas top-left corner**, which contains **no nodes**. `cull()` returns
an empty set, so no node widgets and no edges are built.

### 4. The empty result then *sticks*
`shouldRebuild()` skips recalculation unless the viewport moves past
`_rebuildThreshold`, so the empty visible-set is cached and the canvas stays blank
even after positions are known.

## The fix (landed on this branch)

Two additive, low-risk engine changes — no signatures changed, nothing deleted:

### A. One-time initial fit — `camera_controller.dart`
New `initialFitOnce(positions, viewportSize)` (guarded by `_didInitialFit`) performs a
single `fitToView` the first time data + a real viewport size are available. This is the
*initial framing*, explicitly distinct from the forbidden "auto-center on every event."
`resetInitialFit()` re-arms it when switching families.

### B. Blank-screen safety net — `viewport_culler.dart`
In `cull()`, if the computed visible set is empty **but** `positions.isNotEmpty`, fall
back to showing every node instead of a blank canvas. After the initial fit moves the
camera, the next cull returns the correct (small) visible set. This guarantees the graph
can never again render fully blank because of a viewport/transform mismatch.

### How they work together (the widget must do this — see PATH_B_REWIRE.md)
```
on first frame with known size + non-empty positions:
  WidgetsBinding.instance.addPostFrameCallback((_) {     // never during build
    camera.initialFitOnce(positions, viewportSize);       // frame the graph
    culler.invalidate();                                  // force a recompute
  });
```
Running the fit in a post-frame callback (not synchronously in `build`) also eliminates
the original **setState-during-build** crash named in the v40 header.

## Why this is better than v40
| | v40 (InteractiveViewer) | Engine + this fix |
|---|---|---|
| Blank screen | Avoided by rendering everything | Avoided by initial fit + safety net |
| 500+ nodes | Builds every widget every frame → jank | Culls to ~30–80 visible widgets |
| Offline / realtime / expand-collapse / saved positions | Not wired | Re-enabled (see PATH_B_REWIRE.md) |

## Verification you must run locally (no Flutter SDK in this environment)
```bash
cd Daxelo-Kinrel-App
flutter analyze
flutter test test/graph/
```
Then run the app and confirm: open a family with 3+ generations → the graph is framed and
visible immediately (no pan required), and "Reset View" still returns to origin.
