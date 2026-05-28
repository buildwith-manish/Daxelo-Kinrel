#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# DAXELO KINREL — Release AAB Build Script
#
# Builds a signed Android App Bundle (.aab) for Play Store upload with:
#   - Production flavor
#   - Code obfuscation
#   - Split debug info (dated folder)
#   - Release mode
#
# Prerequisites:
#   - android/key.properties must exist with signing credentials
#   - Keystore file referenced in key.properties must exist
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate project root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY_PROPERTIES="$PROJECT_DIR/android/key.properties"

# ── Pre-flight checks ───────────────────────────────────────────────────────
if [ ! -f "$KEY_PROPERTIES" ]; then
  echo "❌ android/key.properties not found!" >&2
  echo "   Copy key.properties.example and fill in your signing credentials:" >&2
  echo "   cp android/key.properties.example android/key.properties" >&2
  exit 1
fi

# Extract storeFile from key.properties and verify keystore exists
STORE_FILE=$(sed -n 's/^storeFile[[:space:]]*=[[:space:]]*//p' "$KEY_PROPERTIES" | tr -d '[:space:]')
if [ -n "$STORE_FILE" ]; then
  # storeFile is relative to android/app/ in Gradle context
  KEYSTORE_PATH="$PROJECT_DIR/android/app/$STORE_FILE"
  # Also check relative to android/ (for ../prefixed paths)
  if [[ "$STORE_FILE" == ../* ]]; then
    KEYSTORE_PATH="$PROJECT_DIR/android/$STORE_FILE"
  fi
  if [ ! -f "$KEYSTORE_PATH" ]; then
    echo "⚠️  Keystore file not found at: $KEYSTORE_PATH" >&2
    echo "   Referenced in key.properties as: $STORE_FILE" >&2
    echo "   Build may fail. Continue? (y/N)" >&2
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      exit 1
    fi
  fi
fi

# ── Build ───────────────────────────────────────────────────────────────────
DEBUG_INFO_DIR="build/debug-info/$(date +%Y%m%d)"

echo "🏗️  Building Daxelo Kinrel release AAB..."
echo "   Flavor      : prod"
echo "   Obfuscate   : yes"
echo "   Debug info  : $DEBUG_INFO_DIR"
echo ""

cd "$PROJECT_DIR"

flutter build appbundle \
  --dart-define=FLAVOR=prod \
  --obfuscate \
  --split-debug-info="$DEBUG_INFO_DIR" \
  --release

# ── Confirm ─────────────────────────────────────────────────────────────────
AAB_PATH="$PROJECT_DIR/build/app/outputs/bundle/release/app-release.aab"

echo ""
if [ -f "$AAB_PATH" ]; then
  AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
  echo "✅ AAB build complete!"
  echo ""
  echo "   📦 Path : $AAB_PATH"
  echo "   📏 Size : $AAB_SIZE"
  echo ""
  echo "   Upload this file to the Google Play Console."
else
  echo "⚠️  Build finished but AAB not found at expected path:"
  echo "   $AAB_PATH"
  echo ""
  echo "   Check build output above for errors."
  exit 1
fi
