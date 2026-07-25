# Phase A Migration Checklist (spec v2.0)

Per spec: "Do not proceed to Phase B until this is verified."

## Step 0 — Prerequisites (DONE ✅)

- [x] Verified `maplibre: 0.3.5` is the pinned version
- [x] Verified `maplibre_android 0.3.5` wraps `android-sdk-opengl:13.0.+`
      (MapLibre Native Android 13.x — has `Style.addProtocol()` since 11.7.0)
- [x] Verified `maplibre_ios 0.3.5` wraps `MapLibre ~> 6.25`
      (MapLibre Native iOS 6.25 — has `MLNStyle.addProtocol()`)
- [x] Verified `maplibre_web 0.3.5` auto-registers `pmtiles://` protocol
      via `interop.addProtocol('pmtiles', pmtilesProtocol.tile)` in
      `map_state.dart:48-49` — requires pmtiles.js script tag (DONE)
- [x] No version bump needed. 0.3.5 supports PMTiles on all 3 platforms.

## Step 1 — Tile Generation Pipeline

- [x] Download Planetiler JAR v0.10.2 to `pmtiles/bin/planetiler.jar`
- [x] Write `pmtiles/scripts/download_planetiler.sh` (idempotent)
- [x] Write `pmtiles/scripts/download_sources.sh` (Geofabrik extracts)
- [x] Write `pmtiles/scripts/build_mumbai.sh` (Stage 1 validation build)
      - Per-layer zoom config: base z0-14, buildings z0-16 + overzoom to z17
      - Uses `--maxzoom=16 --render_maxzoom=17` (Planetiler profile hard cap)
- [ ] Write `pmtiles/scripts/build_karnataka.sh` (Stage 2 validation)
- [ ] Write `pmtiles/scripts/build_india.sh` (Stage 3 validation + size estimate)
- [ ] Write `pmtiles/scripts/build_planet.sh` (Stage 4 production cutover)
- [ ] Download Western Zone India PBF (218MB) — IN PROGRESS
- [ ] Download water-polygons auxiliary data (885MB) — IN PROGRESS
- [ ] Generate `pmtiles/output/mumbai.pmtiles` (~20-50MB est)
- [ ] Verify archive contains `building` source-layer with render_height
      field by decoding a z14 Mumbai tile with mapbox-vector-tile

### Per-layer Zoom Config (spec v2.0)

Per spec: "Do not apply one zoom range to the entire schema."

| Layer group | minzoom | maxzoom |
|---|---|---|
| Base schema (roads, water, landuse, parks, labels, POIs, etc.) | 0 | 14 |
| Buildings layer only | 0 | 16 (with `--render_maxzoom=17` for overzoom) |

**Implementation:** `--maxzoom=16 --render_maxzoom=17` in build scripts.
Planetiler's OpenMapTiles profile YAML hard-caps buildings at z16, so
true z17 building tiles require a profile fork (out of scope for Phase A).

## Step 2 — Flutter Integration

- [x] Add `pmtiles@3.0.0` script tag to `web/index.html` (web)
- [x] Add pmtiles fallback CDN in `web/index.html`
- [x] Update `kinrel_dark_style.json` openmaptiles source to use
      `pmtiles://{{PMTILES_URL}}/{z}/{x}/{y}.pbf` placeholder
- [x] Update `family_map_screen.dart` `_loadStyleJson` to patch
      `{{PMTILES_URL}}` placeholder with `_kPmtilesSourceUrl` at runtime
- [x] Write `PmtilesProtocol.kt` for Android (registers pmtiles://
      protocol via `Style.addProtocol()`)

## Step 3 — Staging & Hosting

- [x] Write `pmtiles/scripts/serve_local.sh` for dev (range-request
      HTTP server with CORS)
- [ ] **Stage 1 (Mumbai validation):** run local server, verify PMTiles
      loads in browser, take visual diff screenshots vs OpenFreeMap
- [ ] **Stage 2 (Karnataka validation):** repeat parity check
- [ ] **Stage 3 (India validation):** measure file size, extrapolate to
      planet, verify hosting budget fit
- [ ] **Stage 4 (Planet production build):** spin up 32-64GB RAM VM,
      build planet.pmtiles, upload to Cloudflare R2
