# Phase A Migration Checklist

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
- [x] Write `pmtiles/scripts/build_mumbai.sh` (Planetiler + bbox clip)
- [ ] Download Western Zone India PBF (218MB) — IN PROGRESS
- [ ] Generate `pmtiles/output/mumbai.pmtiles` (~20-50MB est)
- [ ] Verify archive contains `building` source-layer with render_height
      field by decoding a z14 Mumbai tile with mapbox-vector-tile

### Maxzoom Note

Spec says `maxzoom=17 (hard minimum)`. Planetiler's OpenMapTiles profile
caps at `maxzoom=16`. We generate `maxzoom=16` and rely on MapLibre's
overzoom for z17+. This is documented in `docs/deployment.md` as a
known limitation. **2 zoom levels better than OpenFreeMap (z14 cap).**

## Step 2 — Flutter Integration

- [x] Add `pmtiles@3.0.0` script tag to `web/index.html` (web)
- [x] Add pmtiles fallback CDN in `web/index.html`
- [x] Update `kinrel_dark_style.json` openmaptiles source to use
      `pmtiles://{{PMTILES_URL}}/{z}/{x}/{y}.pbf` placeholder
- [x] Update `family_map_screen.dart` `_loadStyleJson` to patch
      `{{PMTILES_URL}}` placeholder with `_kPmtilesSourceUrl` at runtime
- [x] Write `PmtilesProtocol.kt` for Android (registers pmtiles://
      protocol via `Style.addProtocol()`)

## Step 3 — Hosting

- [x] Write `pmtiles/scripts/serve_local.sh` for dev (range-request
      HTTP server with CORS)
- [ ] Run local server, verify PMTiles loads in browser
- [ ] Upload `mumbai.pmtiles` to Cloudflare R2 (prod)
- [ ] Configure `tiles.daxelo-kinrel.dev` → R2 public URL

## Step 4 — Visual Parity Verification

Per spec: "Map matches current visual output layer-for-layer at z0–14"

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

## Step 5 — Functional Regression Tests

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

## Step 6 — Attribution

Per ODbL license: attribution is required.

- [x] Updated `kinrel_dark_style.json` openmaptiles source attribution:
      `© OpenStreetMap contributors, © OpenMapTiles, © Planetiler`
- [ ] Verify `SourceAttribution` widget renders correctly in bottom-right
- [ ] Verify attribution is also visible in light mode (OpenFreeMap liberty URL)

## Step 7 — Production Cutover

- [ ] Upload `mumbai.pmtiles` to Cloudflare R2
- [ ] Update `_kPmtilesSourceUrl` in `family_map_screen.dart` from
      `http://localhost:8080/mumbai.pmtiles` (dev) →
      `https://tiles.daxelo-kinrel.dev/mumbai.pmtiles` (prod)
- [ ] Build APK + web bundle
- [ ] Test on Android device (real, not emulator)
- [ ] Test on web (Chrome, Firefox, Safari)
- [ ] Commit + push + Vercel auto-deploy
- [ ] Monitor error logs for 24 hours

## Step 8 — Documentation

- [x] `pmtiles/docs/deployment.md` — hosting + update strategy
- [x] `pmtiles/docs/migration-checklist.md` — this file
- [ ] `pmtiles/README.md` — overview + quickstart

## Phase A.5 (Out of Scope for Initial Migration)

- [ ] iOS Swift plugin to register `pmtiles://` protocol via
      `MLNStyle.addProtocol()`. Until then, iOS uses OpenFreeMap fallback.
- [ ] India-wide build (Phase 3 in spec) — needs ~16GB RAM
- [ ] Planet-wide build (Phase 4) — needs ~32-64GB RAM, hours of build time
- [ ] Scheduled CI job to rebuild PMTiles from fresh OSM extracts monthly
