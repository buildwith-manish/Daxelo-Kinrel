#!/usr/bin/env bash
# build_karnataka.sh — Phase A Stage 2: Karnataka validation build
#
# VALIDATION BUILD ONLY — per Phase A spec v2.0.
#
# Purpose: validate that pipeline scales from city (Mumbai) to state (Karnataka)
# before committing to country-scale (India, Stage 3).
#
# Zoom strategy (spec v3.0, Option B — single global maxzoom, same as Stage 1):
#   --maxzoom=16          All layers baked to z16 (OpenMapTiles profile hard cap).
#   --render_maxzoom=17   MapLibre overzooms z17 from z16 data.
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
PBF="$ROOT/cache/sources/karnataka-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/karnataka"
CACHE_DIR="$ROOT/cache/planetiler"

# Karnataka bounding box: [west, south, east, north]
# Used as --bounds (NOT --bbox — Planetiler has no --bbox flag; that was a prior bug, silently ignored).
BOUNDS="73.0,11.5,78.5,18.5"

# Memory tuning for 4 GB cgroup-limited containers. See build_mumbai.sh for full rationale.
JAVA_MEM_OPTS="-Xmx2g"
PLANETILER_MEM_OPTS="--storage=direct --mmap_temp=false"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  echo "  Preferred: run via GitHub Actions (.github/workflows/build-pmtiles.yml)" >&2
  echo "  Local:     ./scripts/download_planetiler.sh v0.10.2" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: Karnataka PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh karnataka" >&2
  exit 1
fi

echo "=== Planetiler Karnataka Build (Stage 2 — VALIDATION) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "Bounds: $BOUNDS (Karnataka state, used as --bounds)"
echo "Memory: $JAVA_MEM_OPTS $PLANETILER_MEM_OPTS"
echo "Zoom strategy: --maxzoom=16 (all layers), --render_maxzoom=17 (overzoom)"
echo "Output: $OUTPUT_DIR/karnataka.pmtiles"
echo ""

# See build_mumbai.sh for full rationale on memory opts and log file placement.
LOG_FILE="/tmp/karnataka_build.$$.log"
java $JAVA_MEM_OPTS -jar "$JAR" \
  --osm_path="$PBF" \
  --bounds="$BOUNDS" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --force \
  $PLANETILER_MEM_OPTS \
  --output="$OUTPUT_DIR/karnataka.pmtiles" \
  --tmpdir="$BUILD_DIR" \
  --download_dir="$CACHE_DIR" \
  > "$LOG_FILE" 2>&1 &
BUILD_PID=$!

tail -f "$LOG_FILE" --pid="$BUILD_PID" 2>/dev/null || true
wait "$BUILD_PID"
BUILD_EXIT=$?

mkdir -p "$BUILD_DIR"
cp "$LOG_FILE" "$BUILD_DIR/build.log"

if [[ $BUILD_EXIT -ne 0 ]]; then
  echo "ERROR: Planetiler exited with code $BUILD_EXIT" >&2
  echo "Last 50 lines of build log:" >&2
  tail -50 "$LOG_FILE" >&2
  exit 1
fi

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
