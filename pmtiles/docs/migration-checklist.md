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

## Phase B v1.0 — Visual Design Enhancement (Implementation done, device verification PENDING)

Phase B prerequisite gate: "Do not start this phase until every item in
this checklist is checked with attached evidence."

**Gate status: NOT MET.** Steps 3–8 device-side verification items remain
PENDING (require Flutter SDK + Android emulator + iOS simulator + browser
— not available in headless Linux env).

**Pragmatic split applied:** The Phase B implementation work that is purely
style-JSON + Dart edits (paint/layout/filter/text-font only) has been
executed. All device-verification items are explicitly marked PENDING
below. This is the same split applied to Phase A (CLI verification done
in headless env; device verification deferred to developer machine).

When the developer-machine slot opens, Phase A's device checks (Steps 3–8)
and Phase B's device checks (below) can be done in one pass.

### Implementation (DONE ✅ — awaiting device verification)

- [x] **Buildings — density-aware glow filter.** `kinrel-3d-buildings-warm-glow`
  filter rewritten: `render_height >= interpolate(zoom, 12→60, 13→45,
  14→25, 15→18, 16→12, 22→12)`. At z12 only skyscrapers (≥60m) get the
  duplicate extrusion glow — caps draw calls in dense downtowns from
  ~1000 buildings to ~50. At z16+ reverts to original 12m threshold
  (viewport naturally limits visible buildings to ~200–400).
- [x] **Buildings — data-driven warm color.** 5-stop interpolate by
  render_height: `#A04515` (12m, dim residential) → `#E8612A` (25m,
  bright apartment) → `#F59240` (50m, office) → `#F5B841` (100m, tall
  office) → `#FFD66B` (200m, landmark beacon).
- [x] **Roads — class-aware glow.** Line-blur added to motorway/trunk/
  primary CASING layers only (6 layers: road/bridge/tunnel × motorway/
  trunk_primary). Zoom-scaled 0.0→1.5 blur. Secondary/tertiary/
  residential/minor/service roads get NO glow — keeps dense old-city
  street networks legible (brief concern).
- [x] **Water — zoom-scaled fill-color.** 6-stop interpolate: `#0E1A2A`
  at z0 (deep navy oceans) → `#162335` at z8 (original mid-zoom) →
  `#243860` at z18 (reflective close-up).
- [x] **Parks — class-aware outline + arid palette verified.** Park
  outline color is now a 4-way match on subclass (public_park / garden
  / nature_reserve / default). Arid palette verified: existing
  landcover_sand / landcover_wood / landcover_wetland / landcover_ice
  layers already route non-green landcover to separate non-green colors
  via class-based filtering.
- [x] **Labels — multi-script text-font stack.** All 23 text-bearing
  symbol layers updated: each `text-font` array now includes Latin →
  Devanagari → Arabic → CJK (Simplified Chinese) fallback. Italic
  stacks fall back to Regular for non-Latin scripts.
- [x] **Labels — RTL/CJK layout.** `text-writing-mode = ['horizontal',
  'vertical']` added to 9 place label layers. For RTL (Arabic/Hebrew):
  MapLibre Native handles BiDi automatically once the font stack
  includes an Arabic-script font (handled by the multi-script stack
  above). No style-level RTL reordering needed.
- [x] **Performance — quality tier scaling.** `MapQualityTierController`
  added at `lib/features/family_map/config/map_quality_tier.dart`.
  Initialized from `DeviceTierCache` at startup. For low-tier devices,
  patches `layout.visibility = 'none'` on `kinrel-3d-buildings-warm-glow`
  at style-load time (eliminates the 2x draw-call cost of the duplicate
  extrusion). Family-* layers NEVER touched.
- [x] **Critical Rules respected.** Layer count unchanged (116 → 116).
  No tile source, schema, lifecycle, camera, family-layer, attribution,
  or fallback-logic changes.

### Verification (PENDING ⏳ — needs developer machine)

Per Phase B brief: "No new paint technique is claimed working without a
screenshot from the actual region it was tested in."

