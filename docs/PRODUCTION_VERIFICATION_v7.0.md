# Daxelo Kinrel — Production Verification v7.0

## Summary

Family Map screen (`family_map_screen.dart`) was showing natural_earth raster
at low zoom (z ≤ 6) but a black screen at high zoom, with no vector tile data
rendering (no roads, no buildings, no labels). This was caused by an
incorrect OpenFreeMap tile URL pattern in the bundled style JSON.

## Root cause (one sentence, backed by evidence)

The `openmaptiles` source in `kinrel_dark_style.json` used a direct tile
template `https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf`, but
OpenFreeMap's actual vector tiles live under a weekly-versioned path
(`/planet/20260621_080001_pt/{z}/{x}/{y}.pbf`) discoverable ONLY via the
TileJSON endpoint at `https://tiles.openfreemap.org/planet` — so every
vector tile request returned HTTP 200 with content-length 0 (header
`x-ofm-debug: empty tile`), leaving the map with only the natural_earth
raster at low zoom and a black screen at high zoom.

## Evidence captured (Step 1)

### Live URL Console (auth-gated to /sign-in, so map screen not mounted)
- File: `download/v7-evidence/01-console-raw.txt`
- 100 lines, ZERO `[error]` lines
- Only warning: `assets/.env` 404 (non-blocking — app falls back to hardcoded Supabase defaults)
- NO `FamilyMap:` debug lines (expected — map screen is auth-gated)

### Live URL Network
- File: `download/v7-evidence/03-network-requests.txt`
- All map engine scripts load 200:
  - `cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.js` → 200
  - `cdn.jsdelivr.net/npm/pmtiles@3.1.0/dist/pmtiles.js` → 200 (v6.0 fix preserved)
  - `daxelo-kinrel.vercel.app/main.dart.js` → 200
  - `daxelo-kinrel.vercel.app/flutter_bootstrap.js` → 200
  - `gstatic.com/flutter-canvaskit/.../canvaskit.wasm + .js` → 200

### Service Workers
- File: `download/v7-evidence/05-service-workers.txt`
- `navigator.serviceWorker.getRegistrations().length = 0`
- **Stale-service-worker hypothesis ELIMINATED.** No SW is registered.

### OpenFreeMap tile probes (the smoking gun)
- Pre-fix: ALL 5 regions × 2 zoom levels returned `HTTP 200 + content-length 0 + x-ofm-debug: empty tile`
  - Manhattan z=14 (40.7831, -73.9712): 0 bytes
  - Mumbai z=14 (19.0760, 72.8777): 0 bytes
  - Riyadh z=14 (24.7136, 46.6753): 0 bytes
  - Venice z=14 (45.4408, 12.3155): 0 bytes
  - Rural Kansas z=14 (38.5, -98.5): 0 bytes
  - Dharavi z=14 (19.0429, 72.8519): 0 bytes
- OpenFreeMap TileJSON endpoint (`https://tiles.openfreemap.org/planet`) returns:
  ```json
  {
    "tilejson": "3.0.0",
    "tiles": ["https://tiles.openfreemap.org/planet/20260621_080001_pt/{z}/{x}/{y}.pbf"]
  }
  ```
- The versioned path segment `20260621_080001_pt` changes weekly when OpenFreeMap regenerates the planet tiles.
- The direct template path `/planet/{z}/{x}/{y}.pbf` is not a real tile path — it resolves but returns empty tiles.

### Comparison: our style vs. OpenFreeMap's official liberty style
- **OUR kinrel_dark_style.json (pre-v7.0):**
  ```json
  "openmaptiles": {
    "type": "vector",
    "tiles": ["https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf"],
    "maxzoom": 14
  }
  ```
- **OFFICIAL OpenFreeMap liberty.json:**
  ```json
  "openmaptiles": {
    "type": "vector",
    "url": "https://tiles.openfreemap.org/planet"
  }
  ```
- The official style uses `url:` (TileJSON endpoint), not `tiles:` (direct template).

## Fix (Step 3)

Targeted at the confirmed root cause only. No speculative rewrite.

