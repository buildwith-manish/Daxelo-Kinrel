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
#   3. Validate that the global zoom strategy works as documented
#
# The app keeps using OpenFreeMap in production until Stage 4 (planet build).
#
# Zoom strategy (per spec v3.0, Option B — single global maxzoom):
#   --maxzoom=16          All layers baked to z16 (Planetiler's OpenMapTiles
#                         profile hard-caps at 16; no per-layer override
#                         is supported without forking the profile).
#   --render_maxzoom=17   Lets MapLibre overzoom z17 by interpolating z16 data.
#
# Trade-off: every layer (roads, water, landuse, labels, POIs, buildings, …)
# goes to z16, not just buildings. Larger archive than a per-layer split
# would produce, but 2 zoom levels better than OpenFreeMap's z14 cap.
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
PBF="$ROOT/cache/sources/maharashtra-latest.osm.pbf"
OUTPUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build/mumbai"
CACHE_DIR="$ROOT/cache/planetiler"

# Mumbai metro bounding box: [west, south, east, north]
# Covers Greater Mumbai + Navi Mumbai + Thane + Mira-Bhayandar + Vasai-Virar
# Used as --bounds (NOT --bbox — Planetiler has no --bbox flag; --bbox is silently ignored).
# --bounds both sets the archive metadata bounds AND clips the output to that envelope.
BOUNDS="72.65,18.85,73.15,19.35"

# Memory tuning for 4 GB cgroup-limited containers (GitHub Actions ubuntu-latest,
# dev containers, CI runners with 4-7 GB RAM). The default --storage=mmap mode
# causes silent OOM kills during OSM pass1 on PBFs > ~50 MB because mmap'd
# virtual address space is accounted against cgroup memory.
#
# --storage=direct   uses direct ByteBuffer instead of mmap for temp storage
# --mmap_temp=false  disables mmap for feature.db temp files
# -Xmx2g             JVM heap; 2g is safe under 4 GB cgroup, 1g is too tight for
#                    India-state-sized PBFs (peak heap during OSM pass2 ~700 MB).
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
  echo "ERROR: Maharashtra PBF not found at $PBF" >&2
  echo "Run: scripts/download_sources.sh mumbai" >&2
  exit 1
fi

echo "=== Planetiler Mumbai Build (VALIDATION — not for production) ==="
echo "PBF: $PBF ($(du -h "$PBF" | cut -f1))"
echo "Bounds: $BOUNDS (Mumbai metro, used as --bounds)"
echo "Memory: $JAVA_MEM_OPTS $PLANETILER_MEM_OPTS"
echo "Zoom strategy (spec v3.0, Option B — single global maxzoom):"
echo "  --maxzoom=16          all layers baked to z16"
echo "  --render_maxzoom=17   MapLibre overzooms z17 from z16 data"
echo "Output: $OUTPUT_DIR/mumbai.pmtiles"
echo ""

# Planetiler OpenMapTiles profile generates all standard OMT layers
# (building, transportation, water, landuse, place, poi, etc.) and applies
# ONE global maxzoom to all of them. Spec v3.0 Option B accepts this.
#
# --bounds:   clips output to Mumbai metro envelope (NOT --bbox; planetiler
#             has no --bbox flag — that was a prior bug, silently ignored).
# --download: fetch auxiliary data (water polygons, natural earth) on first run
# --output:   writes .pmtiles directly (planetiler auto-detects by extension)
# Memory:     $PLANETILER_MEM_OPTS avoids cgroup OOM kills on memory-limited
#             runners (GitHub Actions, dev containers, 4 GB CI boxes).
#
# IMPORTANT: build.log is written to /tmp, NOT $BUILD_DIR — planetiler wipes
# $BUILD_DIR (the tmpdir) at startup, which silently deletes any log file
# placed there before java starts.
LOG_FILE="/tmp/mumbai_build.$$.log"
java $JAVA_MEM_OPTS -jar "$JAR" \
  --osm_path="$PBF" \
  --bounds="$BOUNDS" \
  --maxzoom=16 \
  --render_maxzoom=17 \
  --force \
  --download \
  $PLANETILER_MEM_OPTS \
  --output="$OUTPUT_DIR/mumbai.pmtiles" \
  --tmpdir="$BUILD_DIR" \
  --download_dir="$CACHE_DIR" \
  > "$LOG_FILE" 2>&1 &
BUILD_PID=$!

# Stream the log to stdout while the build runs (so CI sees live progress).
tail -f "$LOG_FILE" --pid="$BUILD_PID" 2>/dev/null || true
wait "$BUILD_PID"
BUILD_EXIT=$?

# Copy log into $BUILD_DIR now that the build is done (tmpdir is no longer wiped).
mkdir -p "$BUILD_DIR"
cp "$LOG_FILE" "$BUILD_DIR/build.log"

if [[ $BUILD_EXIT -ne 0 ]]; then
  echo "ERROR: Planetiler exited with code $BUILD_EXIT" >&2
  echo "Last 50 lines of build log:" >&2
  tail -50 "$LOG_FILE" >&2
  exit 1
fi

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
