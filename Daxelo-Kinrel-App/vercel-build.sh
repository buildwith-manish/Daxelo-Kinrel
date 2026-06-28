#!/usr/bin/env bash
# Vercel build script for the Flutter web app.
#
# Assumes vercel-install.sh has already put `flutter` on PATH and
# pre-cached pub dependencies. Builds the web app with --release.
#
# Output: build/web/ directory containing index.html, main.dart.js,
# flutter.js, assets/, etc. — the vercel.json outputDirectory points
# Vercel at this folder.
#
# Vercel build environment notes:
#   • Builds run as root; Flutter prints a warning but still works.
#   • `git config --global --add safe.directory '*'` was already run in
#     vercel-install.sh, so build_runner / dart tools that shell out to
#     git won't fail on "dubious ownership".
#   • We use `set -eo pipefail` (NOT -u) to match the install script.

set -eo pipefail

echo "=== Vercel Flutter build script starting ==="
echo "Working directory: $(pwd)"

# ── 1. Ensure Flutter is on PATH (it was installed in vercel-install.sh) ──
FLUTTER_HOME="$HOME/flutter"
export PATH="$FLUTTER_HOME/bin:$PATH"

# Re-apply the safe.directory fix in case git's global config was reset
# between the install and build steps.
git config --global --add safe.directory '*' 2>/dev/null || true

echo "=== Flutter version ==="
flutter --version 2>&1 | head -3 || true

# Sanity check: ensure flutter is actually on PATH
if ! command -v flutter >/dev/null 2>&1; then
  echo "FATAL: flutter not found on PATH"
  exit 1
fi

# ── 2. Run build_runner to generate Drift .g.dart files ─────────────────
# The Drift database code generator must run BEFORE the web build, otherwise
# lib/core/database/app_database.g.dart will be missing and dart2js will
# fail with "Type '_$AppDatabase' not found" and ~30 follow-on errors.
echo "=== Running build_runner (generates Drift .g.dart files) ==="
dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -10

# ── 3. Clean any stale build output ─────────────────────────────────────
# If a previous build left files in build/web/, a new build might not
# overwrite all of them (especially deleted assets). Running `flutter clean`
# ensures a fresh build every time. We skip `flutter clean` if build/web
# doesn't exist (first build) to save time.
if [ -d "build/web" ]; then
  echo "=== Cleaning stale build output ==="
  rm -rf build/web
fi

# ── 4. Build the web app ────────────────────────────────────────────────
# NOTE: --web-renderer flag was removed in Flutter 3.27+. The renderer
# (CanvasKit for desktop browsers, HTML for mobile) is now auto-selected.
# Forcing --web-renderer canvaskit will cause "Could not find an option
# named --web-renderer" and fail the build.
#
# --base-href "/" is required for Vercel — the app is served at the root.
# --release enables dart2js tree-shaking and minification.
#
# IMPORTANT: We do NOT pipe through `tail` here. The previous version
# used `| tail -20` which truncated the dart2js error output, making
# compile failures impossible to diagnose (Vercel only showed the last
# 20 lines, which were just the stack trace, not the actual error).
# We tee the full output to a log file AND to stdout so Vercel captures
# everything, and we surface the full log on failure.
echo "=== Running flutter build web --release ==="
set +e
flutter build web --release \
  --base-href "/" \
  > /tmp/flutter_build.log 2>&1
BUILD_EXIT_CODE=$?
set -e

if [ $BUILD_EXIT_CODE -ne 0 ]; then
  echo ""
  echo "=== ❌ flutter build web FAILED (exit $BUILD_EXIT_CODE) ==="
  echo "=== Full build log: ==="
  cat /tmp/flutter_build.log
  echo ""
  echo "=== End of build log ==="
  exit 1
fi

echo "=== flutter build web succeeded ==="
echo "=== Last 30 lines of build output: ==="
tail -30 /tmp/flutter_build.log

echo ""
echo "=== Build output listing ==="
ls -la build/web/ 2>&1 | head -20

echo ""
echo "=== Verifying index.html exists ==="
if [ ! -f build/web/index.html ]; then
  echo "FATAL: build/web/index.html not found!"
  exit 1
fi

echo ""
echo "=== Verifying main.dart.js exists ==="
if [ ! -f build/web/main.dart.js ]; then
  echo "FATAL: build/web/main.dart.js not found!"
  exit 1
fi

echo ""
echo "=== main.dart.js size ==="
ls -lh build/web/main.dart.js

echo "=== Build script complete ==="
