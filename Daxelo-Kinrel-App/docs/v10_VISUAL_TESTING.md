# v10 Visual-System — Manual Testing Checklist

> Verify the v10 Family Map visual overhaul on the Vercel preview deployment.
> Each scenario lists: setup → expected → how to capture evidence.
> Structural validation (48/48 checks) already passed locally via
> `node /home/z/my-project/scripts/v10_json_validate.mjs`; this checklist
> confirms the visual end-result in a real browser.

## Pre-flight

1. **Push to `origin/main`** so Vercel auto-deploys.
2. Wait for the Vercel preview build to finish.
3. Open the preview URL in Chrome desktop + Android Chrome.
4. Hard-refresh to bypass CDN cache: `Ctrl+Shift+R` / long-press reload.
5. Open DevTools → Console. Filter by `FamilyMap` to see v10 logs.

Expected console lines on a healthy load:

```
✅ FamilyMap: style loaded (attempt=0, web=true)
🔤 FamilyMap v9.0: patched N multi-script fontstack(s) ...
🔆 FamilyMap v10: injected family-proximity buffer (M place(s), N polygon ring(s))
   into kinrel-3d-buildings-family-proximity-glow filter
✅ FamilyMap: added family-places source (web)
```

If you see `⚠️ FamilyMap v10: family-places data not ready in time for
proximity buffer injection` — that's fine, the proximity glow won't appear
on first paint but will appear after the next style reload (e.g., when
the user toggles theme or focuses a pin).

---

## Scenario 1 — Default camera shows 3D buildings immediately

**Setup:** Fresh load of Family Map (no restored state — clear site data
first if needed: DevTools → Application → Storage → Clear site data).

**Expected:**
- Camera animates from zoom 4 → 5.5 over ~1.5s.
- **Camera is tilted to ~50° pitch** and rotated to **-17° bearing** by
  the end of the animation — 3D building extrusions are visible
  immediately at the end of the entrance, not flat top-down.
- After animation completes, the map shows 3D buildings in the visible
  viewport (for any city with OSM building data — try Mumbai, Bengaluru,
  or any dense downtown at zoom ≥ 13).

**Evidence:** Screenshot at t=2s after load.

**Failure modes:**
- If the camera is flat (pitch=0) at the end of entrance →
  `MapVisualConstants.defaultPitch` not being read; check
  `family_map_screen.dart` line ~1873.
- If 3D buildings don't appear even at pitch 50 → fog/sky layer is
  erroring; check console for `maplibre:` errors.

---

## Scenario 2 — Atmosphere (fog + sky) renders at the horizon

**Setup:** From the default load, wait for entrance animation to finish,
then zoom into any city to zoom 14–16 (3D buildings clearly visible).

**Expected:**
- **At pitch 50° with bearing -17°**, the top of the canvas shows a
  warm-amber horizon gradient — `#2A2030` blending down into the dark
  `#0B0F17` sky color.
- The horizon is NOT pure black — there's a visible warm tint at the
  sky/ground boundary.
- Buildings in the distance (toward the horizon) fade slightly into the
  fog color — this is the `fog.color` depth-haze effect.

**Evidence:**
- Screenshot at pitch 50, zoom 15, looking toward a downtown cluster.
- Compare against an old v9 screenshot — the v10 should clearly show
  the warm horizon gradient that v9 lacked.

**Failure modes:**
- Pure black sky with no warm tint → `fog.high-color` not applied; verify
  in DevTools Network panel that the deployed `kinrel_dark_style.json`
  contains `"fog": { "high-color": "#2A2030", ... }`.
- Sky renders solid color with no horizon blend → `sky` LAYER's
  `atmosphere-blend` zoom-interpolation not respected; verify the
  deployed JSON has the `sky` layer at index 1 with
  `"sky-type": "atmosphere"`.

---

## Scenario 3 — 3D building extrusion + warm-glow render correctly

**Setup:** Zoom to a downtown area with mid-rise buildings (zoom 15–17).
Mumbai Fort, Bengaluru MG Road, or any dense commercial district works.

**Expected:**
- Buildings extrude in 3D with the height-graded color:
  - height 0–15m  → `#1E1D2A` (darkest purple-grey)
  - height 35m    → `#2A2638`
  - height 70m    → `#3A3450`
  - height 200m+  → `#4A4060` (lightest purple)
- Tall buildings show a warm-glow overlay (amber→gold tint) on top of
  the base extrusion — the `kinrel-3d-buildings-warm-glow` layer.
- Building outlines (`kinrel-buildings-outline`) appear as thin `#4A4060`
  lines that thicken from 0.3px at zoom 11 to 1.5px at zoom 22.
- `fill-extrusion-vertical-gradient` is visible — building sides are
  darker than tops (lighting from above).

**Evidence:**
- Screenshot at zoom 16, pitch 50, bearing -17.
- Screenshot at zoom 18 (close-up) showing outline thickness.

**Failure modes:**
- Buildings flat (no extrusion) → check `render_height` is being read;
  OpenFreeMap's `building` source-layer must include `render_height`.
- Warm-glow missing on low-end devices → expected if
  `MapQualityTier.low` is active (controlled layer is hidden). Verify
  in console: `🎛️ MapQualityTier initialized: low/mid/high`.

