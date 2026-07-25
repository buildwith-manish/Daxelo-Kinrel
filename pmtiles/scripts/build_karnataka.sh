#!/usr/bin/env bash
# build_karnataka.sh — Phase A Stage 2: Karnataka validation build
#
# VALIDATION BUILD ONLY — per Phase A spec v2.0.
#
# Purpose: validate that pipeline scales from city (Mumbai) to state (Karnataka)
# before committing to country-scale (India, Stage 3).
#
# Per-layer zoom config (same as Stage 1):
#   - Base schema: z0-14
#   - Buildings: z0-16 (overzoom to z17)
#
# Requirements:
#   - Java 21+
#   - 4GB+ RAM
#   - Southern Zone India PBF at ../cache/sources/southern-zone-latest.osm.pbf (~530MB)
#
# Output:
#   ../output/karnataka.pmtiles (~100-500MB estimated)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR="$ROOT/bin/planetiler.jar"
PBF="$ROOT/cache/sources/southern-zone-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/karnataka"
CACHE_DIR="$ROOT/cache/planetiler"

# Karnataka bounding box: [min_lon, min_lat, max_lon, max_lat]
BBOX="73.0,11.5,78.5,18.5"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: Southern Zone PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh karnataka" >&2
  exit 1
fi

echo "=== Planetiler Karnataka Build (Stage 2 — VALIDATION) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "BBox: $BBOX (Karnataka state)"
echo "Per-layer zoom config: base z0-14, buildings z0-16+overzoom"
echo "Output: $OUTPUT_DIR/karnataka.pmtiles"
echo ""

java -Xmx4g -jar "$JAR" \
  --osm_path="$PBF" \
  --bbox="$BBOX" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --download \
  --output="$OUTPUT_DIR/karnataka.pmtiles" \
  --tmpdir="$BUILD_DIR" \
  --download_dir="$CACHE_DIR" \
  2>&1 | tee "$BUILD_DIR/build.log"

if [[ ! -f "$OUTPUT_DIR/karnataka.pmtiles" ]]; then
  echo "ERROR: PMTiles archive not produced" >&2
  exit 1
fi

echo ""
echo "=== Stage 2 build complete (validation) ==="
echo "File: $OUTPUT_DIR/karnataka.pmtiles ($(du -h "$OUTPUT_DIR/karnataka.pmtiles" | cut -f1))"
echo ""
echo "DO NOT ship this to production — Karnataka-only archive would lose the map"
echo "for any user outside Karnataka's bounding box."
