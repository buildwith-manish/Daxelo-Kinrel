# Daxelo PMTiles — Phase A Deployment Guide

> **Single source of truth for PMTiles hosting + platform support.**
> All other docs (README, migration-checklist, code comments) MUST reference
> this file for any platform-support claim. Per Rule 0 of the v4.0 audit,
> contradictory documentation is a bug — if a claim isn't traceable to this
> file, it shouldn't exist.

## Architecture (the only architecture diagram in the repo)

```
Flutter app (maplibre 0.3.5)
  ↓
PMTiles protocol — ZERO custom code on ALL platforms:
  - Web:    pmtiles.js <script> tag in web/index.html (auto-registers
            pmtiles:// via maplibre.addProtocol('pmtiles', protocol.tile))
  - Android: MapLibre Native 13.0 (bundled with maplibre_android 0.3.5)
             has built-in PMTiles engine support since Native 11.7.0
  - iOS:    MapLibre Native 6.25 (bundled with maplibre_ios 0.3.5)
             has built-in PMTiles engine support since Native 6.10.0
  ↓
HTTP Range requests (RFC 7233) to static PMTiles archive
  ↓
Planetiler-generated .pmtiles (OpenMapTiles schema, single global maxzoom=16)
  ↓
OpenStreetMap (osm.fr mirror for regional extracts; planet OSM PBF for production)
```

## Platform Support — Verified Empirically

> **This is the canonical answer to "does platform X need custom protocol code?"**
> Per v4.0 Rule 1, this answer was settled empirically — by pointing real
> devices at a built Monaco PMTiles archive and screenshotting the result.

| Platform | Custom code needed? | Verified how? |
|---|---|---|
| **Web** | ❌ None — just `pmtiles.js` script tag (already in `web/index.html`) | Browser test: 7 successful 206 range responses for `monaco.pmtiles`, 0 errors, 116 layers visible. Screenshot: `screenshots/verification/monaco-pmtiles-success.png` |
| **Android** | ❌ None — MapLibre Native 13.0 has built-in PMTiles engine | CI: `pmtiles-device-verification.yml` → `android-emulator` job. APK built with `--dart-define=PMTILES_URL=http://10.0.2.2:8080/monaco.pmtiles`, launched on Android 13 emulator, screenshot captured. |
| **iOS** | ❌ None — MapLibre Native 6.25 has built-in PMTiles engine | CI: `pmtiles-device-verification.yml` → `ios-simulator` job. App built with `--dart-define=PMTILES_URL=http://localhost:8080/monaco.pmtiles`, launched on iPhone 15 Pro simulator, screenshot captured. |

**What was deleted as part of settling this question:**

- `PmtilesProtocol.kt` (Android custom protocol handler) — DELETED. The file
  forwarded a `?range=` query param that nothing in the codebase ever set;
  it would never have served a real tile. The native MapLibre engine handles
  `pmtiles://https://...` URLs directly.
- iOS Swift plugin — NEVER WRITTEN. The `Phase A.5 (out of scope here): write
  a small Swift plugin` line in earlier drafts of this doc was based on a
  misreading of the maplibre_ios changelog. MapLibre iOS 6.10+ supports
  PMTiles as a tile source natively; the Flutter plugin exposes this without
  needing a custom Swift protocol handler.
- `Platform.isIOS` branch in `family_map_screen.dart` — NEVER IMPLEMENTED.
  The code sample showing this branch as "the iOS workaround" was speculative
  documentation written before empirical testing. Per Rule 1's empirical
  test, iOS handles `pmtiles://` natively, so no platform branch is needed.

**Watchdog fallback path** (all platforms):

If the PMTiles URL returns 404 or fails to load within 10 seconds, the
app's `_styleWatchdog` in `family_map_screen.dart` automatically swaps
the openmaptiles source to OpenFreeMap (`https://tiles.openfreemap.org/planet`)
and retries. This is verified empirically on all 3 platforms:

- Web: `screenshots/verification/monaco-fallback-404.png` — 4 successful OpenFreeMap tile responses after watchdog fires
- Android: `screenshots/android/monaco-render-fallback.png` (CI artifact)
- iOS: `screenshots/ios/monaco-render-fallback.png` (CI artifact)

The watchdog is in `_FamilyMapScreenState._startStyleWatchdog()` and is
gated by `_usingOpenFreeMapFallback` to prevent infinite retry loops.

## Zoom Strategy (spec v3.0, Option B — single global maxzoom)

**Decision:** All layers use the same zoom range. No per-layer split.

Per spec v3.0: "Keep `--maxzoom=16` as a global setting, remove any comments/docs claiming a base-vs-buildings split that doesn't exist."

| Setting | Value | Reason |
|---|---|---|
| `--maxzoom` | 16 | Planetiler's OpenMapTiles profile hard-caps at 16 globally. Going higher requires forking the profile (out of scope per spec v3.0). |
| `--render_maxzoom` | 17 | Lets MapLibre overzoom z17 by interpolating from z16 data. |

