# Daxelo PMTiles — Phase A Migration

Self-hosted vector tile pipeline for the Daxelo Kinrel map. Replaces
OpenFreeMap-hosted tiles with Planetiler-generated PMTiles archives
served via HTTP range requests.

Per Phase A spec: this is an infrastructure migration only. No UI,
styling, or application architecture changes. Success = the map looks
and behaves identically to today, except tiles now come from a
self-hosted source and render past zoom 14.

## Quick Start

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
│       └── western-zone-latest.osm.pbf    (~208MB, Mumbai source)
├── build/
│   ├── monaco/                    ← Planetiler temp dir (test build)
│   ├── mumbai/                    ← Planetiler temp dir (Phase A target)
│   ├── karnataka/                 ← Phase 2 (future)
│   ├── india/                     ← Phase 3 (future)
│   └── planet/                    ← Phase 4 (future)
├── output/
│   ├── monaco.pmtiles             ← test archive (~2MB)
│   └── mumbai.pmtiles             ← Phase A archive (~20-50MB est)
├── config/
│   └── sources.json               ← PMTiles URL registry (dev vs prod)
├── scripts/
│   ├── download_planetiler.sh     ← fetch Planetiler JAR
│   ├── download_sources.sh        ← fetch OSM PBF from Geofabrik
│   ├── build_mumbai.sh            ← Planetiler + bbox clip → mumbai.pmtiles
│   ├── serve_local.sh             ← range-request HTTP server for dev
│   └── _range_server.py           ← Python HTTP server with Range + CORS
└── docs/
    ├── deployment.md              ← hosting + update strategy
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
Planetiler-generated .pmtiles (OpenMapTiles schema, maxzoom=16)
  ↓
OpenStreetMap (Geofabrik extracts)
```

## Phase A Success Criteria

Per spec: "Map matches current visual output layer-for-layer at z0–14"

- Map matches OpenFreeMap source visually at z0-14 over Mumbai
- Buildings, roads, and labels render with real detail through z16
  (2 zoom levels better than OpenFreeMap's z14 cap)
- No regressions in progressive loading, camera, animation, marker,
  or family-layer behavior
- Attribution present and correct: `© OpenStreetMap contributors,
  © OpenMapTiles, © Planetiler`

See `docs/migration-checklist.md` for the full verification checklist.

## Documentation

- `docs/deployment.md` — production hosting (Cloudflare R2), update strategy,
  offline support, known limitations
- `docs/migration-checklist.md` — step-by-step Phase A verification

## Phase B (Not Started)

Phase B (visual design enhancement) must NOT begin until Phase A is verified
at visual parity with the current OpenFreeMap-based map. See the original
spec for Phase B requirements.