- [ ] Configure `tiles.daxelo-kinrel.dev` → R2 public URL

## Step 4 — Visual Parity Verification (Stage 1)

Per spec: "Mumbai-stage visual diff against the current OpenFreeMap map
to confirm parity"

- [ ] Take screenshots of Mumbai at z4, z8, z11, z13, z14 with OpenFreeMap
- [ ] Take screenshots of Mumbai at same zooms with PMTiles
- [ ] Diff screenshots — visual parity required at z0-14
- [ ] At z15-17, verify MORE buildings render (real OSM data, not stretched z14)
- [ ] Verify all existing layers still render:
  - [ ] background, water, landuse, parks, roads, bridges, tunnels
  - [ ] building (2D fill)
  - [ ] kinrel-buildings-outline (2D outline)
  - [ ] kinrel-3d-buildings (3D extrusion)
  - [ ] kinrel-3d-buildings-warm-glow (tall-building accent)
  - [ ] family-places (GeoJSON source — unchanged)
  - [ ] family-buildings-glow, family-buildings, family-buildings-fallback
  - [ ] All label layers (place, poi, water_name, transportation_name)
  - [ ] All boundary layers

## Step 5 — File-Size Validation (Stage 3)

Per spec: "India-stage file-size measurement to validate the worldwide
estimate, before the production cutover"

- [ ] Build India PMTiles archive (~16GB RAM required)
- [ ] Measure file size of `india.pmtiles`
- [ ] Extrapolate to planet scale (India ≈ 2.4% of planet land area)
- [ ] Verify planet-size estimate fits Cloudflare R2 budget
      (free tier: 10GB; paid: $0.015/GB/month)

## Step 6 — Functional Regression Tests

Per spec: "No regressions in progressive loading, camera, animation, marker,
or family-layer behavior"

- [ ] Progressive loading (8-phase loader) still works
- [ ] Camera transitions (zoom, pitch, bearing) smooth
- [ ] Marker rendering (avatar markers, cluster markers) intact
- [ ] Family building extrusion (per-place-type colors) intact
- [ ] Path rendering (relationship lines) intact
- [ ] Selection logic (tap to focus, tap to deselect) intact
- [ ] Caching (camera state restoration) intact
- [ ] Theme system (dark/light toggle) intact
- [ ] Cold start < 2 seconds
- [ ] Tile loading speed ≥ OpenFreeMap baseline

## Step 7 — Attribution

Per ODbL license: attribution is required.

- [x] Updated `kinrel_dark_style.json` openmaptiles source attribution:
      `© OpenStreetMap contributors, © OpenMapTiles, © Planetiler`
- [ ] Verify `SourceAttribution` widget renders correctly in bottom-right
- [ ] Verify attribution is also visible in light mode (OpenFreeMap liberty URL)

## Step 8 — Production Cutover (Stage 4 only)

**Per spec: "Production only cuts over once the full worldwide archive is
built and verified."**

- [ ] Stage 4 planet build complete: `planet.pmtiles` (~50-80GB est)
- [ ] Upload `planet.pmtiles` to Cloudflare R2
- [ ] Update `_kPmtilesSourceUrl` in `family_map_screen.dart` from
      OpenFreeMap URL → `https://tiles.daxelo-kinrel.dev/planet.pmtiles`
- [ ] Build APK + web bundle
- [ ] Test on Android device (real, not emulator)
- [ ] Test on web (Chrome, Firefox, Safari)
- [ ] Commit + push + Vercel auto-deploy
- [ ] Monitor error logs for 24 hours

## Step 9 — Documentation

- [x] `pmtiles/docs/deployment.md` — hosting + update strategy + staging
- [x] `pmtiles/docs/migration-checklist.md` — this file
- [x] `pmtiles/README.md` — overview + quickstart

## Phase A.5 (Out of Scope for Initial Migration)

- [ ] iOS Swift plugin to register `pmtiles://` protocol via
      `MLNStyle.addProtocol()`. Until then, iOS uses OpenFreeMap fallback.
- [ ] Custom OpenMapTiles profile fork to produce true z17 building tiles
      (current workaround: --render_maxzoom=17 overzooms from z16)
- [ ] Scheduled CI job to rebuild PMTiles from fresh OSM extracts monthly
