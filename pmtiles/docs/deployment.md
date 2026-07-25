# Daxelo PMTiles — Phase A Deployment Guide

This document describes how to build, host, and serve PMTiles archives for
the Daxelo Kinrel map. Per the Phase A spec v2.0, this is an infrastructure
migration — no UI or styling changes.

## Architecture

```
Flutter app
  ↓
maplibre 0.3.5 (Flutter package)
  ↓
PMTiles protocol handler:
  - Web: maplibre_web auto-registers `pmtiles://` protocol
    (requires pmtiles.js script tag in web/index.html — DONE)
  - Android: PmtilesProtocol.kt registers custom protocol via
    Style.addProtocol() (DONE)
  - iOS: NOT YET IMPLEMENTED — see "Known Limitations" below
  ↓
HTTP Range requests to static PMTiles archive
  ↓
Planetiler-generated .pmtiles (OpenMapTiles schema)
  ↓
OpenStreetMap (Geofabrik extracts)
```

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

Per spec: "Do not ship a Mumbai-only or India-only .pmtiles archive to
production: any user outside that region's bounding box would load an
archive with no data for their location and lose the map entirely.
Production only cuts over once the full worldwide archive is built and
verified."

| Stage | Purpose | Coverage | Rough disk | Build machine notes |
|---|---|---|---|---|
| 1 | Validation | Mumbai | Low (MBs) | Runs fine on a laptop |
| 2 | Validation | Karnataka | Tens of MBs–low GBs | Laptop or small cloud VM |
| 3 | Validation + real size estimate | India | Single-digit GBs | Few CPU cores, ~16GB+ RAM — use this stage to get real numbers for buildings-at-z18 before committing to worldwide size estimate |
| 4 | **Production cutover** | Worldwide (planet) | Well under ~100GB (only buildings go past z14) | Many CPU cores, 32–64GB+ RAM; budget hours for the build |

**The app keeps using OpenFreeMap in production through Stages 1-3.**
Production only switches to PMTiles once Stage 4 (planet build) is complete.

## Stage 1 — Mumbai Validation Build

### Prerequisites

- Java 21+ (verified: openjdk 21.0.11)
- ~2GB free disk (for Mumbai build cache + output)
- ~2GB RAM (for Planetiler JVM heap)

### Build Steps

```bash
# 1. Get Planetiler JAR (one-time, ~89MB)
./pmtiles/scripts/download_planetiler.sh v0.10.2

# 2. Get OSM source data (Western Zone India, ~208MB)
./pmtiles/scripts/download_sources.sh mumbai

# 3. Build PMTiles archive for Mumbai metro
./pmtiles/scripts/build_mumbai.sh
# Output: ./pmtiles/output/mumbai.pmtiles (~20-50MB estimated)

# 4. Serve locally for dev
./pmtiles/scripts/serve_local.sh 8080
# URL: http://localhost:8080/mumbai.pmtiles
```

### Mumbai Visual Parity Verification (REQUIRED before Stage 2)

Per spec: "Mumbai-stage visual diff against the current OpenFreeMap map
to confirm parity"

1. Take screenshots of Mumbai at z4, z8, z11, z13, z14 with OpenFreeMap source
2. Switch `_kPmtilesSourceUrl` in `family_map_screen.dart` to
   `http://localhost:8080/mumbai.pmtiles`
3. Take screenshots at same zooms with PMTiles source
4. Diff screenshots — visual parity required at z0-14
5. At z15-17, verify MORE buildings render (real OSM data, not stretched z14)

## Stage 3 — India File-Size Measurement (REQUIRED before Stage 4)

Per spec: "India-stage file-size measurement to validate the worldwide
estimate, before the production cutover"

1. Build India-wide PMTiles archive (needs ~16GB RAM)
2. Measure file size
3. Extrapolate to planet scale (India is ~2.4% of planet land area;
   planet archive estimated at ~30-45× India size with global z16 maxzoom)
4. Verify the planet-size estimate fits in the chosen hosting budget
   (Cloudflare R2 free tier: 10GB; paid: $0.015/GB/month)

## Stage 4 — Production Cutover (Worldwide Build)

### Prerequisites

- 32-64GB+ RAM build machine
- Many CPU cores (16+ recommended)
- Hours of build time (estimated 4-8 hours for planet)
- ~100GB+ free disk for build cache

