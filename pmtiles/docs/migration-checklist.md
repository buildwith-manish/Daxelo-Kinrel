# Phase A Migration Checklist (spec v3.0)

Per spec v3.0: "Do not proceed to Phase B until this is verified."

> **CRITICAL:** A checklist item is only "done" when there is a verification
> artifact attached (screenshot, log, test output). Code existing is not
> evidence that the code works.

## Step 0 — Determine whether custom PMTiles protocol code is needed (DONE ✅)

**Finding:** MapLibre Native has built-in PMTiles engine support. No custom
Kotlin/Swift protocol code is required on any platform.

| Platform | Bundled native version | PMTiles native since | Custom code needed? |
|---|---|---|---|
| Android | MapLibre Native **13.0** (via maplibre_android 0.3.5) | 11.7.0 | ❌ None |
| iOS | MapLibre Native **6.25** (via maplibre_ios 0.3.5) | 6.10.0 | ❌ None |
| Web | MapLibre GL JS 5.6.0 + pmtiles.js 3.0.0 | (JS lib required) | ✅ Just the `<script>` tag in `web/index.html` (already present) |

**Sources:**
- maplibre 0.3.5 changelog (official): "Android: update MapLibre Native to 13.0" and "iOS: update MapLibre Native to 6.25"
- MapLibre Android docs: "Starting MapLibre Android 11.7.0, PMTiles archives are supported as tile sources"
- MapLibre iOS docs: "MapLibre iOS 6.10.0, using PMTiles as a data source is supported"

**Action taken:** Deleted the broken `PmtilesProtocol.kt` — it forwarded a
`?range=` query param that nothing in the codebase ever set, and would never
have served a real tile. The native engine handles `pmtiles://https://...`
URLs directly.

## Step 1 — Per-platform code (DONE ✅)

- [x] **Android:** deleted `PmtilesProtocol.kt`. No custom code. Native engine handles `pmtiles://` URL scheme.
- [x] **iOS:** no custom code needed (no Swift plugin to write or remove). Native engine handles `pmtiles://` URL scheme.
- [x] **Web:** `web/index.html` loads `pmtiles@3.0.0` from jsdelivr CDN with unpkg fallback. `maplibre_web` 0.3.5 auto-registers the `pmtiles://` protocol via `interop.addProtocol('pmtiles', pmtilesProtocol.tile)`.

## Step 1b — Style JSON source declaration (DONE ✅)

- [x] `kinrel_dark_style.json` `openmaptiles` source now declares:
  ```json
  {
    "type": "vector",
    "url": "pmtiles://{{PMTILES_URL}}",
    "maxzoom": 16,
    "minzoom": 0,
    "attribution": "© OpenStreetMap contributors, © OpenMapTiles, © Planetiler"
  }
  ```
  (Previously used an incorrect `tiles: ["pmtiles://.../{z}/{x}/{y}.pbf"]` template array — PMTiles is a single-archive URL, not a per-tile template.)
- [x] `{{PMTILES_URL}}` placeholder is replaced at runtime by `_applyPmtilesSource()` in `family_map_screen.dart`, sourced from `--dart-define=PMTILES_URL=...` (default: `http://localhost:8080/mumbai.pmtiles` for dev).

## Step 2 — Zoom strategy (DONE ✅ — Option B)

- [x] Decision: **Option B** — single global `--maxzoom=16 --render_maxzoom=17`. All layers baked to z16; MapLibre overzooms z17 from z16 data.
- [x] Reasoning documented in `pmtiles/README.md`, `pmtiles/docs/deployment.md`, and inline comments in all four `build_*.sh` scripts.
- [x] Removed all "per-layer split" claims from docs (they were false — Planetiler's stock OpenMapTiles profile doesn't support per-layer zoom overrides).
- [x] Updated planet-wide size estimate to 70–110 GB (was 50–80 GB) to reflect that every layer goes to z16, not just buildings.

## Step 3 — Monaco independent verification (PENDING ⏳)

Per spec v3.0: "Before touching Mumbai or any larger extract: build Monaco, verify with an independent tool, then point the Flutter app at the Monaco archive and confirm real tiles render."

- [ ] Build Monaco test archive via `pmtiles/scripts/build_monaco.sh` (script needs to be written — Planetiler ships with a Monaco test extract)
- [ ] Verify archive with `pmtiles show monaco.pmtiles` (independent CLI):
  - [ ] Header parses (magic, version, root directory offset)
  - [ ] Directory listing returns tile entries
  - [ ] At least one tile decodes (decompress, MVT-parse, find a named layer)