---

## Scenario 4 — Family-proximity amber glow around family places

**Setup:** Sign in as a user with at least 2 family places saved
(current_home, childhood_home, etc.) within 150m of OSM buildings.

**Expected:**
- Each family place has a **150m-radius amber glow** on surrounding OSM
  buildings — `#E8612A` fill-extrusion overlaying the base building.
- The glow is visible from zoom 13+ (the layer's `minzoom`).
- The glow fades in as you zoom in (interpolated opacity 0.3 at z13 →
  0.6 at z22).
- The family marker pin (extruded cylinder in the place's color) is
  still visible on top of the proximity glow — the proximity glow is
  BELOW the `family-buildings` layer.

**Evidence:**
- Screenshot at zoom 15, pitch 50, centered on a family place with
  surrounding buildings.
- Screenshot at zoom 13 — glow should be visible but fainter.

**Failure modes:**
- No amber glow at all → check console for the v10 injection log line:
  `🔆 FamilyMap v10: injected family-proximity buffer (...)`. If absent,
  the family-places data wasn't ready in 1.5s — try focusing a pin then
  refreshing.
- Glow appears on ALL buildings (not just near family places) → the
  `within` filter expression wasn't injected correctly; check the
  runtime patch in `_injectFamilyProximityBuffer()`.
- Glow visible on low-end devices → expected if `MapQualityTier.low` is
  active; the proximity-glow layer is in `_kControlledLayerIds` and
  should be hidden alongside the warm-glow layer.

---

## Scenario 5 — Roads are desaturated; motorway remains prominent

**Setup:** Zoom to a city with a mix of road classes (motorway +
secondary + minor). Mumbai's Western Express Highway works well.

**Expected:**
- **Motorway** (`road_motorway`, `road_motorway_link`): `#4A3F63` —
  brightest, most saturated purple. Stands out clearly.
- **Trunk/Primary** (`road_trunk_primary`): `#3A3252` — slightly
  desaturated.
- **Secondary/Tertiary, Minor, Service, Track**: `#221E36` — very dark,
  nearly invisible against the `#131416` background. This is intentional
  — the desaturation pushes the eye toward the motorway network.
- All road lines have **rounded caps and joins** — no visible "stairstep"
  artifacts at intersections or line endpoints.
- Labels remain readable (text-halo `#0D0D0D` width 2.5 ensures
  contrast over any road color).

**Evidence:**
- Screenshot at zoom 14 showing a motorway interchange with secondary
  roads branching off.
- Zoom in to 16+ and verify the line-cap roundness at endpoints.

**Failure modes:**
- Roads look uniformly bright (no desaturation hierarchy) → old cached
  style JSON; hard-refresh and check Network panel for the new
  `kinrel_dark_style.json` (size should be ~190KB).
- Sharp line endpoints (square caps) → `line-cap: round` missing on a
  layer; check the deployed JSON.

---

## Scenario 6 — Quality tier behaves correctly on low-end devices

**Setup:** Test on a low-end Android device (e.g., 2GB RAM, Android 9+).
Alternatively, desktop Chrome with CPU throttling (6x slowdown) +
DevTools "Low-end mobile" preset.

**Expected:**
- Console shows `🎛️ MapQualityTier initialized: low` (not mid/high).
- `kinrel-3d-buildings-warm-glow` layer is HIDDEN — no warm-glow overlay
  on buildings.
- `kinrel-3d-buildings-family-proximity-glow` layer is also HIDDEN — no
  amber proximity tint.
- Base `kinrel-3d-buildings` extrusion still renders — buildings are 3D
  but use the simple height-graded color only.
- Frame rate stays closer to 60 FPS in dense downtowns (compared to
  mid/high tier which would drop due to the extra extrusion passes).

**Evidence:**
- Screenshot on the low-end device — buildings should be uniformly
  purple-grey, no amber/warm tint.
- Performance trace in DevTools showing frame times.

**Failure modes:**
- Warm-glow visible on low-tier → `_kControlledLayerIds` in
  `map_quality_tier.dart` missing the layer ID, OR
  `applyToStyleJson()` not being called. Check console for
  `🎛️ MapQualityTier: hid N controlled layer(s) for low tier`.
- Map fails to load entirely → check that `applyToStyleJson()` returns
  the patched JSON correctly; the function is wrapped in try/catch
  and returns the unpatched input on any error.

---

## Reduced-motion path (bonus check)

**Setup:** Enable "Reduce motion" in OS settings (macOS: System Settings
→ Accessibility → Display → Reduce motion; Android: Settings →
Accessibility → Remove animations).

**Expected:**
- Cinematic entrance animation is **skipped** — camera snaps directly
  to zoom 5.5, pitch 50, bearing -17 with no animation.
- All other behavior unchanged.

**Evidence:** Screen recording of the load.

---

## Post-test — file an issue if any scenario fails

For each failing scenario, attach:
1. The screenshot/recording.
2. The full console log (filtered to `FamilyMap`).
3. The deployed `kinrel_dark_style.json` URL (Network panel →
   kinrel_dark_style.json → Response).
4. The result of `node /home/z/my-project/scripts/v10_json_validate.mjs`
   run against the deployed JSON (download it first).
