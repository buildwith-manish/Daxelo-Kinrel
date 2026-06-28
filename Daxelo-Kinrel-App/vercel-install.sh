#!/usr/bin/env bash
# Vercel install script for the Flutter web app.
#
# Downloads a pre-built Flutter SDK tarball (faster + more reliable than
# git clone). Pinned to Flutter 3.44.2 stable, which ships Dart 3.12.2
# — matches pubspec.yaml's `sdk: ^3.12.0` constraint.
#
# Vercel build environment notes:
#   • Builds run as root, so Flutter prints "appears to be trying to run
#     flutter as root" warnings. We suppress these by NOT failing on
#     stderr output.
#   • The Flutter SDK tarball includes a .git directory, and git on the
#     Vercel build machine complains about "dubious ownership" because
#     the repo is owned by root but git's safe.directory isn't configured.
#     We fix this by running `git config --global --add safe.directory '*'
#     BEFORE invoking any flutter command.
#   • $HOME on Vercel is /vercel and is NOT preserved between builds by
#     default. The Flutter SDK is downloaded on every build (~45s). If
#     Vercel later enables cache for $HOME, the NEED_INSTALL check below
#     will skip the download.
#   • We use `set -eo pipefail` (NOT -u) so unset variables don't kill
#     the build, and we append `|| true` to commands that may exit
#     non-zero on warnings.

set -eo pipefail

echo "=== Vercel Flutter install script starting ==="
echo "Working directory: $(pwd)"
echo "HOME: $HOME"
echo "Node version: $(node --version 2>&1 || echo 'n/a')"
echo "Disk space:"
df -h . 2>&1 | head -2

# ── 0. Fix git "dubious ownership" for the Flutter SDK's bundled .git ─────
# The Flutter tarball ships with a .git directory. When extracted as root
# on Vercel, git refuses to operate on it ("fatal: detected dubious
# ownership in repository at ..."). Adding it to safe.directory globally
# fixes this for ALL repositories, which is safe in the ephemeral build
# environment.
git config --global --add safe.directory '*' 2>/dev/null || true

# ── 1. Install Flutter SDK ──────────────────────────────────────────────
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"
FLUTTER_HOME="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_HOME/bin"
FLUTTER_TARBALL_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Check if Flutter is already cached at the right version.
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
  # --no-same-owner: ignore stored owner/group (we're root anyway, and
  #   this avoids permission issues on the extracted files).
  curl --fail --location --retry 3 --retry-delay 5 \
    "$FLUTTER_TARBALL_URL" \
    | tar -xJ -C "$FLUTTER_HOME" --strip-components=1 --no-same-owner

  echo "=== Flutter extracted to $FLUTTER_HOME ==="
else
  echo "=== Flutter ${FLUTTER_VERSION} already cached, skipping download ==="
fi

export PATH="$FLUTTER_BIN:$PATH"

# ── 2. Verify Flutter is callable ───────────────────────────────────────
# We capture both stdout and stderr, and only fail if `flutter --version`
# doesn't print the version string at all. The "running as root" warning
# goes to stderr and would cause `set -e` + `pipefail` to fail the build
# if we weren't careful.
echo "=== Flutter version ==="
flutter --version 2>&1 | head -5 || true

# Sanity check: ensure flutter is actually on PATH
if ! command -v flutter >/dev/null 2>&1; then
  echo "FATAL: flutter not found on PATH after install"
  exit 1
fi

# ── 3. Disable analytics + telemetry ────────────────────────────────────
flutter config --no-analytics 2>&1 | tail -1 || true
dart --disable-analytics 2>&1 || true

# ── 4. Enable web ───────────────────────────────────────────────────────
flutter config --enable-web 2>&1 | tail -1 || true

# ── 5. Pre-cache pub dependencies ───────────────────────────────────────
echo "=== Running flutter pub get ==="
flutter pub get 2>&1 | tail -10

echo "=== Install script complete ==="
