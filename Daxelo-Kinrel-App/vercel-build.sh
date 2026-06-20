#!/usr/bin/env bash
# Vercel build script for the Flutter web app.
#
# Assumes vercel-install.sh has already put `flutter` on PATH and
# pre-cached pub dependencies. Builds the web app with --release
# and --web-renderer canvaskit (better performance + CORS-safe).
#
# Output: build/web/ directory containing index.html, main.dart.js,
# flutter.js, assets/, etc. — the vercel.json outputDirectory points
# Vercel at this folder.

set -euo pipefail

echo "=== Vercel Flutter build script starting ==="
echo "Working directory: $(pwd)"

# ── 1. Ensure Flutter is on PATH (it was installed in vercel-install.sh) ──
# Flutter 3.44.2 stable (ships Dart 3.12, matches pubspec sdk: ^3.12.0).
FLUTTER_HOME="$HOME/flutter"
export PATH="$FLUTTER_HOME/bin:$PATH"

echo "=== Flutter version ==="
flutter --version 2>&1 | head -3

# ── 2. Build the web app ────────────────────────────────────────────────
#   --web-renderer canvaskit   : use CanvasKit (best fidelity, no CORS issues
#                                that html renderer has with fonts/images)
#   --release                  : production build (dart2js / dartdevc tree-shake)
#   --no-tree-shake-icons      : keep icon tree-shaking ON by default; remove
#                                flag if icon font errors appear at runtime
#
# Base href MUST be "/" for Vercel — the app is served at the root domain.
echo "=== Running flutter build web --release ==="
flutter build web --release \
  --web-renderer canvaskit \
  --base-href "/" \
  2>&1 | tail -30

echo ""
echo "=== Build output listing ==="
ls -la build/web/ 2>&1 | head -20

echo ""
echo "=== Verifying index.html exists ==="
if [ ! -f build/web/index.html ]; then
  echo "FATAL: build/web/index.html not found!"
  exit 1
fi

echo "=== Build script complete ==="
