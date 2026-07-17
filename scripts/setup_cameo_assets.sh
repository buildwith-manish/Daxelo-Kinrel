#!/usr/bin/env bash
# scripts/setup_cameo_assets.sh
#
# Copies the canonical kinrel-cameo asset pack from repo root into the
# Flutter app's assets/ directory so it can be loaded at runtime via
# rootBundle / AssetImage.
#
# This is idempotent — re-running overwrites the copy with the latest
# source-of-truth assets.
#
# Run this after every `git pull` that touches kinrel-cameo/**, or
# before any `flutter run` / `flutter test` if you've regenerated assets.
#
# Layout:
#   Daxelo-Kinrel/                      <- repo root
#     kinrel-cameo/                     <- canonical asset pack (source)
#     scripts/setup_cameo_assets.sh     <- this script
#     Daxelo-Kinrel-App/                <- Flutter app
#       assets/kinrel-cameo/            <- populated copy (gitignored)

set -euo pipefail

# Resolve paths from this script's location.
# Script lives at: <repo_root>/scripts/setup_cameo_assets.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/Daxelo-Kinrel-App"

SRC="$REPO_ROOT/kinrel-cameo"
DST="$APP_DIR/assets/kinrel-cameo"

if [ ! -d "$SRC" ]; then
  echo "ERROR: source asset pack not found at $SRC" >&2
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  echo "ERROR: Flutter app dir not found at $APP_DIR" >&2
  exit 1
fi

echo "Copying kinrel-cameo assets:"
echo "  from: $SRC"
echo "  to:   $DST"
rm -rf "$DST"
mkdir -p "$APP_DIR/assets"
cp -r "$SRC" "$DST"

PNG_COUNT=$(find "$DST" -name "*.png" -size +1k | wc -l)
echo "Done. $PNG_COUNT PNGs now available to Flutter at assets/kinrel-cameo/"
