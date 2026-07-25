#!/usr/bin/env bash
# build_mumbai.sh — Phase A deliverable #1: Planetiler build pipeline for Mumbai
#
# Generates a PMTiles archive from OpenStreetMap data for the Mumbai metro area
# using the OpenMapTiles-compatible Planetiler profile.
#
# Requirements:
#   - Java 21+ (already verified)
#   - planetiler.jar at ../bin/planetiler.jar
#   - Western Zone India PBF at ../cache/sources/western-zone-latest.osm.pbf
#     (download via scripts/download_sources.sh)
#
# Output:
#   ../output/mumbai.pmtiles  (single archive, served via HTTP range requests)
#
# Per Phase A spec: maxzoom=17 hard minimum.

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
  echo "Run: scripts/download_planetiler.sh" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: Western Zone PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh" >&2
  exit 1
fi

echo "=== Planetiler Mumbai Build ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "BBox: $BBOX (Mumbai metro)"
echo "Maxzoom: 16 (Planetiler OpenMapTiles profile hard cap; spec asked for 17"
echo "  but Planetiler rejects maxzoom > 16. MapLibre overzoomes z17+ from z16"
echo "  data — 2 levels better than OpenFreeMap's z14 cap.)"
echo "Output: $OUTPUT_DIR/mumbai.pmtiles"
echo ""

# Planetiler OpenMapTiles profile — generates all standard OMT layers
# (building, transportation, water, landuse, place, poi, etc.)
# --maxzoom=16: Planetiler's OpenMapTiles profile hard cap (spec asked for 17)
# --bbox: clip to Mumbai metro
# --download: fetch auxiliary data (water polygons, natural earth, etc.) on first run
# --output: writes .pmtiles directly (planetiler auto-detects by extension)
java -Xmx3g -jar "$JAR" \
  --osm_path="$PBF" \
  --bbox="$BBOX" \
  --maxzoom=16 \
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
echo "=== Build complete ==="
echo "File: $OUTPUT_DIR/mumbai.pmtiles"
echo "Next: serve via scripts/serve_local.sh for dev, or upload to Cloudflare R2 for prod"
