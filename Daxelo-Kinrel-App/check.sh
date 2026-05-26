#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# KINREL Quick Check — Run before pushing to avoid Codemagic fails
# ═══════════════════════════════════════════════════════════════
export PATH="/home/z/flutter/bin:$PATH"
export ANDROID_HOME=/home/z/android-sdk
export ANDROID_SDK_ROOT=/home/z/android-sdk

cd "$(dirname "$0")"

echo "🔍 Running flutter pub get..."
flutter pub get 2>&1 | tail -3

echo ""
echo "🔍 Running flutter analyze..."
RESULT=$(flutter analyze 2>&1)

# Count errors vs warnings vs info
ERRORS=$(echo "$RESULT" | grep -c "error •" || true)
WARNINGS=$(echo "$RESULT" | grep -c "warning •" || true)

echo "$RESULT" | grep -E "error •|No issues found" || true

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "❌ BUILD WILL FAIL — $ERRORS compile error(s) found!"
  echo "$RESULT" | grep "error •"
  exit 1
else
  echo ""
  echo "✅ NO COMPILE ERRORS — Safe to push! ($WARNINGS warnings, 0 errors)"
  exit 0
fi
