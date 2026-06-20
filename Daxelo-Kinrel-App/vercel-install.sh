#!/usr/bin/env bash
# Vercel install script for the Flutter web app.
#
# Downloads a pre-built Flutter SDK tarball (faster + more reliable than
# git clone). Pinned to Flutter 3.44.2 stable, which ships Dart 3.12.2
# — matches pubspec.yaml's `sdk: ^3.12.0` constraint.
#
# Vercel preserves $HOME between builds (when cache is enabled), so the
# ~700MB SDK is only downloaded on the first build after the cache is
# invalidated. Subsequent builds skip straight to `flutter pub get`.

set -euo pipefail

echo "=== Vercel Flutter install script starting ==="
echo "Working directory: $(pwd)"
echo "HOME: $HOME"
echo "Node version: $(node --version 2>&1 || echo 'n/a')"
echo "Disk space:"
df -h . 2>&1 | head -2

# ── 1. Install Flutter SDK ──────────────────────────────────────────────
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"
FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin"
FLUTTER_TARBALL_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Check if Flutter is already cached at the right version.
# Vercel preserves $HOME between builds when cache is enabled, so this
# skips the ~700MB download on subsequent builds.
NEED_INSTALL=0
if [ ! -f "$FLUTTER_BIN/flutter" ]; then
  NEED_INSTALL=1
elif ! "$FLUTTER_BIN/flutter" --version 2>&1 | grep -q "Flutter ${FLUTTER_VERSION}"; then
  NEED_INSTALL=1
fi

if [ $NEED_INSTALL -eq 1 ]; then
  echo "=== Downloading Flutter ${FLUTTER_VERSION} (stable) ==="
  echo "URL: $FLUTTER_TARBALL_URL"
  rm -rf "$FLUTTER_HOME"
  mkdir -p "$FLUTTER_HOME"

  # Download and extract in one pipeline (no temp file needed).
  # --fail: curl exits non-zero on HTTP errors (404, 500, etc.)
  # -L: follow redirects (Google's CDN may redirect)
  # The tarball is .tar.xz — tar auto-detects compression.
  curl --fail --location --retry 3 --retry-delay 5 \
    "$FLUTTER_TARBALL_URL" \
    | tar -xJ -C "$FLUTTER_HOME" --strip-components=1

  echo "=== Flutter extracted to $FLUTTER_HOME ==="
else
  echo "=== Flutter ${FLUTTER_VERSION} already cached, skipping download ==="
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
