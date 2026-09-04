# Graph Performance Profiling Playbook

> **v5.142** — How to find the actual bottleneck instead of guessing.
>
> The graph engine (`lib/graph/`, ~46k lines) already has
> `GraphPerformanceProfile` (v5.141) with device-tier LOD, gated
> animation controllers, and RepaintBoundaries. So this isn't a "no
> optimization" problem — it's likely one specific bottleneck hiding
> under all that prior work. This doc shows how to find it.

---

## The 4-Step Diagnostic Playbook

### Step 1: Check you're profiling correctly first

If you're testing via hot reload in **debug mode**, that alone can
make canvas-heavy graphs feel **3–5× laggier** than real users will
see. Debug mode disables AOT compilation, tree-shaking, and many
paint optimizations.

**Always profile in profile mode:**

```bash
flutter run --profile
```

Profile mode compiles with AOT (like release) but keeps DevTools
instrumentation. What you measure here is what real users experience.

**The diagnostics overlay warns you:** If you see a red `⚠ DEBUG MODE`
banner at the top of the overlay, you're in debug mode — your
measurements are invalid. Run `flutter run --profile` instead.

---

### Step 2: Split UI-thread vs Raster-thread lag

In the diagnostics overlay (long-press the top-right corner of the
graph screen to toggle), look at the **FRAME TIMES** section:

```
FRAME TIMES
UI      8.2ms   avg 7.1ms
Raster  24.1ms  avg 22.8ms  ⚠ JANK
```

- **UI thread spikes** (> 16ms) → rebuild storm. The
  `family_graph_engine_view.dart` State class has 27 `setState` calls
  and 20 `ref.watch` in one ~3000-line file — any small state change
  (drag, tap, provider tick) can rebuild far more than needed.
  - **Fix**: Split into smaller `Consumer` widgets scoped to just
    what they need, not one giant watcher. Use `ref.watch(provider.select(...))`
    to subscribe to only the field you read.
  - **Diagnostics overlay shows**: UI ms in red, "⚠ JANK" badge.

- **Raster thread spikes** (> 16ms) → too much GPU work per frame.
  The `EngineEdgePainter` supports a 3-pass render (shadow + ridge +
  body). Each pass is a `drawPath` call with potential `MaskFilter.blur`.
  - **Fix**: Confirm `allowShadowPass` / `allowRidgePass` are actually
    `false` on your test device's tier (see Step 3). If they're ON,
    your device tier was misdetected and every perf gate is being
    bypassed.
  - **Diagnostics overlay shows**: Raster ms in red, the PROFILE FLAGS
    section shows the actual state of each flag.

**Rule of thumb:**
- UI jank → widget tree problem → fix with `Consumer` + `.select()`
- Raster jank → paint problem → fix with fewer draw calls / blur ops

---

### Step 3: Verify device tier detection itself

