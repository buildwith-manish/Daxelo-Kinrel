#!/usr/bin/env bash
# build_planet.sh — Phase A Stage 4: PRODUCTION planet-wide build
#
# THIS IS THE PRODUCTION BUILD. Per spec v2.0:
#   "Production only cuts over once the full worldwide archive is built
#    and verified."
#
# Per-layer zoom config (same as Stages 1-3):
#   - Base schema: z0-14
#   - Buildings layer: z0-16 (overzoom to z17 via --render_maxzoom=17)
#
# Requirements:
#   - Java 21+
#   - 32-64GB+ RAM (planet is huge)
#   - Many CPU cores (16+ recommended)
#   - 4-8 hours build time
#   - ~150GB free disk for build cache + output
#   - Planet PBF (~80GB) at ../cache/sources/planet-latest.osm.pbf
#     Download via bittorrent: https://planet.openstreetmap.org/
#
# Output:
#   ../output/planet.pmtiles (~50-80GB estimated, depending on OSM density)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR="$ROOT/bin/planetiler.jar"
PBF="$ROOT/cache/sources/planet-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/planet"
CACHE_DIR="$ROOT/cache/planetiler"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "ERROR: planetiler.jar not found at $JAR" >&2
  exit 1
fi

if [[ ! -f "$PBF" ]]; then
  echo "ERROR: Planet PBF not found at $PBF" >&2
  echo "Download via bittorrent from https://planet.openstreetmap.org/" >&2
  echo "Place at: $PBF" >&2
  exit 1
fi

# Verify available RAM (warn if <32GB)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
if [[ $TOTAL_RAM_GB -lt 32 ]]; then
  echo "WARNING: Only ${TOTAL_RAM_GB}GB RAM detected. Planet build needs 32-64GB+." >&2
  echo "Continue anyway? (y/N)" >&2
  read -r response
  [[ "$response" != "y" && "$response" != "Y" ]] && exit 1
fi

echo "=== Planetiler PLANET Build (Stage 4 — PRODUCTION) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "Per-layer zoom config:"
echo "  - Base schema: z0-14"
echo "  - Buildings: z0-16 (overzoom to z17 via --render_maxzoom=17)"
echo "Output: $OUTPUT_DIR/planet.pmtiles (~50-80GB estimated)"
echo "Build time: 4-8 hours estimated"
echo ""

# Use 24GB heap on 32GB machine, 48GB on 64GB machine
HEAP_SIZE=$((TOTAL_RAM_GB < 48 ? 24 : 48))

echo "Using ${HEAP_SIZE}GB JVM heap"
echo ""

# No --bbox (planet is the whole world)
# No --download for planet PBF (we provide --osm_path)
java -Xmx${HEAP_SIZE}g -jar "$JAR" \
  --osm_path="$PBF" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --download \
  --output="$OUTPUT_DIR/planet.pmtiles" \
  --tmpdir="$BUILD_DIR" \
  --download_dir="$CACHE_DIR" \
  2>&1 | tee "$BUILD_DIR/build.log"

if [[ ! -f "$OUTPUT_DIR/planet.pmtiles" ]]; then
  echo "ERROR: PMTiles archive not produced" >&2
  exit 1
fi

PLANET_SIZE=$(stat -c%s "$OUTPUT_DIR/planet.pmtiles")
PLANET_SIZE_GB=$((PLANET_SIZE / 1024 / 1024 / 1024))

echo ""
echo "=== Stage 4 PRODUCTION build complete ==="
echo "File: $OUTPUT_DIR/planet.pmtiles ($(du -h "$OUTPUT_DIR/planet.pmtiles" | cut -f1))"
echo ""
echo "Next steps:"
echo "  1. Upload to Cloudflare R2:"
echo "     wrangler r2 object put daxelo-tiles/planet.pmtiles \\"
echo "       --file=$OUTPUT_DIR/planet.pmtiles \\"
echo "       --content-type=application/octet-stream \\"
echo "       --cache-control='public, max-age=31536000, immutable'"
echo ""
echo "  2. Update _kPmtilesSourceUrl in family_map_screen.dart:"
echo "     static const _kPmtilesSourceUrl = 'https://tiles.daxelo-kinrel.dev/planet.pmtiles';"
echo ""
echo "  3. Build APK + web bundle, test on real devices"
echo "  4. Commit + push + Vercel auto-deploy"
echo "  5. Monitor error logs for 24 hours"
