#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# KINREL Flutter Web — Build & Serve
# Run this after code changes to see the updated app
# ═══════════════════════════════════════════════════════════════
export PATH="/home/z/flutter/bin:$PATH"
export ANDROID_HOME=/home/z/android-sdk

cd "$(dirname "$0")"

echo "🔍 Step 1: Checking for compile errors..."
flutter pub get 2>&1 | tail -1

ERRORS=$(flutter analyze 2>&1 | grep -c "error •" || true)
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS compile error(s) found! Fix before building."
  flutter analyze 2>&1 | grep "error •"
  exit 1
fi
echo "✅ No compile errors"

echo ""
echo "🔨 Step 2: Building Flutter web..."
flutter build web --release 2>&1 | tail -3

echo ""
echo "🌐 Step 3: Serving on port 8080..."

# Kill any existing server on port 8080
pkill -f "http.server 8080" 2>/dev/null
sleep 1

cd build/web
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/flutter_web_serve.log 2>&1 &
cd ..

echo ""
echo "✅ Flutter app is LIVE at port 8080!"
echo "   Preview: Use the Preview Panel with ?XTransformPort=8080"
