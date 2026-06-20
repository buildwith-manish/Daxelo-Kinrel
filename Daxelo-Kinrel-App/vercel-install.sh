#!/usr/bin/env bash
# Vercel install script for the Flutter web app.
#
# Vercel's build environment doesn't ship Flutter, so we install it here.
# Pinned to a specific stable release for reproducible builds.
#
# The pubspec.yaml requires:
#   environment:
#     sdk: ^3.12.0
# Flutter 3.44.2 (stable, June 2026) ships Dart 3.12.x — this is the
# lowest stable Flutter version that satisfies the constraint.
#
# Output: a usable `flutter` on PATH + cached pub packages.

set -euo pipefail

echo "=== Vercel Flutter install script starting ==="
echo "Working directory: $(pwd)"
echo "Node version: $(node --version 2>&1 || echo 'n/a')"
echo "Disk space:"
df -h . 2>&1 | head -2

# ── 1. Install Flutter SDK ──────────────────────────────────────────────
# Pin to a specific stable version for reproducible builds.
# Update this when bumping the SDK constraint in pubspec.yaml.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"
FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin"

# Check if Flutter is already cached at the right version.
# Vercel preserves $HOME between builds when cache is enabled, so this
# skips the ~2GB download on subsequent builds.
NEED_INSTALL=0
if [ ! -f "$FLUTTER_BIN/flutter" ]; then
  NEED_INSTALL=1
elif ! "$FLUTTER_BIN/flutter" --version 2>&1 | grep -q "Flutter $FLUTTER_VERSION"; then
  NEED_INSTALL=1
fi

if [ $NEED_INSTALL -eq 1 ]; then
  echo "=== Downloading Flutter $FLUTTER_VERSION (stable) ==="
  # Clone the Flutter repo with --depth 1 + --branch to minimize download
  # size (~500MB instead of ~2GB full history). This is the smallest
  # possible Flutter checkout that works for building web apps.
  rm -rf "$FLUTTER_HOME"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME" 2>&1 | tail -5
else
  echo "=== Flutter $FLUTTER_VERSION already cached, skipping clone ==="
fi

export PATH="$FLUTTER_BIN:$PATH"

echo "=== Flutter version ==="
flutter --version 2>&1 | head -5

# ── 2. Disable analytics + telemetry ────────────────────────────────────
flutter config --no-analytics 2>&1 | tail -1 || true
dart --disable-analytics 2>&1 || true

# ── 3. Enable web ───────────────────────────────────────────────────────
flutter config --enable-web 2>&1 | tail -1

# ── 4. Pre-cache pub dependencies ───────────────────────────────────────
echo "=== Running flutter pub get ==="
flutter pub get 2>&1 | tail -10

echo "=== Install script complete ==="
