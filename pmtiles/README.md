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

## Zoom Strategy (single global maxzoom — spec v3.0, Option B)

**Decision:** All layers use the same zoom range. No per-layer split.

| Setting | Value | Reason |
|---|---|---|
| `--maxzoom` | 16 | Planetiler's stock OpenMapTiles profile hard-caps at 16. Going higher requires forking the profile, which the spec v3.0 explicitly calls out as a nontrivial scope addition. |
| `--render_maxzoom` | 17 | Lets MapLibre overzoom z17 by interpolating from z16 data. |

| All layers (roads, water, landuse, parks, labels, POIs, buildings, …) | minzoom | maxzoom |
|---|---|---|
| | 0 | 16 (overzoom to 17 at display time) |

**Trade-offs vs a hypothetical per-layer split (Option A):**
- ✅ Simpler: no profile fork, no per-layer YAML overrides, single Planetiler command.
- ✅ More detail everywhere: roads, POIs, labels all get z15–16 detail (not just buildings).
- ❌ Larger archive: every layer is baked to z16, not just buildings. Realistic file-size estimates are 1.5–2× what a per-layer split would produce. The planet-wide archive will likely land in the 70–110 GB range rather than 50–80 GB. This is acceptable for Cloudflare R2 hosting ($1–2/month delta at $0.015/GB).
- ✅ Still 2 zoom levels better than OpenFreeMap's z14 cap for buildings.

**Why not Option A?** Planetiler's OpenMapTiles profile (`planetiler-openmaptiles` submodule) hard-caps `--maxzoom` at 16 globally — there's no flag to override per-layer. A real per-layer split would require forking the profile YAML and maintaining the fork. Spec v3.0 explicitly defers this to a later phase.

## Quick Start (Stage 1 — Mumbai validation)

### Option A — GitHub Actions (recommended, no local deps)

The Planetiler JAR (89 MB) and OSM PBF extracts are NOT in this repo.
They are downloaded on demand by CI, cached per version / per week,
and the resulting `.pmtiles` is uploaded as a 90-day workflow artifact.

```text
1. Push this branch to GitHub.
2. GitHub → Actions tab → "Build PMTiles" → Run workflow
   - Region: mumbai
   - Planetiler version: v0.10.2 (default)
   - Deploy to R2: unchecked (validation only)
3. Wait ~5 min for the run to finish.
4. Download the `mumbai-pmtiles` artifact from the run page.
5. Unzip locally and serve with ./scripts/serve_local.sh.
```

Workflow file: `.github/workflows/build-pmtiles.yml`

For production (Stage 4 planet build): the workflow runs weekly via cron
(Sunday 02:00 UTC) and optionally uploads to Cloudflare R2 if
`R2_*` secrets are configured.

### Option B — Local build (advanced, needs Java 21 + ~89 MB JAR download)

Only use this if you cannot use GitHub Actions (e.g. offline dev,
custom profile fork). The JAR is downloaded to `pmtiles/bin/` which
is in `.gitignore` — never commit it.

```bash
# 1. Get Planetiler (~89 MB JAR, one-time — NOT committed)
cd pmtiles && ./scripts/download_planetiler.sh v0.10.2

# 2. Get Maharashtra OSM extract (~165 MB, contains Mumbai metro)
#    Uses osm.fr mirror (Geofabrik rate-limits public downloads to ~40 KB/s).
./scripts/download_sources.sh mumbai

# 3. Build PMTiles archive (~2 min on 4-core machine, 4 GB RAM)
#    Memory opts: -Xmx2g --storage=direct --mmap_temp=false
#    (Required for cgroup-limited containers like GitHub Actions runners.)
./scripts/build_mumbai.sh

# 4. Serve locally for dev
./scripts/serve_local.sh 8080
# → http://localhost:8080/mumbai.pmtiles

# 5. Verify in browser at http://localhost:8080/mumbai.pmtiles
#    Should download a binary file (~40 MB)

# 6. In family_map_screen.dart, set _kPmtilesSourceUrl to
#    'http://localhost:8080/mumbai.pmtiles' for dev testing
```

## Verified Build Results (2026-07-25)

Pipeline verified end-to-end at three scales. Each archive independently
verified with `pmtiles-show` CLI (header + metadata) and `mapbox-vector-tile`
(actual tile decode).

| Region | PBF | Archive | Tiles | Build time | z16 buildings? | Notes |
|---|---|---|---|---|---|---|
| Monaco | 686 KB (built-in) | 1.13 MB | 3,286 | 7 min* | ✅ 18/tile | First end-to-end pipeline test |
| Mumbai | 165 MB (Maharashtra) | 40.7 MB | 12,068 | 2:07 | ✅ 32/tile | Mumbai-specific POIs, multilingual (hi) |
| Karnataka | 122 MB | 434 MB | 1,046,464 | 4:17 | ✅ 16-35/tile | 6 sample tiles verified across state |
| India | 1.8 GB | ~5-8 GB est. | ~10M est. | ~40 min est. | — | SKIPPED: needs 16GB+ RAM, 30GB+ disk |
| Planet | ~80 GB | ~70-110 GB est. | ~100M+ est. | 4-8 hr est. | — | Production: needs 32-64GB RAM VM |

