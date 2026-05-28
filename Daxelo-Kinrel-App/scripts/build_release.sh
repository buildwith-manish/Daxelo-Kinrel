#!/bin/bash
# DAXELO KINREL — Release Build Script
# Builds optimized APKs with code obfuscation and split per ABI

set -e

echo "🏗️  Building Daxelo Kinrel release APK..."

flutter build apk \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --dart-define=FLUTTER_WEB_USE_SKIA=true \
  --release

echo ""
echo "✅ Build complete! APK sizes:"
ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || echo "No APKs found"

echo ""
echo "📊 Size summary:"
for f in build/app/outputs/flutter-apk/*.apk; do
  name=$(basename "$f")
  size=$(du -h "$f" | cut -f1)
  echo "  $name: $size"
done
