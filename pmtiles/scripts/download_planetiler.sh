#!/usr/bin/env bash
# download_planetiler.sh — fetch the Planetiler JAR
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$ROOT/bin"
mkdir -p "$BIN_DIR"

VERSION="${1:-v0.10.2}"
URL="https://github.com/onthegomap/planetiler/releases/download/${VERSION}/planetiler.jar"
OUT="$BIN_DIR/planetiler.jar"

if [[ -f "$OUT" ]] && java -jar "$OUT" --version >/dev/null 2>&1; then
  echo "[skip] planetiler.jar already present ($VERSION)"
  exit 0
fi

echo "[fetch] Planetiler $VERSION"
curl -L --fail -o "$OUT" "$URL"
echo "       $(du -h "$OUT" | cut -f1) — done"
java -jar "$OUT" --version 2>&1 | head -1