- [ ] Point Flutter app (Android emulator + iOS simulator + web) at the Monaco archive
- [ ] Attach screenshots of the rendered Monaco map from each platform

**Honest note:** This step requires Flutter SDK + a running Android emulator or iOS simulator + a desktop browser. Cannot be verified in a headless Linux CI runner. Must be done on a developer machine or in a CI workflow with device testing capability.

## Step 4 — Mumbai validation (PENDING ⏳)

- [ ] Download Western Zone India PBF (~208 MB) via `pmtiles/scripts/download_sources.sh mumbai`
- [ ] Build `mumbai.pmtiles` via `pmtiles/scripts/build_mumbai.sh` (or GitHub Actions `Build PMTiles` workflow with `region=mumbai`)
- [ ] Verify with `pmtiles show mumbai.pmtiles` (independent CLI — header, directory, decoded tile)
- [ ] Serve locally via `pmtiles/scripts/serve_local.sh 8080`
- [ ] Point Flutter app at `http://localhost:8080/mumbai.pmtiles`
- [ ] Take screenshots of Mumbai at z4, z8, z11, z13, z14 with OpenFreeMap (current source)
- [ ] Take screenshots of Mumbai at same zooms with PMTiles
- [ ] Diff — visual parity required at z0–14
- [ ] At z15–17, verify MORE buildings render (real OSM data, not stretched z14)
- [ ] Verify all existing layers still render (background, water, landuse, parks, roads, bridges, tunnels, building 2D, kinrel-buildings-outline, kinrel-3d-buildings, kinrel-3d-buildings-warm-glow, family-places, family-buildings-*, all label/boundary layers)

**Honest note:** Same device-testing requirement as Step 3.

## Step 5 — Karnataka + India validation (PENDING ⏳)

Same build → independent verify → app-render → screenshot process for:
- [ ] Karnataka (Stage 2): bbox clip of Southern Zone PBF
- [ ] India (Stage 3): full India PBF, measure file size, extrapolate to planet

## Step 6 — Production cutover (PENDING ⏳)

**Single worldwide cutover only — no regional archives in production.**

- [ ] Stage 4 planet build complete: `planet.pmtiles` (~70–110 GB estimated per Option B)
- [ ] Upload `planet.pmtiles` to Cloudflare R2 (or equivalent static host with HTTP Range support)
- [ ] Update `pmtiles/config/sources.json` `active` field to the worldwide production URL
- [ ] Build APK + web bundle + iOS IPA
- [ ] Test on Android device (real, not emulator)
- [ ] Test on iOS device (real, not simulator)
- [ ] Test on web (Chrome, Firefox, Safari)
- [ ] **Test automatic fallback:** deliberately point `_kPmtilesSourceUrl` at a broken URL, confirm the app auto-swaps to OpenFreeMap within 10s and continues rendering
- [ ] Verify attribution is visible in the shipped app
- [ ] Commit + push + Vercel auto-deploy
- [ ] Monitor error logs for 24 hours

## Step 7 — Functional regression tests (PENDING ⏳)

Per spec: "No regressions in progressive loading, camera, animation, marker, or family-layer behavior"

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

## Step 8 — Attribution (DONE ✅ for source declaration; PENDING for visible attribution widget)

- [x] `kinrel_dark_style.json` openmaptiles source attribution:
  `© OpenStreetMap contributors, © OpenMapTiles, © Planetiler`
- [ ] Verify `SourceAttribution` widget renders correctly in bottom-right
- [ ] Verify attribution is also visible in light mode (OpenFreeMap liberty URL)

## Step 9 — Documentation (DONE ✅)

- [x] `pmtiles/docs/deployment.md` — hosting + update strategy + staging
- [x] `pmtiles/docs/migration-checklist.md` — this file (rewritten per spec v3.0)
- [x] `pmtiles/README.md` — overview + quickstart (Option A: CI, Option B: local)
- [x] `.github/workflows/build-pmtiles.yml` — CI workflow for all 4 regions

## Phase A.5 (Deferred per spec v3.0)

- [ ] Custom OpenMapTiles profile fork to produce true z17 building tiles (current workaround: `--render_maxzoom=17` overzooms from z16). Spec v3.0 explicitly defers this — nontrivial scope addition.
- [ ] Scheduled CI job to rebuild PMTiles from fresh OSM extracts weekly (cron already configured in `build-pmtiles.yml` for planet build).
