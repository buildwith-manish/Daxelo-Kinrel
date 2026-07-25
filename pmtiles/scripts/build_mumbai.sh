#!/usr/bin/env bash
# build_mumbai.sh — Phase A deliverable #1: Planetiler build pipeline for Mumbai
#
# VALIDATION BUILD ONLY — per Phase A spec v2.0:
#   "Daxelo is a global app — these regional builds are validation steps
#    only, not a gradual production rollout. Do not ship a Mumbai-only or
#    India-only .pmtiles archive to production: any user outside that
#    region's bounding box would load an archive with no data for their
#    location and lose the map entirely. Production only cuts over once
#    the full worldwide archive is built and verified."
#
# This script is used to:
#   1. Verify the Planetiler pipeline works end-to-end
#   2. Generate a Mumbai-region archive for visual diff against OpenFreeMap
#   3. Validate that per-layer zoom config works as documented
#
# The app keeps using OpenFreeMap in production until Stage 4 (planet build).
#
# Per-layer zoom config (per spec v2.0):
#   - Base schema (roads, water, landuse, parks, labels, POIs, boundaries,
#     transportation, bridges, tunnels): minzoom=0, maxzoom=14
#   - Buildings layer ONLY: maxzoom=17 (Planetiler OpenMapTiles profile
#     hard-caps at 16; --render_maxzoom=17 lets MapLibre overzoom z17
#     from z16 data. 2 levels better than OpenFreeMap's z14 cap.)
#
# Requirements:
#   - Java 21+ (verified)
#   - planetiler.jar at ../bin/planetiler.jar
#   - Western Zone India PBF at ../cache/sources/western-zone-latest.osm.pbf
#     (download via scripts/download_sources.sh)
#
# Output:
#   ../output/mumbai.pmtiles  (single archive, served via HTTP range requests)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR="$ROOT/bin/planetiler.jar"
PBF="$ROOT/cache/sources/western-zone-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/mumbai"
CACHE_DIR="$ROOT/cache/planetiler"

# Mumbai metro bounding box: [min_lon, min_lat, max_lon, max_lat]
# Covers Greater Mumbai + Navi Mumbai + Thane + Mira-Bhayandar + Vasai-Virar
BBOX="72.65,18.85,73.15,19.35"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  echo "  Preferred: run via GitHub Actions (.github/workflows/build-pmtiles.yml)" >&2
  echo "  Local:     ./scripts/download_planetiler.sh v0.10.2" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: Western Zone PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh mumbai" >&2
  exit 1
fi

echo "=== Planetiler Mumbai Build (VALIDATION — not for production) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "BBox: $BBOX (Mumbai metro)"
echo "Per-layer zoom config (per spec v2.0):"
echo "  - Base schema (roads, water, landuse, labels, POIs, etc.): z0-14"
echo "  - Buildings layer: z0-16 (Planetiler OpenMapTiles profile hard cap;"
echo "    --render_maxzoom=17 allows MapLibre overzoom to z17 from z16 data)"
echo "Output: $OUTPUT_DIR/mumbai.pmtiles"
echo ""

# Planetiler OpenMapTiles profile generates all standard OMT layers
# (building, transportation, water, landuse, place, poi, etc.).
#
# Per spec v2.0 "Zoom Levels — per-layer split":
#   "Configure Planetiler with per-layer zoom overrides instead:
#    Base schema ... maxzoom = 14, Buildings layer only: extended to maxzoom = 17"
#
# Planetiler's openmaptiles profile YAML hard-caps buildings at z16.
# To get base schema at z14 + buildings at z17+, we use:
#   --maxzoom=16          (Planetiler's global cap — produces buildings to z16)
#   --render_maxzoom=17   (allows MapLibre to overzoom z17 from z16 data)
#
# This produces a single archive with all OMT layers, buildings through z16,
# and MapLibre interpolates z17+ display. 2 zoom levels better than OpenFreeMap
# (which caps at z14).
#
# NOTE: Planetiler rejects --maxzoom > 16 for the OpenMapTiles profile
#       ("Max zoom must be <= 16"). The cap is in the profile schema, not
#       Planetiler itself. Working around it requires a custom profile fork,
#       out of scope for Phase A.
#
# --bbox: clip to Mumbai metro
# --download: fetch auxiliary data (water polygons, natural earth) on first run
# --output: writes .pmtiles directly (planetiler auto-detects by extension)
java -Xmx3g -jar "$JAR" \
  --osm_path="$PBF" \
  --bbox="$BBOX" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --download \
  --output="$OUTPUT_DIR/mumbai.pmtiles" \
  --tmpdir="$BUILD_DIR" \
  --download_dir="$CACHE_DIR" \
  2>&1 | tee "$BUILD_DIR/build.log"

if [[ ! -f "$OUTPUT_DIR/mumbai.pmtiles" ]]; then
  echo "ERROR: PMTiles archive not produced" >&2
  exit 1
fi

ls -lh "$OUTPUT_DIR/mumbai.pmtiles"
echo ""
echo "=== Build complete (validation) ==="
echo "File: $OUTPUT_DIR/mumbai.pmtiles"
echo ""
echo "Next steps:"
echo "  1. Serve locally: ./scripts/serve_local.sh 8080"
echo "  2. In family_map_screen.dart, set _kPmtilesSourceUrl to"
echo "     'http://localhost:8080/mumbai.pmtiles' for dev testing"
echo "  3. Take screenshots at z4, z8, z11, z13, z14, z16, z17"
echo "  4. Diff against OpenFreeMap screenshots — parity required at z0-14"
echo "  5. At z15-17, verify MORE buildings render (real OSM data, not stretched z14)"
echo ""
echo "DO NOT ship this to production — Mumbai-only archive would lose the map"
echo "for any user outside Mumbai's bounding box. Production cutover happens"
echo "at Stage 4 (planet build) only."
