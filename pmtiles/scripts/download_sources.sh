#!/usr/bin/env bash
# download_sources.sh — fetch OSM PBF extracts from Geofabrik
#
# Per Phase A spec: "Support regenerating PMTiles from fresh OSM extracts
# without app code changes — only the archive file is replaced."
#
# Run this before each rebuild to get fresh OSM data.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT/cache/sources"
mkdir -p "$SRC_DIR"

GEOFABRIK_BASE="https://download.geofabrik.de/asia/india"

# Phase A — Mumbai (Western Zone, 208MB)
# Mumbai metro is in the Western Zone. Will be bbox-clipped at build time.
download() {
  local name="$1"
  local url="$2"
  local out="$SRC_DIR/$name"
  if [[ -f "$out" ]]; then
    echo "[skip] $name already exists ($(du -h "$out" | cut -f1))"
    echo "       To refresh: rm $out && re-run this script"
    return 0
  fi
  echo "[fetch] $name from $url"
  curl -L --fail --retry 3 --retry-delay 5 -o "$out" "$url"
  echo "       done: $(du -h "$out" | cut -f1)"
}

case "${1:-mumbai}" in
  mumbai|western)
    download "western-zone-latest.osm.pbf" "$GEOFABRIK_BASE/western-zone-latest.osm.pbf"
    ;;
  karnataka|southern)
    download "southern-zone-latest.osm.pbf" "$GEOFABRIK_BASE/southern-zone-latest.osm.pbf"
    ;;
  india)
    download "india-latest.osm.pbf" "$GEOFABRIK_BASE/india-latest.osm.pbf"
    ;;
  planet)
    echo "Planet extract: ~80GB. Use bittorrent from https://planet.openstreetmap.org/"
    echo "This script does not auto-download the planet file."
    exit 1
    ;;
  *)
    echo "Usage: $0 {mumbai|karnataka|india|planet}"
    exit 1
    ;;
esac

echo ""
echo "=== Sources ready ==="
ls -lh "$SRC_DIR"
