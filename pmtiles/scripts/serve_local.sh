#!/usr/bin/env bash
# serve_local.sh — local HTTP server with proper Range request support
#
# PMTiles clients issue HTTP Range requests (RFC 7233) to fetch only the
# specific byte ranges of the archive they need. A plain `python3 -m http.server`
# works for small files but is slow on large archives. This script uses a
# purpose-built server with:
#   - Full Range request support
#   - Proper CORS headers (for dev: web app on :443, tiles on :8080)
#   - Correct Content-Type for .pmtiles
#   - Aggressive caching headers (immutable, 1 year)
#
# For production: serve from Cloudflare R2 or any S3-compatible static host.
# See docs/deployment.md.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$ROOT/output"
PORT="${1:-8080}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "ERROR: output dir not found: $OUTPUT_DIR" >&2
  echo "Run scripts/build_mumbai.sh first" >&2
  exit 1
fi

# Python server with Range support + CORS — written inline to avoid extra deps
exec python3 "$SCRIPT_DIR/_range_server.py" "$OUTPUT_DIR" "$PORT"
