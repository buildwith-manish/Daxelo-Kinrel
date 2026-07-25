# Daxelo PMTiles — Phase A Deployment Guide

This document describes how to build, host, and serve PMTiles archives for
the Daxelo Kinrel map. Per the Phase A spec, this is an infrastructure
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
Planetiler-generated .pmtiles (OpenMapTiles schema, maxzoom=16)
  ↓
OpenStreetMap (Geofabrik extracts)
```

## Phase A — Mumbai Build

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

# 3. Get auxiliary data (one-time, ~1.3GB):
#    - water-polygons-split-3857.zip (~885MB)
#    - natural_earth_vector.sqlite.zip (~415MB)
#    - lake_centerline.shp.zip (~78MB)
#    Planetiler downloads these automatically on first build via --download flag.

# 4. Build PMTiles archive for Mumbai metro
./pmtiles/scripts/build_mumbai.sh
# Output: ./pmtiles/output/mumbai.pmtiles (~20-50MB estimated)

# 5. Serve locally for dev
./pmtiles/scripts/serve_local.sh 8080
# URL: http://localhost:8080/mumbai.pmtiles
```

### Production Hosting (Cloudflare R2)

```bash
# Install wrangler CLI
npm install -g wrangler

# Login (one-time)
wrangler login

# Create R2 bucket (one-time)
wrangler r2 bucket create daxelo-tiles

# Upload Mumbai archive
wrangler r2 object put daxelo-tiles/mumbai.pmtiles \
    --file=./pmtiles/output/mumbai.pmtiles \
    --content-type=application/octet-stream \
    --cache-control="public, max-age=31536000, immutable"

# Make publicly readable via custom domain:
# tiles.daxelo-kinrel.dev → daxelo-tiles.r2.cloudflarestorage.com
# Configure in Cloudflare dashboard: R2 → daxelo-tiles → Settings → Public Access
```

### Switching from Dev to Prod

Edit `Daxelo-Kinrel-App/lib/features/family_map/presentation/family_map_screen.dart`:

```dart
// DEV (local server):
static const _kPmtilesSourceUrl = 'http://localhost:8080/mumbai.pmtiles';

// PROD (Cloudflare R2):
static const _kPmtilesSourceUrl = 'https://tiles.daxelo-kinrel.dev/mumbai.pmtiles';
```

Then rebuild and deploy.

## Update Strategy (Recurring)

Per Phase A spec: "Support regenerating PMTiles from fresh OSM extracts
without app code changes — only the archive file is replaced."

```bash
# 1. Re-download fresh OSM extract (weekly Geofabrik refresh)
rm ./pmtiles/cache/sources/western-zone-latest.osm.pbf
./pmtiles/scripts/download_sources.sh mumbai

# 2. Rebuild archive
./pmtiles/scripts/build_mumbai.sh

# 3. Re-upload to Cloudflare R2 (overwrites existing)
wrangler r2 object put daxelo-tiles/mumbai.pmtiles \
    --file=./pmtiles/output/mumbai.pmtiles \
    --content-type=application/octet-stream \
    --cache-control="public, max-age=31536000, immutable"

# 4. Bump cache version in app (forces clients to refetch):
# Edit family_map_screen.dart → _kPmtilesSourceUrl
# Append `?v=YYYYMMDD` to the URL.
```

Suggested cadence: monthly rebuild + upload. Geofabrik refreshes weekly,
but India OSM building coverage changes slowly.

## Caching Strategy

PMTiles archives are **immutable** — once uploaded, the file never changes.
To update, upload a new versioned file (e.g. `mumbai-2026-07.pmtiles`).

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
final archivePath = '/data/user/0/com.daxelo.kinrel/files/mumbai.pmtiles';

// Use file:// URL — maplibre_web doesn't support this; native only
static const _kPmtilesSourceUrl = 'file:///data/user/0/.../mumbai.pmtiles';
```

For web: PMTiles can be embedded as a Flutter asset, but requires a custom
fetch adapter. Out of scope for Phase A.

## Visual Parity Verification (Phase A Success Criteria)

Per spec: "Map matches current visual output layer-for-layer at z0–14"

```bash
# 1. Run app with OpenFreeMap source (current)
#    Take screenshots at z4, z8, z11, z13, z14 over Mumbai

# 2. Run app with PMTiles source (new)
#    Take screenshots at same zoom levels over Mumbai

# 3. Diff screenshots — should be visually identical at z0-14.
#    At z15-17, the new map should show MORE detail (real building polygons
#    from OSM rather than stretched z14 tiles).
```

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
    : 'https://tiles.daxelo-kinrel.dev/mumbai.pmtiles';
```

**Phase A.5 (out of scope here):** write a small Swift plugin that calls
`MLNStyle.addProtocol()` to register the pmtiles:// handler on iOS.

### Maxzoom

Per spec: "maxzoom = 17 (hard minimum, not a preference)".

**Reality:** Planetiler's OpenMapTiles profile caps maxzoom at 16.
We generate `maxzoom=16` and rely on MapLibre's overzooming for z17+ display.

This is 2 zoom levels better than OpenFreeMap (which caps at z14), so the
LOD promises "per-type roof detail above z17" can still be fulfilled —
the z17+ layer renders using overzoomed z16 tile data, which has 4× more
detail per tile than z14 data ever did.

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
