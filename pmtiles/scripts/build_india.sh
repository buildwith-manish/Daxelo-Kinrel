#!/usr/bin/env bash
# build_india.sh — Phase A Stage 3: India-wide validation build
#
# VALIDATION BUILD ONLY — per Phase A spec v2.0:
#   "Stages 1–3 exist to catch schema/style/performance problems cheaply
#    before committing to a planet-scale build. The app itself keeps using
#    OpenFreeMap in production through all three validation stages, and
#    only switches to PMTiles once, at Stage 4."
#
# Purpose of this build:
#   1. Validate that the pipeline scales from city to country
#   2. Measure real file size at India scale (~2.4% of planet land area)
#   3. Extrapolate to planet-size estimate for hosting budget verification
#      BEFORE committing to Stage 4 (planet build)
#
# Zoom strategy (spec v3.0, Option B — single global maxzoom, same as Stage 1):
#   --maxzoom=16          All layers baked to z16 (OpenMapTiles profile hard cap).
#   --render_maxzoom=17   MapLibre overzooms z17 from z16 data.
#
# Requirements:
#   - Java 21+
#   - 16GB+ RAM (India is much bigger than Mumbai) — uses -Xmx12g
#   - ~30GB free disk for build cache + temp + output
#   - India PBF at ../cache/sources/india-latest.osm.pbf (~1.8GB from osm.fr)
#
# Output:
#   ../output/india.pmtiles (~5-8GB estimated)
#
# NOTE: This build CANNOT run on a 4 GB cgroup-limited container (GitHub Actions
# ubuntu-latest, dev containers, this headless Linux env). It needs either:
#   - A 16GB+ GitHub Actions runner (ubuntu-latest-16-cores, ~$0.16/min)
#   - A dedicated VM (DigitalOcean/GCP/AWS 16GB+ instance)
#   - Run via .github/workflows/build-pmtiles.yml with region=india

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR="$ROOT/bin/planetiler.jar"
PBF="$ROOT/cache/sources/india-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/india"
CACHE_DIR="$ROOT/cache/planetiler"

# Memory tuning — same rationale as build_mumbai.sh.
# For India scale, use 12GB heap (requires 16GB+ RAM machine).
# On 4 GB containers, this WILL fail — use GitHub Actions or a dedicated VM.
JAVA_MEM_OPTS="-Xmx12g"
PLANETILER_MEM_OPTS="--storage=direct --mmap_temp=false"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  echo "  Preferred: run via GitHub Actions (.github/workflows/build-pmtiles.yml)" >&2
  echo "  Local:     ./scripts/download_planetiler.sh v0.10.2" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: India PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh india" >&2
  exit 1
fi

echo "=== Planetiler India Build (Stage 3 — VALIDATION, not for production) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "Memory: $JAVA_MEM_OPTS $PLANETILER_MEM_OPTS"
echo "Zoom strategy: --maxzoom=16 (all layers), --render_maxzoom=17 (overzoom)"
echo "Output: $OUTPUT_DIR/india.pmtiles"
echo "RAM: 16GB+ required for India scale (this build will fail on 4 GB containers)"
echo ""

# See build_mumbai.sh for full rationale on memory opts and log file placement.
LOG_FILE="/tmp/india_build.$$.log"
java $JAVA_MEM_OPTS -jar "$JAR" \
  --osm_path="$PBF" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --force \
  $PLANETILER_MEM_OPTS \
  --output="$OUTPUT_DIR/india.pmtiles" \
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

if [[ ! -f "$OUTPUT_DIR/india.pmtiles" ]]; then
  echo "ERROR: PMTiles archive not produced" >&2
  exit 1
fi

INDIA_SIZE=$(stat -c%s "$OUTPUT_DIR/india.pmtiles")
INDIA_SIZE_GB=$((INDIA_SIZE / 1024 / 1024 / 1024))

echo ""
echo "=== Stage 3 build complete ==="
echo "File: $OUTPUT_DIR/india.pmtiles ($(du -h "$OUTPUT_DIR/india.pmtiles" | cut -f1))"
echo ""
echo "=== Worldwide Size Estimate ==="
echo "India ≈ 2.4% of planet land area"
echo "Planet estimate: ~$((INDIA_SIZE_GB * 40)) GB (40× India size)"
echo ""
echo "Cloudflare R2 cost estimate (at $0.015/GB/month):"
echo "  \$$(echo "scale=2; $INDIA_SIZE_GB * 40 * 0.015" | bc)/month"
echo ""
echo "Next: verify this fits hosting budget before Stage 4 (planet build)"
