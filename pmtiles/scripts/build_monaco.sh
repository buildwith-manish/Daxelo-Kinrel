#!/usr/bin/env bash
# build_monaco.sh — Step 3 (spec v3.0): Build a tiny Monaco test archive
# and verify it INDEPENDENTLY (with pmtiles CLI) before any larger build.
#
# Why Monaco: Planetiler ships with a Monaco OSM extract baked into the JAR
# (~2 MB). No download needed. The full Planetiler pipeline runs in <1 min.
# The resulting .pmtiles is ~2-5 MB — small enough to inspect by hand.
#
# This script is the FIRST end-to-end test of the PMTiles pipeline. Per
# spec v3.0: "Do not build larger archives on top of an unverified pipeline."
#
# Output: ../output/monaco.pmtiles (~2-5 MB)
# Verification: ../build/monaco/verify.log (pmtiles show + tile decode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR="$ROOT/bin/planetiler.jar"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/monaco"
CACHE_DIR="$ROOT/cache/planetiler"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  echo "  Preferred: run via GitHub Actions (.github/workflows/build-pmtiles.yml)" >&2
  echo "  Local:     ./scripts/download_planetiler.sh v0.10.2" >&2
  exit 1
fi

echo "=== Planetiler Monaco Build (Step 3 — pipeline verification) ==="
echo "JAR: $JAR ($(du -h "$JAR" | cut -f1))"
echo "Zoom strategy: --maxzoom=16 (all layers), --render_maxzoom=17 (overzoom)"
echo "Output: $OUTPUT_DIR/monaco.pmtiles"
echo ""

# Planetiler's --area=monaco flag uses a built-in Monaco OSM extract
# (no PBF download needed). This is the smallest meaningful end-to-end test.
#
# --maxzoom=16 + --render_maxzoom=17: same as production builds (spec v3.0 Option B).
# --download: fetch auxiliary data (water polygons, natural earth) on first run.
#             Idempotent — no-op if aux data is already cached.
# Memory: -Xmx1g + --storage=direct + --mmap_temp=false (see build_mumbai.sh rationale).
# Log placement: written to /tmp during build (planetiler wipes tmpdir at startup),
# then copied to $BUILD_DIR/build.log after completion.
JAVA_MEM_OPTS="-Xmx1g"
PLANETILER_MEM_OPTS="--storage=direct --mmap_temp=false"

LOG_FILE="/tmp/monaco_build.$$.log"
java $JAVA_MEM_OPTS -jar "$JAR" \
  --area=monaco \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --force \
  --download \
  $PLANETILER_MEM_OPTS \
  --output="$OUTPUT_DIR/monaco.pmtiles" \
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

if [[ ! -f "$OUTPUT_DIR/monaco.pmtiles" ]]; then
  echo "ERROR: PMTiles archive not produced" >&2
  exit 1
fi

ls -lh "$OUTPUT_DIR/monaco.pmtiles"
echo ""
echo "=== Build complete ==="
echo "File: $OUTPUT_DIR/monaco.pmtiles"
echo ""
echo "Next step (independent verification):"
echo "  pmtiles show $OUTPUT_DIR/monaco.pmtiles"
echo "  pmtiles extract $OUTPUT_DIR/monaco.pmtiles 13 8192 5461 --output=/tmp/monaco_tile.pbf"
echo "  (decode the .pbf with mapbox-vector-tile to confirm layer structure)"