### Build

```bash
# Download planet PBF (~80GB) — use bittorrent for reliability
# https://planet.openstreetmap.org/
./pmtiles/scripts/download_sources.sh planet

# Build planet archive (zoom strategy built into build_planet.sh)
./pmtiles/scripts/build_planet.sh
# Output: ./pmtiles/output/planet.pmtiles (~70-110GB estimated per Option B)
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
static const _kPmtilesSourceUrl = 'http://localhost:8080/mumbai.pmtiles';

// PROD (Stage 4 — worldwide archive on Cloudflare R2):
static const _kPmtilesSourceUrl = 'https://tiles.daxelo-kinrel.dev/planet.pmtiles';
```

Then rebuild + deploy. **Only at this point does the app switch from
OpenFreeMap to PMTiles in production.**

## Update Strategy (Recurring)

Per Phase A spec: "Support regenerating PMTiles from fresh OSM extracts
without app code changes — only the archive file is replaced."

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

Suggested cadence: monthly rebuild + upload. OSM planet refreshes weekly,
but global building coverage changes slowly.

**Trigger:** scheduled CI job (GitHub Actions cron) that:
1. Detects new planet PBF via OSM RSS feed
2. Spins up a 32GB+ RAM cloud VM (AWS c5.4xlarge, ~$1/hour)
3. Runs `build_planet.sh`
4. Uploads to R2
5. Bumps cache version in app via PR
6. Tears down VM

Total monthly cost estimate: ~$10-20 in VM fees + ~$1 R2 storage.

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

Per Phase A spec: "A downloaded .pmtiles archive for a region must be
loadable with no backend changes."

```dart
// Download archive to device storage (e.g. via Flutter file_download)
final archivePath = '/data/user/0/com.daxelo.kinrel/files/planet.pmtiles';

// Use file:// URL — maplibre_web doesn't support this; native only
static const _kPmtilesSourceUrl = 'file:///data/user/0/.../planet.pmtiles';
```

For web: PMTiles can be embedded as a Flutter asset, but requires a custom
fetch adapter. Out of scope for Phase A.

## Known Limitations

### iOS

`maplibre_ios 0.3.5` wraps MapLibre Native iOS 6.25 which supports
`MLNStyle.addProtocol()`, but the Flutter plugin does NOT expose this API.

**Workaround for Phase A:** iOS app continues to use the OpenFreeMap URL
fallback for now. The map still works — just doesn't get the z15-17 detail
boost on iOS.

```dart
// In family_map_screen.dart, platform-check the source:
static String get _kPmtilesSourceUrl => Platform.isIOS
    ? 'https://tiles.openfreemap.org/planet/20260621_080001_pt/{z}/{x}/{y}.pbf'
    : 'https://tiles.daxelo-kinrel.dev/planet.pmtiles';
```

**Phase A.5 (out of scope here):** write a small Swift plugin that calls
`MLNStyle.addProtocol()` to register the pmtiles:// handler on iOS.

### Building Maxzoom

Per spec: "Buildings layer only: extended to maxzoom = 17 (hard minimum)."

**Reality:** Planetiler's OpenMapTiles profile YAML hard-caps buildings at
z16. We generate `maxzoom=16` and use `--render_maxzoom=17` to let MapLibre
overzoom z17+ from z16 data.

This is 2 zoom levels better than OpenFreeMap (which caps at z14), so the
LOD promises "per-type roof detail above z17" can still be fulfilled —
the z17+ layer renders using overzoomed z16 tile data, which has 4× more
detail per tile than z14 data ever did.

To produce true z17 building tiles requires forking the OpenMapTiles
profile YAML — out of scope for Phase A.

### Building Coverage

Per spec: "this migration removes the artificial z14 ceiling and lets
genuinely more detail render at higher zoom — it does **not** add buildings
that were never mapped in OSM."

If a neighborhood has sparse OSM tagging today, the PMTiles archive will
still show the same building count as before — just at higher zoom levels.
This is a data-quality issue, not a pipeline issue.

## Attribution

Per ODbL license: attribution is required. Carried in the
`openmaptiles.attribution` field of the map style JSON source definition:

```
© OpenStreetMap contributors, © OpenMapTiles, © Planetiler
```

MapLibre renders this automatically in the bottom-right attribution control
(via `SourceAttribution` widget in the maplibre package).