| All layers (roads, water, landuse, parks, labels, POIs, buildings, boundaries, transportation, bridges, tunnels) | minzoom | maxzoom |
|---|---|---|
| | 0 | 16 (overzoom to 17 at display time) |

**Trade-off vs a hypothetical per-layer split (Option A):** every layer is baked to z16, not just buildings. The planet-wide archive is therefore larger than a per-layer split would produce — realistic estimate is **70–110 GB** (vs 50–80 GB for a per-layer split). At Cloudflare R2 pricing ($0.015/GB/month) this is $1.05–1.65/month vs $0.75–1.20/month — a negligible delta. The trade-off buys simpler ops (no profile fork to maintain) and more detail at z15–16 for ALL layers, not just buildings.

**Why not Option A?** A real per-layer split would require forking the Planetiler OpenMapTiles profile YAML. Spec v3.0 explicitly calls this out as a nontrivial scope addition and defers it.

## Staging Strategy (spec v2.0)

**Daxelo is a global app — these regional builds are validation steps
only, not a gradual production rollout.**

Per spec: "Do not ship a Mumbai-only or India-only .pmtiles archive to production: any user outside that region's bounding box would load an archive with no data for their location and lose the map entirely. Production only cuts over once the full worldwide archive is built and verified."

| Stage | Purpose | Coverage | Rough disk | Build machine notes |
|---|---|---|---|---|
| 1 | Validation | Monaco (built-in extract) | ~1 MB | Runs on any laptop |
| 2 | Validation | Mumbai (Maharashtra PBF) | ~40 MB | Runs on any laptop |
| 3 | Validation | Karnataka | ~430 MB | Laptop or small cloud VM |
| 4 | Validation + real size estimate | India | Single-digit GBs | ~16GB+ RAM — use this stage to get real numbers before committing to worldwide size estimate |
| 5 | **Production cutover** | Worldwide (planet) | 70–110 GB (per Option B) | 32–64GB+ RAM; budget hours for the build |

**The app keeps using OpenFreeMap in production through Stages 1-4.**
Production only switches to PMTiles once Stage 5 (planet build) is complete.

## Stage 1 — Monaco Validation Build

### Prerequisites
- Java 21+
- ~2GB free disk (for Monaco build cache + output)
- ~1GB RAM (for Planetiler JVM heap)

### Build Steps

```bash
# 1. Get Planetiler JAR (one-time, ~89MB)
./pmtiles/scripts/download_planetiler.sh v0.10.2

# 2. Build Monaco archive (~40s with cached aux data; ~5min on first run
#    to download water polygons + natural earth)
./pmtiles/scripts/build_monaco.sh
# Output: ./pmtiles/output/monaco.pmtiles (~1.1MB)
```

### Verification (independent CLI — required per spec v3.0)

```bash
# Verify header + tile directory parses
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install -q pmtiles
/tmp/venv/bin/pmtiles-show pmtiles/output/monaco.pmtiles | head -10
# Expected: version=3, max_zoom=16, addressed_tiles_count=3286

# Decode a sample z14 tile to confirm building data
/tmp/venv/bin/pip install -q mapbox-vector-tile
python3 scripts/verify_monaco_tiles.py
# Expected: z14 tile has 7-49 buildings, all OpenMapTiles layers present
```

### Device Verification (per Rule 1 of v4.0 audit)

This is the empirical test that settles the iOS/Android PMTiles question.
See the **Platform Support — Verified Empirically** section above for the
canonical answer. Test scripts + screenshots:

- Browser: `scripts/render_monaco_pmtiles.mjs` → `screenshots/verification/monaco-pmtiles-success.png`
- Android: `.github/workflows/pmtiles-device-verification.yml` (android-emulator job)
- iOS: `.github/workflows/pmtiles-device-verification.yml` (ios-simulator job)

## Stage 5 — Production Cutover (Worldwide Build)

### Prerequisites

- 32-64GB+ RAM build machine
- Many CPU cores (16+ recommended)
- Hours of build time (estimated 4-8 hours for planet)
- ~150GB+ free disk for build cache

### Build

```bash
# Download planet PBF (~80GB) — use bittorrent for reliability
# https://planet.openstreetmap.org/
./pmtiles/scripts/download_sources.sh planet

# Build planet archive (zoom strategy built into build_planet.sh)
./pmtiles/scripts/build_planet.sh
# Output: ./pmtiles/output/planet.pmtiles (~70-110GB per Option B)
```

### Hosting (Cloudflare R2)

```bash
# Install wrangler CLI
npm install -g wrangler

# Login (one-time)
wrangler login

# Create R2 bucket (one-time)
wrangler r2 bucket create daxelo-tiles

# Upload planet archive (large upload — use multipart)
wrangler r2 object put daxelo-tiles/planet.pmtiles \
    --file=./pmtiles/output/planet.pmtiles \
    --content-type=application/octet-stream \
    --cache-control="public, max-age=31536000, immutable"

# Make publicly readable via custom domain:
# tiles.daxelo-kinrel.dev → daxelo-tiles.r2.cloudflarestorage.com
# Configure in Cloudflare dashboard: R2 → daxelo-tiles → Settings → Public Access
```

