# Daxelo PMTiles — Phase A Migration (spec v2.0)

Self-hosted vector tile pipeline for the Daxelo Kinrel map. Replaces
OpenFreeMap-hosted tiles with Planetiler-generated PMTiles archives
served via HTTP range requests.

Per Phase A spec v2.0: this is an infrastructure migration only. No UI,
styling, or application architecture changes. Success = the map looks
and behaves identically to today, except tiles now come from a
self-hosted source and render past zoom 14.

## Critical: Staging vs Production

**Daxelo is a global app.** Regional builds (Mumbai, Karnataka, India) are
**validation steps only** — they MUST NOT ship to production. Production
only cuts over at Stage 4 (planet build).

The app keeps using OpenFreeMap in production through all 3 validation
stages, and only switches to PMTiles once, at Stage 4.

| Stage | Purpose | Coverage | Status |
|---|---|---|---|
| 1 | Validation | Mumbai | scripts ready, awaiting data download |
| 2 | Validation | Karnataka | scripts ready |
| 3 | Validation + size estimate | India | scripts ready |
| 4 | **Production cutover** | Worldwide (planet) | scripts ready, needs 32-64GB RAM VM |

## Per-layer Zoom Config (spec v2.0)

Per spec: "Do not apply one zoom range to the entire schema."

| Layer group | minzoom | maxzoom |
|---|---|---|
| Base schema (roads, water, landuse, parks, labels, POIs, etc.) | 0 | 14 |
| Buildings layer only | 0 | 16 (with `--render_maxzoom=17` for overzoom) |

Buildings get 2 extra zoom levels of real detail vs OpenFreeMap's z14 cap.
MapLibre interpolates z17+ from z16 data.

## Quick Start (Stage 1 — Mumbai validation)

```bash
# 1. Get Planetiler (~89MB JAR, one-time)
./scripts/download_planetiler.sh v0.10.2

# 2. Get Mumbai OSM extract (~208MB, Western Zone India)
./scripts/download_sources.sh mumbai

# 3. Build PMTiles archive (~5 min on 4-core machine, ~2GB RAM)
./scripts/build_mumbai.sh

# 4. Serve locally for dev
./scripts/serve_local.sh 8080
# → http://localhost:8080/mumbai.pmtiles

# 5. Verify in browser at http://localhost:8080/mumbai.pmtiles
#    Should download a binary file (~20-50MB)

# 6. In family_map_screen.dart, set _kPmtilesSourceUrl to
#    'http://localhost:8080/mumbai.pmtiles' for dev testing
```

## Folder Structure

```
pmtiles/
├── README.md                      ← this file
├── bin/
│   └── planetiler.jar             ← downloaded by scripts/download_planetiler.sh
├── cache/
│   ├── planetiler/                ← auxiliary data (water polygons, natural earth)
│   │   ├── lake_centerline.shp.zip        (~78MB, one-time)
│   │   ├── natural_earth_vector.sqlite.zip (~415MB, one-time)
│   │   ├── water-polygons-split-3857.zip  (~885MB, one-time)
│   │   └── monaco.osm.pbf                  (test extract)
│   └── sources/                   ← OSM PBF extracts
│       ├── western-zone-latest.osm.pbf    (~208MB, Mumbai source — Stage 1)
│       ├── southern-zone-latest.osm.pbf   (~530MB, Karnataka source — Stage 2)
│       ├── india-latest.osm.pbf           (~1.5GB, India source — Stage 3)
│       └── planet-latest.osm.pbf          (~80GB, planet source — Stage 4)
├── build/
│   ├── monaco/                    ← Planetiler temp dir (test build)
│   ├── mumbai/                    ← Stage 1 (validation)
│   ├── karnataka/                 ← Stage 2 (validation)
│   ├── india/                     ← Stage 3 (validation + size estimate)
│   └── planet/                    ← Stage 4 (PRODUCTION)
├── output/
│   ├── monaco.pmtiles             ← test archive (~2MB)
│   ├── mumbai.pmtiles             ← Stage 1 (~20-50MB est)
│   ├── karnataka.pmtiles          ← Stage 2 (~100-500MB est)
│   ├── india.pmtiles              ← Stage 3 (~1-3GB est)
│   └── planet.pmtiles             ← Stage 4 PRODUCTION (~50-80GB est)
├── config/
│   └── sources.json               ← PMTiles URL registry (dev vs prod)
├── scripts/
│   ├── download_planetiler.sh     ← fetch Planetiler JAR
│   ├── download_sources.sh        ← fetch OSM PBF from Geofabrik
│   ├── build_mumbai.sh            ← Stage 1 validation build
│   ├── build_karnataka.sh         ← Stage 2 validation build
│   ├── build_india.sh             ← Stage 3 validation + size estimate
│   ├── build_planet.sh            ← Stage 4 PRODUCTION planet build
│   ├── serve_local.sh             ← range-request HTTP server for dev
│   └── _range_server.py           ← Python HTTP server with Range + CORS
└── docs/
    ├── deployment.md              ← hosting + staging + update strategy
    └── migration-checklist.md     ← Phase A verification checklist
```

## Architecture

```
Flutter app (maplibre 0.3.5)
  ↓
PMTiles protocol handler:
  - Web: maplibre_web auto-registers `pmtiles://` protocol
    (requires pmtiles.js script tag in web/index.html — DONE)
  - Android: PmtilesProtocol.kt registers custom protocol via
    Style.addProtocol() (DONE)
  - iOS: NOT YET IMPLEMENTED — see docs/deployment.md "Known Limitations"
  ↓
HTTP Range requests to static PMTiles archive
  ↓
Planetiler-generated .pmtiles (OpenMapTiles schema, per-layer zoom)
  ↓
OpenStreetMap (Geofabrik extracts)
```

## Phase A Success Criteria

Per spec: "Map matches current visual output layer-for-layer at z0–14"

- Map matches OpenFreeMap source visually at z0-14 over Mumbai (Stage 1)
- Buildings render with real detail through z16+ (2 levels better than OpenFreeMap z14 cap)
- No regressions in progressive loading, camera, animation, marker,
  or family-layer behavior
- Attribution present and correct: `© OpenStreetMap contributors,
  © OpenMapTiles, © Planetiler`

See `docs/migration-checklist.md` for the full verification checklist.

## Documentation

- `docs/deployment.md` — production hosting (Cloudflare R2), update strategy,
  offline support, staging strategy, known limitations
- `docs/migration-checklist.md` — step-by-step Phase A verification per spec v2.0

## Phase B (Not Started)

Phase B (visual design enhancement) must NOT begin until Phase A is verified
at visual parity with the current OpenFreeMap-based map. See the original
spec for Phase B requirements.