The `GraphPerformanceProfile` is built from `DeviceTierCache` at graph
screen mount. If the cache misclassifies your phone (e.g. detects
"high" when it's actually mid/low), every perf gate in the profile is
silently bypassed — you get the full 3-pass edges, ambient particles,
connect-on-open animation, 100 MB image cache, etc.

**Check the DEVICE TIER section of the diagnostics overlay:**

```
DEVICE TIER
Tier: high (HIGH-END)
Initialized: true
```

If your phone has < 6 GB RAM and the overlay says "high", the
detection is wrong. The detection logic (in `device_tier.dart`) is:

```
low:  screenWidth < 360 OR pixelRatio < 2.0
mid:  screenWidth 360–414 AND pixelRatio 2.0–2.9
high: screenWidth > 414 OR pixelRatio >= 3.0
```

This means a Pixel 7 (1080×2400 @ 420dpi, pixelRatio 2.75) is
detected as **mid** — correct. But an iPhone 14 Pro (1179×2556 @
460dpi, pixelRatio 3.0) is detected as **high** even though it has
6 GB RAM — which is correct for the GPU but the 100 MB image cache
might still cause GC pressure.

**If the tier is wrong**, either:
1. Fix the detection thresholds in `device_tier.dart` (line 142)
2. Or override the tier manually for testing:
   ```dart
   // In main.dart, after DeviceTierCache.instance.initialize(...):
   // DeviceTierCache.instance.overrideForTest(DeviceTier.low);
   ```

---

### Step 4: Check node count vs culler

If a family graph has 50+ nodes, confirm the viewport culler is
actually **excluding off-screen nodes from paint** — not just from
hit-testing. The diagnostics overlay's CULLER section shows this:

```
CULLER
Visible: 12 / 247 (5%)
Members: 247  Rebuilds: 3  Skips: 47
Buffer: 200px  Threshold: 50px
rebuilt: viewport moved 75px > 50px threshold
```

**What to look for:**

| Metric | Good | Bad |
|--------|------|-----|
| Visible / Total | < 30% on large families | 100% (culler not working) |
| Rebuilds vs Skips | Skips >> Rebuilds | Rebuilds >> Skips (threshold too low) |
| Last action reason | "skipped: viewport moved 12px < 50px" | "rebuilt" every frame |

**If cull ratio is 100%** (every node visible), either:
1. The viewport is mis-aligned with graph-space (the blank-screen
   safety net fired — see `cull()` in `viewport_culler.dart`)
2. The buffer is too large for this family size
3. The graph is small enough that all nodes fit (fine — no action
   needed)

**If rebuilds >> skips** during a slow pan:
1. The rebuild threshold is too low for this device. The profile
   sets it to 50px (high) / 75px (mid) / 120px (low). If your device
   is detected as high but is actually struggling, bump the threshold
   in `graph_performance_profile.dart`.
2. Each rebuild costs O(N) where N = total positions. On a 247-node
   family, that's 247 bounding-box intersection tests per rebuild —
   cheap individually but expensive if firing every frame.

---

## How to toggle the diagnostics overlay

1. Run the app in **profile mode**: `flutter run --profile`
2. Navigate to the graph screen
3. **Long-press the top-right corner** of the graph screen for 500ms
4. The overlay appears, showing all 4 sections in real time
5. Long-press the overlay to hide it

The overlay is **compiled out of release builds** — it has zero
impact on production users.

---

## What each overlay section means

### FRAME TIMES
- **UI**: time spent on the Dart UI thread (build, layout, setState).
  Spikes → widget tree problem.
- **Raster**: time spent on the GPU raster thread (paint, drawPath,
  MaskFilter.blur). Spikes → paint problem.
- **avg**: rolling average of the last 10 frames. More stable than
  the instantaneous value.
- **⚠ JANK**: appears when the frame exceeded the 16.67ms budget
  (60 FPS). At 30 FPS the frame time is ~33ms.

### DEVICE TIER
- **Tier**: the detected `DeviceTier` (low/mid/high). Drives every
  perf gate via `GraphPerformanceProfile`.
- **Initialized**: whether `DeviceTierCache.initialize()` has
  resolved a non-zero screen size. On web this can be `false` before
  the first frame — the tier defaults to `mid` until then.

### CULLER
- **Visible / Total (X%)**: how many nodes are currently being built
  vs the total in the family. < 30% is good on large families.
- **Members**: total persons in the current family.
- **Rebuilds / Skips**: how many times `cull()` recomputed vs
  short-circuited. Skips >> Rebuilds is the goal.
- **Buffer / Threshold**: the current culler settings from the
  profile.
- **Last action reason**: why `cull()` last rebuilt or skipped.
  Helps you see if the threshold is too aggressive.

### PROFILE FLAGS
The actual state of each `GraphPerformanceProfile` flag. If a flag
says `ON` but you expected `OFF` (e.g. `Shadow pass ON` on a low-end
device), your device tier was misdetected — see Step 3.

### RENDER STATE
- **Zoom**: current camera zoom (1.0 = default, range 0.2–5.0).
- **LOD**: current level-of-detail tier (full / compact / mini / micro
  / dot). Low-end devices degrade to compact/mini at low zoom.
- **Edge quality**: current edge paint tier (full = 3-pass, chip =
  2-pass lighter, dot = 1-pass). Low-end devices use chip even at
  Lod.full.

---

## Common bottleneck patterns

### Pattern 1: "UI thread is always 20ms+ even when idle"
- **Cause**: A provider is firing on every animation tick (e.g.
  ambient particle controller, birthday pulse, memorial candle).
- **Check**: The PROFILE FLAGS section — if `Particles ON` and your
  device is low-end, the mote animation is ticking 60×/sec.
- **Fix**: The profile should disable particles on low-end. If the
  flag says ON but you're on a low-end device, the tier is misdetected.

### Pattern 2: "Raster thread spikes during pinch-zoom"
- **Cause**: The edge painter is re-rasterizing every edge on every
  zoom tick. The `painterActiveGesture` flag should skip this, but
  if it's not being set, the painter does full 3-pass × N edges per
  frame.
- **Check**: The RENDER STATE section during a pinch — if Edge quality
  says "full (3-pass)" and PROFILE FLAGS shows `Shadow pass ON`, the
  GPU is doing max work.
- **Fix**: On low-end, the profile forces EdgeQuality.chip +
  `Shadow pass OFF` + `Ridge pass OFF` = single body pass per edge.

### Pattern 3: "Cull ratio is 100% on a 200-node family"
- **Cause**: The blank-screen safety net fired (see `cull()` in
  `viewport_culler.dart`). This happens when the viewport is at the
  origin (0,0) but the graph layout placed all nodes far from the
  origin — typically on the first frame before `fitToView` runs.
- **Check**: The CULLER section — if Visible = 200 / 200 (100%) and
  the last action reason says "rebuilt: first call", this is expected
  for one frame. If it persists, the camera transform is broken.
- **Fix**: Usually self-corrects after `fitToView` runs. If it
  doesn't, check that `_camera.setContentBounds()` was called with
  the layout's bounding box.

### Pattern 4: "Rebuilds counter increments on every pan frame"
- **Cause**: The rebuild threshold is too low for the current pan
  velocity. The profile sets 50px (high) / 75px (mid) / 120px (low),
  but a fast flick can exceed that in one frame.
- **Check**: The CULLER section — if Rebuilds increments rapidly and
  the last action reason says "rebuilt: viewport moved 51px > 50px
  threshold", the threshold is too low.
- **Fix**: Bump `cullerRebuildThresholdPixels` in
  `graph_performance_profile.dart` for your tier. Note that higher
  thresholds mean nodes pop in later at the viewport edge.

---

## If you've ruled out all 4 steps

If the overlay shows:
- ✅ Profile mode (not debug)
- ✅ UI thread < 16ms
- ✅ Raster thread < 16ms
- ✅ Device tier correct
- ✅ Cull ratio < 30%
- ✅ Skips >> Rebuilds
- ✅ Profile flags match the tier

...and the graph STILL feels laggy, the bottleneck is likely:
1. **Input latency** (gesture recognition delay, not render delay) —
   check `_onScaleUpdate` in `interaction_mixin.dart` for expensive
   hit-testing.
2. **Network/database** — check Supabase realtime subscriptions for
   unnecessary re-fetches. The graph subscribes to several channels.
3. **Memory pressure** — check `flutter doctor` and the device's
   available RAM. The image cache may be evicting + re-decoding
   avatars.

Run `flutter doctor -v` and DevTools' Memory view to investigate
further.
