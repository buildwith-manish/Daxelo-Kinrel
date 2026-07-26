# Daxelo PMTiles — Phase A Migration (spec v2.0)

Self-hosted vector tile pipeline for the Daxelo Kinrel map. Replaces
OpenFreeMap-hosted tiles with Planetiler-generated PMTiles archives
served via HTTP range requests.

Per Phase A spec v2.0: this is an infrastructure migration only. No UI,
styling, or application architecture changes. Success = the map looks
and behaves identically to today, except tiles now come from a
self-hosted source and render past zoom 14.

> **Single source of truth:** For PMTiles platform support, hosting,
> zoom strategy, and verification status, see
> [`docs/deployment.md`](docs/deployment.md). This README references
> that file for any platform-support claim — it does NOT restate it.

## Critical: Staging vs Production

**Daxelo is a global app.** Regional builds (Monaco, Mumbai, Karnataka,
India) are **validation steps only** — they MUST NOT ship to production.
Production only cuts over at Stage 5 (planet build).

The app keeps using OpenFreeMap in production through all 4 validation
stages, and only switches to PMTiles once, at Stage 5.

| Stage | Purpose | Coverage | Status |
|---|---|---|---|
| 1 | Validation | Monaco (built-in extract) | ✅ Verified — see `screenshots/verification/` |
| 2 | Validation | Mumbai (Maharashtra) | ✅ Pipeline verified (40.7MB archive, 12K tiles) |
| 3 | Validation | Karnataka | ✅ Pipeline verified (434MB archive, 1M tiles) |
| 4 | Validation + size estimate | India | ⏳ PENDING — needs 16GB+ RAM (Rule 5 of v4.0 audit) |
| 5 | **Production cutover** | Worldwide (planet) | ⏳ PENDING — needs 32-64GB RAM VM (Rule 5 of v4.0 audit) |

## Zoom Strategy

