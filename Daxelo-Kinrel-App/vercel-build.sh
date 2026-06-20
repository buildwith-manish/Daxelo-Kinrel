#!/usr/bin/env bash
# Vercel build script for the Flutter web app.
#
# Assumes vercel-install.sh has already put `flutter` on PATH and
# pre-cached pub dependencies. Builds the web app with --release.
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

# ── 2. Run build_runner to generate Drift .g.dart files ─────────────────
# The Drift database code generator must run BEFORE the web build, otherwise
# lib/core/database/app_database.g.dart will be missing and dart2js will
# fail with "Type '_$AppDatabase' not found" and ~30 follow-on errors.
echo "=== Running build_runner (generates Drift .g.dart files) ==="
dart run build_runner build 2>&1 | tail -5

# ── 3. Build the web app ────────────────────────────────────────────────
# NOTE: --web-renderer flag was removed in Flutter 3.27+. The renderer
# (CanvasKit for desktop browsers, HTML for mobile) is now auto-selected.
# Forcing --web-renderer canvaskit will cause "Could not find an option
# named --web-renderer" and fail the build.
#
# --base-href "/" is required for Vercel — the app is served at the root.
# --release enables dart2js tree-shaking and minification.
echo "=== Running flutter build web --release ==="
flutter build web --release \
  --base-href "/" \
  2>&1 | tail -20

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