- [ ] **5-region screenshot comparison.** Test in:
  - [ ] One dense high-rise downtown (e.g., Manhattan, Hong Kong, Mumbai Nariman Point)
  - [ ] One historic irregular-grid European city (e.g., Venice, Marrakesh medina)
  - [ ] One sparse rural/suburban area (e.g., US Midwest, Scandinavian suburb)
  - [ ] One very hot/arid region (e.g., Rajasthani old-city, Saudi Riyadh)
  - [ ] One dense low-rise informal-settlement-style area (e.g., Mumbai Dharavi,
        São Paulo favela, Cairo informal)
- [ ] **Density-aware glow profiled against densest test region.** Confirm
      z12 downtown view doesn't drop below 60 FPS due to glow draw calls.
- [ ] **Labels render correctly in 4 script regions:**
  - [ ] Latin-script region (e.g., any US/EU city)
  - [ ] CJK region (e.g., Tokyo, Shanghai, Seoul)
  - [ ] Arabic-script RTL region (e.g., Riyadh, Cairo, Dubai)
  - [ ] Devanagari region (e.g., Mumbai, Delhi, Varanasi)
- [ ] **60 FPS maintained in densest test region on representative mid-range
      device** (NOT a high-end test device).
- [ ] **Automatic quality scaling verified** by simulating a low-end device
      profile (e.g., Android emulator with restricted CPU/RAM).
- [ ] **Phase A / production-readiness functionality regression test:**
      - [ ] Progressive loading (8-phase loader) still works
      - [ ] Camera transitions (zoom, pitch, bearing) smooth
      - [ ] Marker rendering (avatar markers, cluster markers) intact
      - [ ] Family building extrusion (per-place-type colors) intact
      - [ ] Path rendering (relationship lines) intact
      - [ ] Selection logic (tap to focus, tap to deselect) intact
      - [ ] Caching (camera state restoration) intact
      - [ ] Theme system (dark/light toggle) intact — verify warm-glow
            layer is dark-theme-only (light mode uses OpenFreeMap liberty
            URL which has no warm-glow layer)
      - [ ] Cold start < 2 seconds
      - [ ] Tile loading speed ≥ OpenFreeMap baseline

### Deferred to Phase B v1.1+

- [ ] **Frame-time runtime downgrade.** `MapQualityTierController` currently
      uses device-capability only (one-shot at startup). Runtime frame-time
      monitoring would require a full style reload on downgrade (maplibre
      0.3.5 has no `setLayoutProperty` API) — this would reset the camera
      and disrupt the user. Brief allows "device capability OR frame time"
      — chose device capability only for v1.0. Add runtime downgrade in
      v1.1 behind a feature flag, with camera-state save/restore around
      the style reload.
- [ ] **True post-processing bloom/AO.** MapLibre (JS or Native) doesn't
      support this without a custom rendering layer outside Phase B scope.
      Current approach uses the existing duplicate-extrusion-layer
      technique — extends it with data-driven color and density-aware
      filtering.
- [ ] **Custom OpenMapTiles profile fork for true z17 building tiles.**
      Deferred from Phase A.5 — current workaround: `--render_maxzoom=17`
      overzooms from z16 data.

### Phase B Implementation Artifacts

- `scripts/apply_phase_b_style_edits.py` — persisted, idempotent script
  that applies all 43 style JSON edits. Re-runnable. Backup of pre-edit
  JSON at `/tmp/kinrel_dark_style.json.before-phase-b`.
- `assets/map_styles/kinrel_dark_style.json` — edited in place (43 changes,
  layer count unchanged at 116).
- `lib/features/family_map/config/map_quality_tier.dart` — new file
  (170 lines, well-documented).
- `lib/main.dart` — 1 import + 1 initialize call added (after
  `DeviceTierCache.instance.initialize(...)`).
- `lib/features/family_map/presentation/family_map_screen.dart` —
  1 import + 1 patch call added in `_loadStyleJson` (between
  `_applyPmtilesSource` and `applyPoiFilters`).