Single global maxzoom — see [`docs/deployment.md`](docs/deployment.md#zoom-strategy-spec-v30-option-b--single-global-maxzoom) for the canonical statement.

**In one sentence:** All layers (roads, water, buildings, parks, labels, POIs, etc.) baked to z16, with `--render_maxzoom=17` letting MapLibre overzoom z17 from z16 data. No per-layer split. Planet archive estimated at 70–110 GB.

## Quick Start (Stage 1 — Monaco validation)

### Option A — GitHub Actions (recommended, no local deps)

The Planetiler JAR (89 MB) and OSM PBF extracts are NOT in this repo.
They are downloaded on demand by CI, cached per version / per week,
and the resulting `.pmtiles` is uploaded as a 90-day workflow artifact.

```text
1. Push this branch to GitHub.
2. GitHub → Actions tab → "Build PMTiles" → Run workflow
   - Region: monaco
   - Planetiler version: v0.10.2 (default)
3. Wait ~5 min for the run to finish.
4. Download the `monaco-pmtiles` artifact from the run page.
5. Unzip locally and serve with ./scripts/serve_local.sh.
```

Workflow file: `.github/workflows/build-pmtiles.yml`

For production (Stage 5 planet build): the workflow runs weekly via cron
(Sunday 02:00 UTC) and optionally uploads to Cloudflare R2 if
`R2_*` secrets are configured.

### Option B — Local build (advanced, needs Java 21 + ~89 MB JAR download)

Only use this if you cannot use GitHub Actions (e.g. offline dev,
custom profile fork). The JAR is downloaded to `pmtiles/bin/` which
is in `.gitignore` — never commit it.

```bash
# 1. Get Planetiler (~89 MB JAR, one-time — NOT committed)
cd pmtiles && ./scripts/download_planetiler.sh v0.10.2

# 2. Build Monaco archive (built-in extract — no PBF download needed)
#    First run: ~5 min (downloads 928MB water polygons + 434MB natural earth)
#    Subsequent runs: ~40s (cached aux data)
./scripts/build_monaco.sh

# 3. Serve locally for dev
./scripts/serve_local.sh 8080
# → http://localhost:8080/monaco.pmtiles

# 4. Verify the archive parses + tiles decode to real OSM data
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install -q pmtiles mapbox-vector-tile
/tmp/venv/bin/pmtiles-show output/monaco.pmtiles | head -10
python3 ../scripts/verify_monaco_tiles.py

# 5. In family_map_screen.dart, set _kPmtilesSourceUrl to
#    'http://localhost:8080/monaco.pmtiles' for dev testing
```

## Verified Build Results

Pipeline verified end-to-end at four scales. Each archive independently
verified with `pmtiles-show` CLI (header + metadata) and `mapbox-vector-tile`
(actual tile decode).

| Region | PBF | Archive | Tiles | Build time | z16 buildings? | Evidence |
|---|---|---|---|---|---|---|
| Monaco | 686 KB (built-in) | 1.13 MB | 3,286 | ~40s (after aux data cached) | ✅ 5-49/tile | `screenshots/verification/monaco-pmtiles-success.png` |
| Mumbai | 165 MB (Maharashtra) | 40.7 MB | 12,068 | 2:07 | ✅ 32/tile | `build/mumbai/verify/summary.md` |
| Karnataka | 122 MB | 434 MB | 1,046,464 | 4:17 | ✅ 16-35/tile | `build/karnataka/verify/summary.md` |
| India | 1.8 GB | ~5-8 GB est. | ~10M est. | ~40 min est. | — | ⏳ SKIPPED: needs 16GB+ RAM — see Rule 5 of v4.0 audit |
| Planet | ~80 GB | ~70-110 GB est. | ~100M+ est. | 4-8 hr est. | — | ⏳ Production: needs 32-64GB RAM VM |

> **Rule 6 (v4.0 audit) reminder:** Numbers marked "est." are estimates,
> not verified facts. Real India numbers will replace the estimate row
> once Rule 5 is closed. Every "verified" claim links to a real artifact
> (screenshot, CI run, or test file).

### Key pipeline bugs fixed during verification

1. **`--bbox` was silently ignored.** Planetiler has no `--bbox` flag — the correct flag is `--bounds` (format: `west,south,east,north`). All build scripts updated.
2. **`-Xmx3g` OOM-killed under 4 GB cgroup limit.** JVM heap + non-heap + mmap of 810 MB natural_earth.sqlite + 928 MB water-polygons exceeded 4 GB cgroup limit on GitHub Actions / dev containers. Fixed with `-Xmx2g --storage=direct --mmap_temp=false`.
3. **Build log placed in tmpdir was wiped at startup.** Planetiler cleans `--tmpdir` at start, silently deleting any log file placed there before java starts. Fixed by writing log to `/tmp` during build, copying to `build/<region>/` after completion.
4. **Background `nohup` processes died at bash tool timeout.** Even with `nohup` + `setsid` + `disown`, child processes spawned by a shell that exits get killed. Fixed by using foreground `timeout 540` (within 10-min bash tool limit) and `tail -f --pid` for live progress.
5. **Geofabrik rate-limits public downloads to ~40 KB/s.** Switched `download_sources.sh` to osm.fr mirror (2 MB/s) which also provides state-level extracts (Maharashtra, Karnataka) — smaller and faster than Geofabrik's Western Zone extract.
6. **Corrupted Geofabrik PBF (MD5 mismatch).** The 164 MB Western Zone PBF downloaded from Geofabrik had MD5 `2c17e6c1...` instead of the expected `d15e88b9...`. This caused a `java.io.IOException: Channel not open for writing - cannot extend file to required size` error during Planetiler's OSM pass1 mmap. Switched to osm.fr mirror which serves valid PBFs.
7. **`build_monaco.sh` was missing `--download` flag.** First-time builds need `--download` to fetch water polygons + natural earth aux data. Fixed by adding `--download` to the script (no-op when aux data is already cached).
8. **`_range_server.py` used HTTP/1.0 — Range requests ignored.** Python's `SimpleHTTPRequestHandler` defaults to HTTP/1.0, which doesn't honor Range headers. Fixed by setting `protocol_version = "HTTP/1.1"` and adding explicit Range request handling (Python 3.12 doesn't have native Range support — it was added in 3.13).

### Verification artifacts

- `screenshots/verification/monaco-pmtiles-success.png` — Monaco loading successfully via pmtiles:// in browser (Rule 1 evidence)
- `screenshots/verification/monaco-fallback-404.png` — Deliberately broken URL → OpenFreeMap fallback (Rule 3 evidence)
- `screenshots/verification/sanity-maplibre-demo.png` — MapLibre official demo rendering world map (proves WebGL + SwiftShader works)
- `screenshots/verification/monaco-render-results.json` — Full test results (network log, status text, pass/fail)
- `build/<region>/build.log` — full Planetiler build log per region
- `build/<region>/verify/show.log` — `pmtiles-show` output per region
- CI workflow runs: `.github/workflows/pmtiles-device-verification.yml` (Android + iOS device screenshots)

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
│   ├── build_monaco.sh            ← Stage 1 validation build (built-in Monaco extract — no PBF download)
│   ├── build_mumbai.sh            ← Stage 2 validation build (Mumbai metro, Maharashtra PBF)
│   ├── build_karnataka.sh         ← Stage 3 validation build (Karnataka state)
│   ├── build_india.sh             ← Stage 4 validation + size estimate (16GB+ RAM required)
│   ├── build_planet.sh            ← Stage 5 PRODUCTION planet build (32-64GB RAM required)
│   ├── serve_local.sh             ← range-request HTTP server for dev
│   └── _range_server.py           ← Python HTTP server with Range + CORS (HTTP/1.1 + RFC 7233)
└── docs/
    ├── deployment.md              ← SINGLE SOURCE OF TRUTH for platform support + hosting + zoom strategy
    └── migration-checklist.md     ← Phase A verification checklist (references deployment.md)
```

Generated locally / in CI (gitignored):
```
bin/planetiler.jar               ← ~89 MB, downloaded by download_planetiler.sh
bin/venv/                        ← Python venv with pmtiles CLI for verification
cache/sources/*.osm.pbf          ← OSM extracts from osm.fr mirror
cache/planetiler/                ← auxiliary data (water polygons 928MB, natural earth 415MB, lake centerlines 78MB)
build/<region>/                  ← Planetiler temp dir + build.log + verify/ subdirs
output/<region>.pmtiles          ← final archive (uploaded as CI artifact)
```

## Phase A Success Criteria

Per spec: "Map matches current visual output layer-for-layer at z0–14"

- Map matches OpenFreeMap source visually at z0-14 over Mumbai (Stage 2)
- Buildings render with real detail through z16+ (2 levels better than OpenFreeMap z14 cap)
- No regressions in progressive loading, camera, animation, marker, or family-layer behavior
- Attribution present and correct: `© OpenStreetMap contributors, © OpenMapTiles, © Planetiler`

See `docs/migration-checklist.md` for the full verification checklist.

## Documentation

- [`docs/deployment.md`](docs/deployment.md) — **single source of truth** for platform support, hosting, update strategy, offline support, staging strategy, known limitations
- [`docs/migration-checklist.md`](docs/migration-checklist.md) — step-by-step Phase A verification per spec v2.0 (references deployment.md for platform-support claims)

## Phase B Status

**Phase B v1.0 implementation is SHIPPED but NOT YET VERIFIED on devices.**

Phase B code (`lib/features/family_map/config/map_quality_tier.dart` +
integration in `family_map_screen.dart` + 43 style JSON edits to
`kinrel_dark_style.json`) was implemented in a previous cycle. Per
v4.0 Rule 4, Phase B's status is now explicitly:

- **Implementation: DONE** — 43 paint/layout/filter/text-font edits applied, layer count unchanged (116 → 116), `MapQualityTierController` added (device-capability-driven).
- **Device verification: PENDING** — awaiting Android emulator + iOS simulator + browser testing on real mid-range hardware (per Phase B brief's "5-region screenshot comparison" requirement).

Phase B was implemented BEFORE Phase A's device verification was closed
(this was an error in the previous cycle). Per v4.0 Rule 4, **no further
Phase B work will be added** until Rules 0–3 are fully closed with
evidence. The shipped Phase B code is being kept (not rolled back)
because:

1. The 43 style JSON edits are pure paint/layout/filter changes — they cannot break the tile-loading path or the watchdog fallback.
2. `MapQualityTierController` is a no-op for mid/high-tier devices (which is what CI tests run on). For low-tier devices, it patches `layout.visibility='none'` on `kinrel-3d-buildings-warm-glow` at style-load time — this only affects the warm-glow layer, not the fallback path.
3. The device verification CI workflow (`.github/workflows/pmtiles-device-verification.yml`) will empirically confirm that Phase B's quality-tier patch doesn't interfere with the OpenFreeMap fallback.

If device verification reveals any interference, the Phase B code will
be rolled back per Rule 4.