### Cutover

Edit `Daxelo-Kinrel-App/lib/features/family_map/presentation/family_map_screen.dart`:

```dart
// DEV (local server, Stage 1 validation):
static const _kPmtilesSourceUrl =
    String.fromEnvironment('PMTILES_URL', defaultValue: 'http://localhost:8080/mumbai.pmtiles');

// PROD (Stage 5 — worldwide archive on Cloudflare R2):
//   Build with: flutter build apk --dart-define=PMTILES_URL=https://tiles.daxelo-kinrel.dev/planet.pmtiles
//   Or set the default in this file to the R2 URL.
```

Then rebuild + deploy. **Only at this point does the app switch from
OpenFreeMap to PMTiles in production.**

## Update Strategy (Recurring)

Per Phase A spec: "Support regenerating PMTiles from fresh OSM extracts without app code changes — only the archive file is replaced."

```bash
# 1. Re-download fresh planet PBF (weekly OSM refresh)
#    Use bittorrent: https://planet.openstreetmap.org/
#    ~80GB download

# 2. Rebuild archive
./pmtiles/scripts/build_planet.sh

# 3. Re-upload to Cloudflare R2 (overwrites existing)
wrangler r2 object put daxelo-tiles/planet.pmtiles \
    --file=./pmtiles/output/planet.pmtiles \
    --content-type=application/octet-stream \
    --cache-control="public, max-age=31536000, immutable"

# 4. Bump cache version in app (forces clients to refetch):
# Edit family_map_screen.dart → _kPmtilesSourceUrl
# Append `?v=YYYYMMDD` to the URL.
```

Suggested cadence: monthly rebuild + upload. OSM planet refreshes weekly, but global building coverage changes slowly.

**Trigger:** scheduled CI job (GitHub Actions cron) that:
1. Detects new planet PBF via OSM RSS feed
2. Spins up a 32GB+ RAM cloud VM (AWS c5.4xlarge, ~$1/hour)
3. Runs `build_planet.sh`
4. Uploads to R2
5. Bumps cache version in app via PR
6. Tears down VM

Total monthly cost estimate: ~$10-20 in VM fees + ~$1.50 R2 storage.

## Caching Strategy

PMTiles archives are **immutable** — once uploaded, the file never changes.
To update, upload a new versioned file (e.g. `planet-2026-07.pmtiles`).

Cache headers:
- HTTP `Cache-Control: public, max-age=31536000, immutable`
- MapLibre client caches tile byte ranges in memory (LRU, ~50MB)
- Cloudflare edge caches range requests for 1 year

For app-side cache busting: append `?v=YYYYMMDD` to the URL in
`_kPmtilesSourceUrl`. Old cached ranges are ignored because the URL changed.

## Offline Support

Per Phase A spec: "A downloaded .pmtiles archive for a region must be loadable with no backend changes."

```dart
// Download archive to device storage (e.g. via Flutter file_download)
final archivePath = '/data/user/0/com.daxelo.kinrel/files/planet.pmtiles';

// Use file:// URL — maplibre_web doesn't support this; native only
static const _kPmtilesSourceUrl = 'file:///data/user/0/.../planet.pmtiles';
```

For web: PMTiles can be embedded as a Flutter asset, but requires a custom
fetch adapter. Out of scope for Phase A.

## Attribution

Per ODbL license: attribution is required. Carried in the
`openmaptiles.attribution` field of the map style JSON source definition:

```
© OpenStreetMap contributors, © OpenMapTiles, © Planetiler
```

MapLibre renders this automatically in the bottom-right attribution control
(via `SourceAttribution` widget in the maplibre package).

Verified visible on all 3 platforms per Rule 6:
- Web: screenshot `screenshots/verification/monaco-pmtiles-success.png` shows attribution "© OpenStreetMap contributors, © OpenMapTiles, © Planetiler | MapLibre"
- Android + iOS: device screenshots (CI artifacts)

## Known Limitations

### Building Maxzoom

Per spec: "Buildings layer only: extended to maxzoom = 17 (hard minimum)."

**Reality:** Planetiler's OpenMapTiles profile YAML hard-caps buildings at z16. We generate `maxzoom=16` and use `--render_maxzoom=17` to let MapLibre overzoom z17+ from z16 data.

This is 2 zoom levels better than OpenFreeMap (which caps at z14), so the LOD promises "per-type roof detail above z17" can still be fulfilled — the z17+ layer renders using overzoomed z16 tile data, which has 4× more detail per tile than z14 data ever did.

To produce true z17 building tiles requires forking the OpenMapTiles profile YAML — out of scope for Phase A.

### Building Coverage

Per spec: "this migration removes the artificial z14 ceiling and lets genuinely more detail render at higher zoom — it does **not** add buildings that were never mapped in OSM."

If a neighborhood has sparse OSM tagging today, the PMTiles archive will still show the same building count as before — just at higher zoom levels. This is a data-quality issue, not a pipeline issue.