*Monaco's 7 min included a one-time 928 MB water-polygons download.

### Key pipeline bugs fixed during verification

1. **`--bbox` was silently ignored.** Planetiler has no `--bbox` flag — the correct flag is `--bounds` (format: `west,south,east,north`). All build scripts updated.
2. **`-Xmx3g` OOM-killed under 4 GB cgroup limit.** JVM heap + non-heap + mmap of 810 MB natural_earth.sqlite + 928 MB water-polygons exceeded 4 GB cgroup limit on GitHub Actions / dev containers. Fixed with `-Xmx2g --storage=direct --mmap_temp=false`.
3. **Build log placed in tmpdir was wiped at startup.** Planetiler cleans `--tmpdir` at start, silently deleting any log file placed there before java starts. Fixed by writing log to `/tmp` during build, copying to `build/<region>/` after completion.
4. **Background `nohup` processes died at bash tool timeout.** Even with `nohup` + `setsid` + `disown`, child processes spawned by a shell that exits get killed. Fixed by using foreground `timeout 540` (within 10-min bash tool limit) and `tail -f --pid` for live progress.
5. **Geofabrik rate-limits public downloads to ~40 KB/s.** Switched `download_sources.sh` to osm.fr mirror (2 MB/s) which also provides state-level extracts (Maharashtra, Karnataka) — smaller and faster than Geofabrik's Western Zone extract.
6. **Corrupted Geofabrik PBF (MD5 mismatch).** The 164 MB Western Zone PBF downloaded from Geofabrik had MD5 `2c17e6c1...` instead of the expected `d15e88b9...`. This caused a `java.io.IOException: Channel not open for writing - cannot extend file to required size` error during Planetiler's OSM pass1 mmap. Switched to osm.fr mirror which serves valid PBFs.

### Verification artifacts

- `build/monaco/verify/summary.md` — Monaco header + tile decode details
- `build/mumbai/verify/summary.md` — Mumbai header + tile decode + bug-fix log
- `build/karnataka/verify/summary.md` — Karnataka header + 6 sample tile decodes + size extrapolation
- `build/<region>/build.log` — full Planetiler build log per region
- `build/<region>/verify/show.log` — `pmtiles-show` output per region

## Folder Structure

> **Note:** `bin/`, `cache/`, `build/`, and `output/` are NOT in git —
> they are generated by GitHub Actions (or local scripts) and listed in
> `.gitignore`. The committed repo is just docs + scripts + config.

```
pmtiles/
├── README.md                      ← this file
├── .gitignore                     ← excludes bin/, cache/, build/, output/, *.pmtiles
├── config/
│   └── sources.json               ← PMTiles URL registry (dev vs prod)
├── scripts/                       ← called by .github/workflows/build-pmtiles.yml
│   ├── download_planetiler.sh     ← fetch Planetiler JAR (cached by CI per version)
│   ├── download_sources.sh        ← fetch OSM PBF from osm.fr mirror (Maharashtra, Karnataka, India)
│   ├── build_monaco.sh            ← Step 3: tiny test build (uses built-in Monaco extract)
│   ├── build_mumbai.sh            ← Stage 1 validation build (Mumbai metro, Maharashtra PBF)
│   ├── build_karnataka.sh         ← Stage 2 validation build (Karnataka state)
│   ├── build_india.sh             ← Stage 3 validation + size estimate (16GB+ RAM required)
│   ├── build_planet.sh            ← Stage 4 PRODUCTION planet build (32-64GB RAM required)
│   ├── serve_local.sh             ← range-request HTTP server for dev
│   └── _range_server.py           ← Python HTTP server with Range + CORS
└── docs/
    ├── deployment.md              ← hosting + staging + update strategy
    └── migration-checklist.md     ← Phase A verification checklist

Generated locally / in CI (gitignored):
  bin/planetiler.jar               ← ~89 MB, downloaded by download_planetiler.sh
  bin/venv/                        ← Python venv with pmtiles CLI for verification
  cache/sources/*.osm.pbf          ← OSM extracts from osm.fr mirror
  cache/planetiler/                ← auxiliary data (water polygons 928MB, natural earth 415MB, lake centerlines 78MB)
  build/<region>/                  ← Planetiler temp dir + build.log + verify/ subdirs
  output/<region>.pmtiles          ← final archive (uploaded as CI artifact)
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