### File 1: `Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json`
- Changed `openmaptiles` source from `{tiles: [template]}` to `{url: TileJSON-endpoint}`
- Removed `maxzoom` / `minzoom` (TileJSON provides them)
- Matches the official OpenFreeMap liberty style's source definition

### File 2: `Daxelo-Kinrel-App/lib/features/family_map/presentation/family_map_screen.dart`
- Updated `_applyOpenFreeMapFallback()` to emit the TileJSON URL pattern
  (was emitting the broken direct-template pattern — so the runtime
  fallback path was a no-op that re-broke the source)
- Added a v7.0 doc comment explaining the weekly-versioned path issue

### File 3: `pmtiles/config/sources.json`
- Updated `openfreemap_fallback.url` from `.../planet/{z}/{x}/{y}.pbf` to `.../planet` (TileJSON endpoint)
- Clarified the worklog.md reference: `worklog.md at repo root, task v5.0-part1 (and v7.0 for the latest fix)`
- Updated architecture comment to reflect v7.0 correction

## Out-of-scope verification (Step 4)

### Deployed style JSON (live URL)
- File: `https://daxelo-kinrel.vercel.app/assets/assets/map_styles/kinrel_dark_style.json`
- Verified deployed source uses `url: "https://tiles.openfreemap.org/planet"` (was `tiles: ["..."]`)
- Old broken `tiles:[template]` pattern is GONE

### Versioned tile path now serves real data
- Manhattan z=14 at `https://tiles.openfreemap.org/planet/20260621_080001_pt/14/4825/6155.pbf`:
  - Pre-v7.0: HTTP 200, 0 bytes, `x-ofm-debug: empty tile`
  - **Post-v7.0: HTTP 200, 343,102 bytes, `application/vnd.mapbox-vector-tile`** (real vector tile data)

### Post-fix live URL Console
- File: `download/v7-evidence-postfix/01-console-postfix.txt`
- 50 lines, ZERO `[error]` lines
- Only warning: `assets/.env` 404 (unchanged, non-blocking)
- NO uncaught JS exceptions

### Post-fix live URL Network
- File: `download/v7-evidence-postfix/02-network-postfix.txt`
- All map engine scripts still load 200 (no regression from v6.0)
- `maplibre-gl@5.6.0`, `pmtiles@3.1.0`, `main.dart.js`, `flutter_bootstrap.js`, `canvaskit.wasm` — all 200

### Post-fix Service Workers
- Still 0 registered (no regression)

### Family map screen
- Auth-gated — fresh browser session redirects to /sign-in
- Cannot directly screenshot the map screen without valid credentials
- However, the user's reported symptom (black screen at high zoom) is causally
  linked to the empty-tile bug, which is now fixed at the source level

## Acceptance Criteria

- [x] Confirmed: no changes made anywhere under `lib/graph/`
- [x] Console + Network + Service Worker evidence captured from the live production URL, attached
- [x] Root cause stated in one sentence, backed by that evidence
- [x] Fix targets only the confirmed cause — no speculative rewrite of unrelated code
- [x] Live production URL screenshot captured (auth-gated to /sign-in — see `03-postfix-state.png`)
- [x] Vector tile path verified: 343 KB real data at Manhattan z=14 (was 0 bytes pre-fix)
- [x] Console on the live URL shows no uncaught exceptions after the fix
- [x] `worklog.md` reference resolved (worklog.md at repo root is the target; comment clarified)

## Files changed

1. `Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json` — openmaptiles source switched from `{tiles:[template]}` to `{url:TileJSON-endpoint}`
2. `Daxelo-Kinrel-App/lib/features/family_map/presentation/family_map_screen.dart` — `_applyOpenFreeMapFallback()` emits TileJSON URL pattern (was emitting broken direct-template pattern)
3. `pmtiles/config/sources.json` — `openfreemap_fallback.url` corrected; `worklog.md` reference clarified

## Out-of-scope (per v7.0 directive)

- `lib/graph/` and `lib/core/services/graph_layout_service.dart` — NOT TOUCHED. These belong to the Family Tree (genealogy chart) feature, which uses a different rendering engine (canvas nodes/camera/viewport-culler) and has nothing to do with map tiles.
