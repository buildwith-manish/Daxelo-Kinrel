#!/usr/bin/env bash
# download_sources.sh — fetch OSM PBF extracts
#
# Uses the OpenStreetMap France mirror (download.openstreetmap.fr) instead of
# Geofabrik. Rationale:
#   - Geofabrik rate-limits public downloads (~40 KB/s after ~50 MB)
#   - osm.fr provides state-level extracts for India (smaller, faster)
#   - osm.fr includes replication headers in the PBF (planetiler uses these
#     for incremental updates)
#
# Per Phase A spec: "Support regenerating PMTiles from fresh OSM extracts
# without app code changes — only the archive file is replaced."

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT/cache/sources"
mkdir -p "$SRC_DIR"

OSM_FR_BASE="https://download.openstreetmap.fr/extracts/asia/india"

# Phase A — regional extracts (osm.fr state-level)
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
  # wget --continue survives transient network errors better than curl --retry
  wget --tries=20 --waitretry=10 --timeout=30 --continue -O "$out" "$url"
  echo "       done: $(du -h "$out" | cut -f1)"
}

case "${1:-mumbai}" in
  mumbai|maharashtra)
    # Mumbai metro is in Maharashtra state. Mumbai bbox clip happens at build time.
    download "maharashtra-latest.osm.pbf" "$OSM_FR_BASE/maharashtra-latest.osm.pbf"
    ;;
  karnataka)
    download "karnataka-latest.osm.pbf" "$OSM_FR_BASE/karnataka-latest.osm.pbf"
    ;;
  india)
    download "india-latest.osm.pbf" "$OSM_FR_BASE/india-latest.osm.pbf"
    ;;
  planet)
    echo "Planet extract: ~80GB. Use bittorrent from https://planet.openstreetmap.org/"
    echo "This script does not auto-download the planet file."
    exit 1
    ;;
  *)
    echo "Usage: $0 {mumbai|karnataka|india|planet}"
    echo "  mumbai     — Maharashtra state PBF (~165 MB, Mumbai is bbox-clipped at build)"
    echo "  karnataka  — Karnataka state PBF (~125 MB)"
    echo "  india      — India country PBF (~1.8 GB, needs 16GB+ RAM to build)"
    echo "  planet     — Planet PBF (~80 GB, bittorrent only)"
    exit 1
    ;;
esac

echo ""
echo "=== Sources ready ==="
ls -lh "$SRC_DIR"
